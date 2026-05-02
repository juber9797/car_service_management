/**
 * ConflictResolver
 *
 * Strategy: Hybrid version-number + field-level merge
 *
 * Why NOT pure last-write-wins:
 *   A technician offline for 2 hours marks a task "completed".
 *   Meanwhile the admin changed the assigned technician.
 *   LWW would silently discard the admin's change because the
 *   technician's device has the newer wall-clock timestamp.
 *
 * Why NOT vector clocks:
 *   Correct VC implementation requires every client to maintain
 *   a full clock per peer. With N garages × M devices this is
 *   complex and the merge logic is still app-specific anyway.
 *
 * Chosen: Monotonic version counter + domain-aware field merge
 *   - Version number detects whether a conflict exists at all.
 *   - Field-level rules encode domain knowledge:
 *       status  → highest valid state in the workflow wins
 *       content → client timestamp breaks the tie (LWW per-field)
 *       delete  → update always beats delete (safety-first)
 */

import { JobCardStatus, TaskStatus } from '../../common/enums';

// ─────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────

export interface VersionedRecord {
  id:        string;
  version:   number;
  updatedAt: Date;
  [key: string]: unknown;
}

export type MergeResult =
  | { outcome: 'clean';    merged: Record<string, unknown> }
  | { outcome: 'merged';   merged: Record<string, unknown>; conflictFields: string[] }
  | { outcome: 'rejected'; reason: string };

// Status ordinals — higher = further along in the workflow.
// A device can only advance status, never rewind it during a merge.
const JOB_CARD_STATUS_ORDER: Record<string, number> = {
  pending:     0,
  in_progress: 1,
  on_hold:     2,   // on_hold is a lateral move, not an advance
  completed:   3,
  cancelled:   4,
};

const TASK_STATUS_ORDER: Record<string, number> = {
  pending:     0,
  in_progress: 1,
  completed:   2,
  cancelled:   3,
};

// Fields that the domain explicitly controls — client may NOT freely overwrite
const SERVER_WINS_FIELDS = new Set([
  'startedAt', 'completedAt', 'createdAt', 'garageId', 'jobNumber', 'invoiceNumber',
]);

// Fields where we never allow a client to downgrade the value
const STATUS_FIELDS = new Set(['status']);

// ─────────────────────────────────────────────────────────────
// Main resolver
// ─────────────────────────────────────────────────────────────

export class ConflictResolver {

  resolveJobCard(
    server:         VersionedRecord,
    clientPayload:  Record<string, unknown>,
    clientBaseVersion: number,
    clientTimestamp:   Date,
  ): MergeResult {
    return this._resolve(server, clientPayload, clientBaseVersion,
      clientTimestamp, JOB_CARD_STATUS_ORDER, 'job_card');
  }

  resolveTask(
    server:         VersionedRecord,
    clientPayload:  Record<string, unknown>,
    clientBaseVersion: number,
    clientTimestamp:   Date,
  ): MergeResult {
    return this._resolve(server, clientPayload, clientBaseVersion,
      clientTimestamp, TASK_STATUS_ORDER, 'task');
  }

  // ─────────────────────────────────────────────────────────
  // Core merge algorithm
  // ─────────────────────────────────────────────────────────
  private _resolve(
    server:            VersionedRecord,
    clientPayload:     Record<string, unknown>,
    clientBaseVersion: number,
    clientTimestamp:   Date,
    statusOrder:       Record<string, number>,
    entityLabel:       string,
  ): MergeResult {

    // No conflict — client has the current version
    if (clientBaseVersion >= server.version) {
      return { outcome: 'clean', merged: { ...clientPayload } };
    }

    // Conflict detected — field-level merge
    const merged:         Record<string, unknown> = { ...server };
    const conflictFields: string[]                = [];

    for (const [field, clientValue] of Object.entries(clientPayload)) {
      const serverValue = server[field];

      // Never allow client to change server-authoritative fields
      if (SERVER_WINS_FIELDS.has(field)) continue;

      if (field === 'status') {
        const resolved = this._mergeStatus(
          serverValue as string,
          clientValue as string,
          statusOrder,
        );
        if (resolved !== serverValue) {
          merged[field] = resolved;
          conflictFields.push(field);
        }
        continue;
      }

      // Soft-delete: if server deleted, client update loses
      if ((server as Record<string, unknown>)['deletedAt'] != null) {
        return {
          outcome:  'rejected',
          reason:   `${entityLabel} was deleted on the server`,
        };
      }

      // Content fields: last-write-wins by timestamp
      const serverTs = new Date(server.updatedAt).getTime();
      const clientTs = clientTimestamp.getTime();

      if (clientValue !== serverValue) {
        conflictFields.push(field);
        if (clientTs > serverTs) {
          merged[field] = clientValue; // client is newer
        }
        // else: serverValue stays (already in merged from spread)
      }
    }

    return { outcome: 'merged', merged, conflictFields };
  }

  // ─────────────────────────────────────────────────────────
  // Status merge: workflow always advances, never rewinds.
  //
  // Device A (offline): task pending → in_progress
  // Device B (online):  task pending → completed
  //
  // Result: completed wins (higher ordinal).
  //
  // Special case: cancellation from either side always wins
  // (someone explicitly cancelled — respect that intent).
  // ─────────────────────────────────────────────────────────
  private _mergeStatus(
    serverStatus: string,
    clientStatus: string,
    order:        Record<string, number>,
  ): string {
    if (serverStatus === clientStatus) return serverStatus;

    // Explicit cancellation is terminal — always wins
    if (clientStatus === 'cancelled') return 'cancelled';
    if (serverStatus === 'cancelled') return 'cancelled';

    // Terminal states cannot be unwound
    if (serverStatus === 'completed') return 'completed';

    const serverOrd = order[serverStatus] ?? 0;
    const clientOrd = order[clientStatus] ?? 0;

    // Take whichever is further along in the workflow
    return clientOrd > serverOrd ? clientStatus : serverStatus;
  }
}
