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
import { DataSource } from 'typeorm';

export interface Tombstone {
  entityType: string;
  entityId:   string;
  deletedAt:  Date;
}

@Injectable()
export class TombstoneService {
  constructor(private readonly dataSource: DataSource) {}

  async write(entityType: string, entityId: string, garageId: string): Promise<void> {
    await this.dataSource.query(
      `INSERT INTO tombstones(garage_id, entity_type, entity_id, deleted_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (entity_type, entity_id) DO UPDATE SET deleted_at = NOW()`,
      [garageId, entityType, entityId],
    );
  }

  async getSince(garageId: string, since: Date): Promise<Tombstone[]> {
    return this.dataSource.query<Tombstone[]>(
      `SELECT entity_type AS "entityType", entity_id AS "entityId", deleted_at AS "deletedAt"
       FROM tombstones
       WHERE garage_id = $1 AND deleted_at > $2
       ORDER BY deleted_at ASC`,
      [garageId, since],
    );
  }

  /** Prune tombstones older than 90 days — run as a nightly cron */
  async prune(): Promise<number> {
    const result = await this.dataSource.query<[{ count: string }]>(
      `DELETE FROM tombstones WHERE deleted_at < NOW() - INTERVAL '90 days'
       RETURNING 1`,
    );
    return result.length;
  }
}
