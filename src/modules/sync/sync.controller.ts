import {
  Controller, Post, Get, Body, Query, UseGuards, HttpCode, HttpStatus,
} from '@nestjs/common';
import { SyncService } from './sync.service';
import { PushSyncDto } from './dto/push-sync.dto';
import { PullSyncDto } from './dto/pull-sync.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@Controller('sync')
@UseGuards(JwtAuthGuard)
export class SyncController {
  constructor(private readonly service: SyncService) {}

  /**
   * POST /api/v1/sync/push
   *
   * Uploads a batch of local changes from an offline client.
   * Each change has a client-generated changeId for idempotency.
   * Clients may safely retry the entire batch — already-applied
   * changes are detected and return 'accepted' without re-applying.
   *
   * Conflict resolution:
   *   - status fields: server wins
   *   - metadata/notes: last-write-wins by timestamp
   *   - irreconcilable: returned as 'rejected' with server state
   *
   * The client must inspect each result.resolution:
   *   - 'accepted' → change is committed, use serverVersion
   *   - 'merged'   → partial merge, update local with serverVersion
   *   - 'rejected' → show conflict to user, discard or re-attempt
   */
  @Post('push')
  @HttpCode(HttpStatus.OK)
  push(@Body() dto: PushSyncDto, @CurrentUser() user: JwtPayload) {
    return this.service.push(dto, user);
  }

  /**
   * GET /api/v1/sync/pull?since=<ISO8601>&entityTypes=job_cards,tasks
   *
   * Returns all changes since the given cursor timestamp.
   * On first sync, omit `since` to get the full dataset.
   * Paginated at 500 records; follow nextCursor when hasMore=true.
   *
   * The 'since' timestamp should be stored by the client as
   * 'lastSyncedAt' and sent on every subsequent pull.
   */
  @Get('pull')
  pull(@Query() dto: PullSyncDto, @CurrentUser() user: JwtPayload) {
    return this.service.pull(dto, user);
  }
}
