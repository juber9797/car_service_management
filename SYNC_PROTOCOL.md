# Offline-First Sync Protocol

## API Contract

### POST /api/v1/sync/push

**Request**
```json
{
  "clientId": "device-uuid-stable-per-install",
  "changes": [
    {
      "changeId":       "client-generated-uuid",
      "entityType":     "job_cards | tasks",
      "entityId":       "uuid-of-the-record",
      "operation":      "create | update | delete",
      "payload":        { "status": "in_progress", "assignedToId": "..." },
      "baseVersion":    3,
      "localTimestamp": "2024-01-15T10:30:00.000Z"
    }
  ]
}
```

**Response**
```json
{
  "accepted": 2,
  "rejected": 1,
  "merged":   1,
  "results": [
    {
      "changeId":      "...",
      "resolution":    "accepted",
      "serverVersion": 4
    },
    {
      "changeId":      "...",
      "resolution":    "merged",
      "serverVersion": 5,
      "serverState":   { "status": "completed", "version": 5, "..." : "..." },
      "conflict":      { "fields": ["status"] }
    },
    {
      "changeId":      "...",
      "resolution":    "rejected",
      "serverState":   { "..." },
      "conflict":      { "reason": "Delete rejected: entity was updated after your offline session" }
    }
  ],
  "serverTime": "2024-01-15T10:31:00.000Z"
}
```

---

### GET /api/v1/sync/pull

**Query params**
```
?since=2024-01-15T10:00:00.000Z   (ISO-8601, omit for full sync)
&entityTypes=job_cards,tasks       (comma-separated, omit for all)
```

**Response**
```json
{
  "changes": [
    {
      "entityType": "tasks",
      "entityId":   "uuid",
      "operation":  "update",
      "version":    5,
      "serverTime": "2024-01-15T10:30:45.000Z",
      "payload":    { "status": "completed", "completedAt": "..." }
    }
  ],
  "tombstones": [
    { "entityType": "job_cards", "entityId": "deleted-uuid" }
  ],
  "serverTime": "2024-01-15T10:31:00.000Z",
  "hasMore":    false,
  "nextCursor": null
}
```

---

## Conflict Resolution Matrix

| Scenario | Rule | Reason |
|---|---|---|
| Both devices update `status` | **Higher workflow state wins** | Jobs only advance; reverting is never correct |
| Device A sets `status=completed`, Device B sets `status=cancelled` | **`cancelled` wins** | Explicit cancellation is intentional; must be respected |
| Both devices update `notes` | **Last-write-wins by `localTimestamp`** | Notes are low-stakes content |
| Device A updates a task, Device B deletes the same task | **Update wins** | Safety-first; a delete of an updated record is likely stale intent |
| Device A deletes a job card that Device B updated | **Rejected** | Server version > client baseVersion signals a concurrent update happened |
| Client sends same `changeId` twice | **Idempotent — returns `accepted`** | Network retry safety |

---

## Failure Handling

| Failure | Behavior |
|---|---|
| Network drops mid-push | Entire batch is in `syncing` state; next cycle retries all of them (markSyncing is idempotent) |
| Server returns 5xx | Full cycle fails; exponential backoff schedules retry (2s, 4s, 8s … 5 min cap) |
| One item in batch rejected | Other items in the batch still processed; rejected item incremented retryCount |
| retryCount reaches 3 | Item stays in queue with `status=failed`; shown in UI as unresolved conflict |
| Device offline for >90 days | Tombstones pruned; device must do a full re-sync (omit `since` parameter) |
| Duplicate push (same changeId) | Server detects via idempotency key; returns `accepted` without re-applying |
| Pull response truncated (hasMore=true) | Client loops, advancing `nextCursor` until `hasMore=false` |
