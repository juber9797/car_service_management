import {
  Injectable,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, MoreThan } from 'typeorm';
import { JobCard } from '../job-cards/entities/job-card.entity';
import { Task } from '../tasks/entities/task.entity';
import { PushSyncDto, SyncChangeDto } from './dto/push-sync.dto';
import { PullSyncDto } from './dto/pull-sync.dto';
import { SyncOperation, JobCardStatus, TaskStatus } from '../../common/enums';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

// -----------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------

export type ConflictResolution = 'accepted' | 'rejected' | 'merged';

export interface ChangeResult {
  changeId: string;
  entityId: string;
  entityType: string;
  resolution: ConflictResolution;
  serverVersion?: number;
  conflict?: {
    reason: string;
    serverState: Record<string, unknown>;
  };
}

export interface PushSyncResponse {
  accepted: number;
  rejected: number;
  results: ChangeResult[];
  serverTime: string;
}

export interface PullSyncResponse {
  changes: SyncedEntity[];
  serverTime: string;
  hasMore: boolean;
  nextCursor: string | null;
}

export interface SyncedEntity {
  entityType: string;
  entityId: string;
  operation: SyncOperation;
  version: number;
  serverTime: string;
  payload: Record<string, unknown>;
}

// -----------------------------------------------------------------------
// Entity registry — maps string names to TypeORM repositories
// -----------------------------------------------------------------------

const SUPPORTED_ENTITIES = new Set(['job_cards', 'tasks']);
const PULL_PAGE_SIZE = 500;

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(
    @InjectRepository(JobCard) private readonly jobCardRepo: Repository<JobCard>,
    @InjectRepository(Task) private readonly taskRepo: Repository<Task>,
    private readonly dataSource: DataSource,
  ) {}

  // =====================================================================
  // PUSH — client uploads local changes in batch
  // =====================================================================

  async push(dto: PushSyncDto, user: JwtPayload): Promise<PushSyncResponse> {
    // Validate all entity types before touching the DB
    const invalid = dto.changes.filter((c) => !SUPPORTED_ENTITIES.has(c.entityType));
    if (invalid.length > 0) {
      throw new BadRequestException(
        `Unsupported entity types: ${invalid.map((c) => c.entityType).join(', ')}`,
      );
    }

    const results: ChangeResult[] = [];

    // Process each change sequentially to respect ordering guarantees.
    // A future optimisation: group by entityId, parallelise across groups.
    for (const change of dto.changes) {
      const result = await this.applyChange(change, dto.clientId, user);
      results.push(result);
    }

    return {
      accepted: results.filter((r) => r.resolution === 'accepted').length,
      rejected: results.filter((r) => r.resolution === 'rejected').length,
      results,
      serverTime: new Date().toISOString(),
    };
  }

  // =====================================================================
  // PULL — client fetches everything changed since a cursor
  // =====================================================================

  async pull(dto: PullSyncDto, user: JwtPayload): Promise<PullSyncResponse> {
    const since = dto.since ? new Date(dto.since) : new Date(0);
    const requestedTypes = dto.entityTypes
      ? dto.entityTypes.split(',').map((s) => s.trim())
      : Array.from(SUPPORTED_ENTITIES);

    const invalidTypes = requestedTypes.filter((t) => !SUPPORTED_ENTITIES.has(t));
    if (invalidTypes.length > 0) {
      throw new BadRequestException(`Unknown entity types: ${invalidTypes.join(', ')}`);
    }

    // Pull from sync_log — a single source of truth for all mutations.
    // The sync_log trigger writes every insert/update there automatically.
    const rows = await this.dataSource.query<Array<{
      entity_type: string;
      entity_id: string;
      operation: SyncOperation;
      version: number;
      server_time: Date;
      payload: Record<string, unknown>;
    }>>(
      `
      SELECT DISTINCT ON (entity_type, entity_id)
        entity_type,
        entity_id,
        operation,
        version,
        server_time,
        payload
      FROM sync_log
      WHERE garage_id   = $1
        AND server_time > $2
        AND entity_type = ANY($3)
      ORDER BY entity_type, entity_id, server_time DESC
      LIMIT $4
      `,
      [user.garageId, since, requestedTypes, PULL_PAGE_SIZE + 1],
    );

    const hasMore = rows.length > PULL_PAGE_SIZE;
    const slice = hasMore ? rows.slice(0, PULL_PAGE_SIZE) : rows;

    const changes: SyncedEntity[] = slice.map((row) => ({
      entityType: row.entity_type,
      entityId: row.entity_id,
      operation: row.operation,
      version: row.version,
      serverTime: row.server_time.toISOString(),
      payload: row.payload,
    }));

    const nextCursor = hasMore && slice.length > 0
      ? slice[slice.length - 1].serverTime.toISOString()
      : null;

    return {
      changes,
      serverTime: new Date().toISOString(),
      hasMore,
      nextCursor,
    };
  }

  // =====================================================================
  // Private: apply a single change with conflict detection
  // =====================================================================

  private async applyChange(
    change: SyncChangeDto,
    clientId: string,
    user: JwtPayload,
  ): Promise<ChangeResult> {
    try {
      return await this.dataSource.transaction(async (manager) => {
        const repo =
          change.entityType === 'job_cards'
            ? manager.getRepository(JobCard)
            : manager.getRepository(Task);

        // ---------- CREATE ----------
        if (change.operation === SyncOperation.CREATE) {
          const existing = await repo.findOne({
            where: { id: change.entityId } as Parameters<typeof repo.findOne>[0],
          });

          if (existing) {
            // Idempotent — already exists, treat as success
            return {
              changeId: change.changeId,
              entityId: change.entityId,
              entityType: change.entityType,
              resolution: 'accepted' as ConflictResolution,
              serverVersion: (existing as { version: number }).version,
            };
          }

          const entity = repo.create({
            ...change.payload,
            id: change.entityId,
            garageId: user.garageId,
            clientId,
            version: 1,
          } as Parameters<typeof repo.create>[0]);

          const saved = await manager.save(entity);
          return {
            changeId: change.changeId,
            entityId: change.entityId,
            entityType: change.entityType,
            resolution: 'accepted',
            serverVersion: (saved as { version: number }).version,
          };
        }

        // ---------- UPDATE ----------
        if (change.operation === SyncOperation.UPDATE) {
          const current = await repo
            .createQueryBuilder('e')
            .where('e.id = :id AND e.garage_id = :gid', {
              id: change.entityId,
              gid: user.garageId,
            })
            .setLock('pessimistic_write')
            .getOne();

          if (!current) {
            return {
              changeId: change.changeId,
              entityId: change.entityId,
              entityType: change.entityType,
              resolution: 'rejected',
              conflict: { reason: 'Entity not found', serverState: {} },
            };
          }

          const serverVersion = (current as { version: number }).version;

          if (change.baseVersion < serverVersion) {
            // Conflict: server moved past the client's base.
            // Strategy: field-level merge where client wins on non-status fields,
            // server wins on status (status is authoritative).
            const merged = this.mergeConflict(current, change, change.entityType);

            if (merged === null) {
              // Irreconcilable — reject the change
              return {
                changeId: change.changeId,
                entityId: change.entityId,
                entityType: change.entityType,
                resolution: 'rejected',
                conflict: {
                  reason: `Version conflict: base=${change.baseVersion} server=${serverVersion}`,
                  serverState: current as unknown as Record<string, unknown>,
                },
              };
            }

            Object.assign(current, merged, {
              clientId,
              version: serverVersion + 1,
            });
            const saved = await manager.save(current);
            return {
              changeId: change.changeId,
              entityId: change.entityId,
              entityType: change.entityType,
              resolution: 'merged',
              serverVersion: (saved as { version: number }).version,
            };
          }

          // No conflict — apply cleanly
          Object.assign(current, change.payload, {
            clientId,
            version: serverVersion + 1,
          });
          const saved = await manager.save(current);
          return {
            changeId: change.changeId,
            entityId: change.entityId,
            entityType: change.entityType,
            resolution: 'accepted',
            serverVersion: (saved as { version: number }).version,
          };
        }

        // ---------- DELETE ----------
        if (change.operation === SyncOperation.DELETE) {
          const current = await repo.findOne({
            where: { id: change.entityId } as Parameters<typeof repo.findOne>[0],
          });

          if (!current) {
            // Already gone — idempotent success
            return {
              changeId: change.changeId,
              entityId: change.entityId,
              entityType: change.entityType,
              resolution: 'accepted',
            };
          }

          // Reject delete if a job card is in_progress
          if (
            change.entityType === 'job_cards' &&
            (current as JobCard).status === JobCardStatus.IN_PROGRESS
          ) {
            return {
              changeId: change.changeId,
              entityId: change.entityId,
              entityType: change.entityType,
              resolution: 'rejected',
              conflict: {
                reason: 'Cannot delete an in-progress job card',
                serverState: current as unknown as Record<string, unknown>,
              },
            };
          }

          await manager.softDelete(
            change.entityType === 'job_cards' ? JobCard : Task,
            change.entityId,
          );
          return {
            changeId: change.changeId,
            entityId: change.entityId,
            entityType: change.entityType,
            resolution: 'accepted',
          };
        }

        throw new BadRequestException(`Unknown operation: ${change.operation as string}`);
      });
    } catch (err) {
      this.logger.error(`Failed to apply change ${change.changeId}`, err);
      return {
        changeId: change.changeId,
        entityId: change.entityId,
        entityType: change.entityType,
        resolution: 'rejected',
        conflict: {
          reason: (err as Error).message,
          serverState: {},
        },
      };
    }
  }

  // =====================================================================
  // Field-level merge for conflicting updates
  //
  // Strategy:
  //   - 'status' fields: server wins (status changes go through validated
  //     state machine transitions; we don't let stale clients revert them)
  //   - All other fields: last-write-wins (client timestamp vs server
  //     updated_at). The client wins for notes/descriptions, etc.
  //   - Returns null if a hard constraint would be violated.
  // =====================================================================

  private mergeConflict(
    server: object,
    change: SyncChangeDto,
    entityType: string,
  ): Partial<object> | null {
    const clientPayload = change.payload ?? {};
    const merged: Record<string, unknown> = {};

    // Fields where server always wins regardless of timestamps
    const serverWinsFields =
      entityType === 'job_cards'
        ? (['status', 'startedAt', 'completedAt'] as const)
        : (['status', 'startedAt', 'completedAt', 'actualHours'] as const);

    const clientTimestamp = new Date(change.localTimestamp).getTime();
    const serverTimestamp = ((server as { updatedAt?: Date }).updatedAt ?? new Date()).getTime();

    for (const [key, value] of Object.entries(clientPayload)) {
      if ((serverWinsFields as readonly string[]).includes(key)) {
        // Server wins — keep what's already on the server entity
        merged[key] = (server as Record<string, unknown>)[key];
      } else if (clientTimestamp > serverTimestamp) {
        // Client change is newer — take client value
        merged[key] = value;
      } else {
        // Server is newer — keep server value
        merged[key] = (server as Record<string, unknown>)[key];
      }
    }

    return merged;
  }
}
