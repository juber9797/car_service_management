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
  serverState?:   Record<string, unknown>;
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
  // PULL — queries entities directly by updatedAt; no sync_log trigger needed
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

    const includeJobCards = requestedTypes.includes('job_cards');
    const includeTasks    = requestedTypes.includes('tasks');

    const [jobCards, tasks, tombstones] = await Promise.all([
      includeJobCards
        ? this.jobCardRepo.find({
            where: { garageId: user.garageId, updatedAt: MoreThan(since) },
            withDeleted: true,
            order: { updatedAt: 'ASC' },
            take: PULL_PAGE_SIZE + 1,
          })
        : Promise.resolve([] as JobCard[]),
      includeTasks
        ? this.taskRepo.find({
            where: { garageId: user.garageId, updatedAt: MoreThan(since) },
            withDeleted: true,
            order: { updatedAt: 'ASC' },
            take: PULL_PAGE_SIZE + 1,
          })
        : Promise.resolve([] as Task[]),
      this.tombstoneService.getSince(user.garageId, since),
    ]);

    // Merge both streams, sort by updatedAt ascending, then paginate
    const allChanges: SyncedEntity[] = [
      ...jobCards.map((jc) => ({
        entityType: 'job_cards',
        entityId:   jc.id,
        operation:  jc.deletedAt ? SyncOperation.DELETE : SyncOperation.UPDATE,
        version:    jc.version,
        serverTime: jc.updatedAt,
        payload:    jc as unknown as Record<string, unknown>,
      })),
      ...tasks.map((t) => ({
        entityType: 'tasks',
        entityId:   t.id,
        operation:  t.deletedAt ? SyncOperation.DELETE : SyncOperation.UPDATE,
        version:    t.version,
        serverTime: t.updatedAt,
        payload:    t as unknown as Record<string, unknown>,
      })),
    ]
      .sort((a, b) => (a.serverTime as unknown as Date).getTime() - (b.serverTime as unknown as Date).getTime())
      .map((c) => ({
        ...c,
        serverTime: (c.serverTime as unknown as Date).toISOString(),
      }));

    const hasMore  = allChanges.length > PULL_PAGE_SIZE;
    const slice    = hasMore ? allChanges.slice(0, PULL_PAGE_SIZE) : allChanges;
    const nextCursor = hasMore && slice.length > 0
      ? slice[slice.length - 1].serverTime
      : null;

    return {
      changes:    slice,
      tombstones: tombstones.map((t) => ({ entityType: t.entityType, entityId: t.entityId })),
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
    // Typed as a wide repo so TypeScript accepts findOne/create calls on either entity
    type AnyEntity = { id: string; garageId: string; version: number; [k: string]: unknown };

    try {
      return await this.dataSource.transaction(async (manager) => {
        const repo = (change.entityType === 'job_cards'
          ? manager.getRepository(JobCard)
          : manager.getRepository(Task)) as unknown as import('typeorm').Repository<AnyEntity>;

        // ── CREATE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.CREATE) {
          const existing = await repo.findOne({ where: { id: change.entityId } });

          if (existing) {
            return {
              changeId:      change.changeId,
              entityId:      change.entityId,
              entityType:    change.entityType,
              resolution:    'accepted' as const,
              serverVersion: existing.version,
            };
          }

          const entity = repo.create({
            ...change.payload,
            id:       change.entityId,
            garageId: user.garageId,
            clientId,
            version:  1,
          });

          const saved = await manager.save(entity);
          return {
            changeId:      change.changeId,
            entityId:      change.entityId,
            entityType:    change.entityType,
            resolution:    'accepted' as const,
            serverVersion: (saved as AnyEntity).version,
          };
        }

        // ── UPDATE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.UPDATE) {
          // SQLite serialises writes within a transaction — no row lock needed
          const current = await repo.findOne({
            where: { id: change.entityId, garageId: user.garageId },
          });

          if (!current) {
            return {
              changeId:   change.changeId,
              entityId:   change.entityId,
              entityType: change.entityType,
              resolution: 'rejected' as const,
              conflict:   { reason: 'Entity not found on server' },
            };
          }

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
              resolution:  'rejected' as const,
              serverState: current as Record<string, unknown>,
              conflict:    { reason: mergeResult.reason },
            };
          }

          Object.assign(current, mergeResult.merged, {
            clientId,
            version: current.version + 1,
          });
          const saved = await manager.save(current) as AnyEntity;

          const resolution: ConflictResolution =
            mergeResult.outcome === 'merged' ? 'merged' : 'accepted';

          return {
            changeId:      change.changeId,
            entityId:      change.entityId,
            entityType:    change.entityType,
            resolution,
            serverVersion: saved.version,
            serverState:   saved as Record<string, unknown>,
            ...(mergeResult.outcome === 'merged' && {
              conflict: {
                reason: 'Field-level merge applied',
                fields: mergeResult.conflictFields,
              },
            }),
          };
        }

        // ── DELETE ────────────────────────────────────────────────────────
        if (change.operation === SyncOperation.DELETE) {
          const current = await repo.findOne({ where: { id: change.entityId } });

          if (!current) {
            return {
              changeId:   change.changeId,
              entityId:   change.entityId,
              entityType: change.entityType,
              resolution: 'accepted',
            };
          }

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

          if (
            change.entityType === 'job_cards' &&
            (current as unknown as JobCard).status === JobCardStatus.IN_PROGRESS
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

          // Write tombstone so offline clients can purge their local copy
          await this.tombstoneService.write(change.entityType, change.entityId, user.garageId);

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
