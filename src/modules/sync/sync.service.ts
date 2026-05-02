import {
  Injectable,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { JobCard } from '../job-cards/entities/job-card.entity';
import { Task } from '../tasks/entities/task.entity';
import { PushSyncDto, SyncChangeDto } from './dto/push-sync.dto';
import { PullSyncDto } from './dto/pull-sync.dto';
import { SyncOperation, JobCardStatus } from '../../common/enums';
import { JwtPayload } from '../../common/decorators/current-user.decorator';
import { ConflictResolver } from './conflict-resolver';
import { TombstoneService } from './tombstone.service';

// ─────────────────────────────────────────────
// Response types
// ─────────────────────────────────────────────

export type ConflictResolution = 'accepted' | 'rejected' | 'merged';

export interface ChangeResult {
  changeId:      string;
  entityId:      string;
  entityType:    string;
  resolution:    ConflictResolution;
  serverVersion?: number;
  serverState?:   Record<string, unknown>;  // returned on merge/reject so client can reconcile
  conflict?: {
    reason:      string;
    fields?:     string[];
  };
}

export interface PushSyncResponse {
  accepted:   number;
  rejected:   number;
  merged:     number;
  results:    ChangeResult[];
  serverTime: string;
}

export interface SyncedEntity {
  entityType:  string;
  entityId:    string;
  operation:   SyncOperation;
  version:     number;
  serverTime:  string;
  payload:     Record<string, unknown>;
}

export interface PullSyncResponse {
  changes:     SyncedEntity[];
  tombstones:  Array<{ entityType: string; entityId: string }>;
  serverTime:  string;
  hasMore:     boolean;
  nextCursor:  string | null;
}

const SUPPORTED_ENTITIES = new Set(['job_cards', 'tasks']);
const PULL_PAGE_SIZE = 500;

@Injectable()
export class SyncService {
  private readonly logger   = new Logger(SyncService.name);
  private readonly resolver = new ConflictResolver();

  constructor(
    @InjectRepository(JobCard) private readonly jobCardRepo: Repository<JobCard>,
    @InjectRepository(Task)    private readonly taskRepo:    Repository<Task>,
    private readonly dataSource:        DataSource,
    private readonly tombstoneService:  TombstoneService,
  ) {}

  // =====================================================================
  // PUSH
  // =====================================================================

  async push(dto: PushSyncDto, user: JwtPayload): Promise<PushSyncResponse> {
    const invalid = dto.changes.filter((c) => !SUPPORTED_ENTITIES.has(c.entityType));
    if (invalid.length > 0) {
      throw new BadRequestException(
        `Unsupported entity types: ${invalid.map((c) => c.entityType).join(', ')}`,
      );
    }

    const results: ChangeResult[] = [];

    for (const change of dto.changes) {
      const result = await this.applyChange(change, dto.clientId, user);
      results.push(result);
    }

    return {
      accepted:   results.filter((r) => r.resolution === 'accepted').length,
      rejected:   results.filter((r) => r.resolution === 'rejected').length,
      merged:     results.filter((r) => r.resolution === 'merged').length,
      results,
      serverTime: new Date().toISOString(),
    };
  }

  // =====================================================================
  // PULL — returns changes + tombstones since cursor
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

    // Fetch entity changes + tombstones in parallel
    const [rows, tombstones] = await Promise.all([
      this.dataSource.query<Array<{
        entity_type: string; entity_id: string; operation: SyncOperation;
        version: number; server_time: Date; payload: Record<string, unknown>;
      }>>(
        `SELECT DISTINCT ON (entity_type, entity_id)
           entity_type, entity_id, operation, version, server_time, payload
         FROM sync_log
         WHERE garage_id   = $1
           AND server_time > $2
           AND entity_type = ANY($3)
         ORDER BY entity_type, entity_id, server_time DESC
         LIMIT $4`,
        [user.garageId, since, requestedTypes, PULL_PAGE_SIZE + 1],
      ),
      this.tombstoneService.getSince(user.garageId, since),
    ]);

    const hasMore = rows.length > PULL_PAGE_SIZE;
    const slice   = hasMore ? rows.slice(0, PULL_PAGE_SIZE) : rows;

    const changes: SyncedEntity[] = slice.map((row) => ({
      entityType: row.entity_type,
      entityId:   row.entity_id,
      operation:  row.operation,
      version:    row.version,
      serverTime: row.server_time.toISOString(),
      payload:    row.payload,
    }));

    const nextCursor = hasMore && slice.length > 0
      ? slice[slice.length - 1].server_time.toISOString()
      : null;

    return {
      changes,
      tombstones: tombstones.map((t) => ({
        entityType: t.entityType,
        entityId:   t.entityId,
      })),
      serverTime: new Date().toISOString(),
      hasMore,
      nextCursor,
    };
  }

  // =====================================================================
  // Private: apply a single change
  // =====================================================================

  private async applyChange(
    change:   SyncChangeDto,
    clientId: string,
    user:     JwtPayload,
  ): Promise<ChangeResult> {
    try {
      return await this.dataSource.transaction(async (manager) => {
        const repo = change.entityType === 'job_cards'
          ? manager.getRepository(JobCard)
          : manager.getRepository(Task);

        // ── CREATE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.CREATE) {
          const existing = await repo.findOne({
            where: { id: change.entityId } as Parameters<typeof repo.findOne>[0],
          });

          // Idempotent: already exists → return success without re-inserting
          if (existing) {
            return {
              changeId:      change.changeId,
              entityId:      change.entityId,
              entityType:    change.entityType,
              resolution:    'accepted',
              serverVersion: (existing as { version: number }).version,
            };
          }

          const entity = repo.create({
            ...change.payload,
            id:       change.entityId,
            garageId: user.garageId,
            clientId,
            version:  1,
          } as Parameters<typeof repo.create>[0]);

          const saved = await manager.save(entity);
          return {
            changeId:      change.changeId,
            entityId:      change.entityId,
            entityType:    change.entityType,
            resolution:    'accepted',
            serverVersion: (saved as { version: number }).version,
          };
        }

        // ── UPDATE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.UPDATE) {
          const current = await repo
            .createQueryBuilder('e')
            .where('e.id = :id AND e.garage_id = :gid', {
              id:  change.entityId,
              gid: user.garageId,
            })
            .setLock('pessimistic_write')
            .getOne();

          if (!current) {
            return {
              changeId:   change.changeId,
              entityId:   change.entityId,
              entityType: change.entityType,
              resolution: 'rejected',
              conflict:   { reason: 'Entity not found on server' },
            };
          }

          // Delegate to ConflictResolver
          const mergeResult = change.entityType === 'job_cards'
            ? this.resolver.resolveJobCard(
                current as unknown as Parameters<typeof this.resolver.resolveJobCard>[0],
                change.payload ?? {},
                change.baseVersion,
                new Date(change.localTimestamp),
              )
            : this.resolver.resolveTask(
                current as unknown as Parameters<typeof this.resolver.resolveTask>[0],
                change.payload ?? {},
                change.baseVersion,
                new Date(change.localTimestamp),
              );

          if (mergeResult.outcome === 'rejected') {
            return {
              changeId:    change.changeId,
              entityId:    change.entityId,
              entityType:  change.entityType,
              resolution:  'rejected',
              serverState: current as unknown as Record<string, unknown>,
              conflict:    { reason: mergeResult.reason },
            };
          }

          // Apply merged fields
          Object.assign(current, mergeResult.merged, {
            clientId,
            version: (current as { version: number }).version + 1,
          });
          const saved = await manager.save(current);

          const resolution: ConflictResolution =
            mergeResult.outcome === 'merged' ? 'merged' : 'accepted';

          return {
            changeId:      change.changeId,
            entityId:      change.entityId,
            entityType:    change.entityType,
            resolution,
            serverVersion: (saved as { version: number }).version,
            serverState:   saved as unknown as Record<string, unknown>,
            ...(mergeResult.outcome === 'merged' && {
              conflict: { fields: mergeResult.conflictFields },
            }),
          };
        }

        // ── DELETE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.DELETE) {
          const current = await repo.findOne({
            where: { id: change.entityId } as Parameters<typeof repo.findOne>[0],
          });

          // Already gone — idempotent
          if (!current) {
            return {
              changeId:   change.changeId,
              entityId:   change.entityId,
              entityType: change.entityType,
              resolution: 'accepted',
            };
          }

          // Safety rule: updates beat deletes.
          // If server version advanced past client's base, an update happened
          // after the client issued the delete — reject the delete.
          const serverVersion = (current as { version: number }).version;
          if (change.baseVersion < serverVersion) {
            return {
              changeId:    change.changeId,
              entityId:    change.entityId,
              entityType:  change.entityType,
              resolution:  'rejected',
              serverState: current as unknown as Record<string, unknown>,
              conflict: {
                reason: `Delete rejected: entity was updated after your offline session ` +
                        `(base v${change.baseVersion}, server v${serverVersion})`,
              },
            };
          }

          // Safety rule: never delete an in-progress job card
          if (
            change.entityType === 'job_cards' &&
            (current as JobCard).status === JobCardStatus.IN_PROGRESS
          ) {
            return {
              changeId:    change.changeId,
              entityId:    change.entityId,
              entityType:  change.entityType,
              resolution:  'rejected',
              serverState: current as unknown as Record<string, unknown>,
              conflict:    { reason: 'Cannot delete an in-progress job card' },
            };
          }

          await manager.softDelete(
            change.entityType === 'job_cards' ? JobCard : Task,
            change.entityId,
          );
          // Tombstone is written automatically by the DB trigger

          return {
            changeId:   change.changeId,
            entityId:   change.entityId,
            entityType: change.entityType,
            resolution: 'accepted',
          };
        }

        throw new BadRequestException(`Unknown operation: ${change.operation as string}`);
      });
    } catch (err) {
      this.logger.error(`Failed to apply change ${change.changeId}`, err);
      return {
        changeId:   change.changeId,
        entityId:   change.entityId,
        entityType: change.entityType,
        resolution: 'rejected',
        conflict:   { reason: (err as Error).message },
      };
    }
  }
}
