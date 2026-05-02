/**
 * TombstoneService
 *
 * Problem: when a record is soft-deleted on the server, devices
 * that were offline never receive the delete signal through a
 * normal pull (they'd just never see the row again — or worse,
 * re-create it with stale data).
 *
 * Solution: every soft-delete writes a tombstone row.
 * The pull endpoint includes tombstones in its response so
 * every client can purge its local copy.
 *
 * Tombstone retention: 90 days. After that they're pruned
 * (any device offline for 90+ days must do a full re-sync).
 */

import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, MoreThan } from 'typeorm';
import { Tombstone } from './entities/tombstone.entity';

@Injectable()
export class TombstoneService {
  constructor(
    @InjectRepository(Tombstone)
    private readonly repo: Repository<Tombstone>,
  ) {}

  async write(entityType: string, entityId: string, garageId: string): Promise<void> {
    await this.repo.upsert(
      { garageId, entityType, entityId, deletedAt: new Date() },
      { conflictPaths: ['entityType', 'entityId'] },
    );
  }

  async getSince(garageId: string, since: Date): Promise<Tombstone[]> {
    return this.repo.find({
      where: { garageId, deletedAt: MoreThan(since) },
      order: { deletedAt: 'ASC' },
    });
  }

  /** Prune tombstones older than 90 days — run as a nightly cron */
  async prune(): Promise<number> {
    const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const result = await this.repo
      .createQueryBuilder()
      .delete()
      .where('deleted_at < :cutoff', { cutoff: cutoff.toISOString() })
      .execute();
    return result.affected ?? 0;
  }
}
