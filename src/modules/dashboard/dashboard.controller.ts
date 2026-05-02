import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { DashboardService } from './dashboard.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { UserRole } from '../../common/enums';

@Controller('dashboard')
@UseGuards(JwtAuthGuard)
export class DashboardController {
  constructor(private readonly service: DashboardService) {}

  /**
   * GET /api/v1/dashboard
   *
   * Returns:
   *   - stats: { totalActive, byStatus, overdueJobs, avgCompletionTimeHours }
   *   - activeJobCards[]: each with totalTasks, completedTasks, progressPercent
   *
   * Technicians automatically see only their own assigned jobs.
   * Admins/receptionists see all unless ?technicianId= is passed.
   */
  @Get()
  getDashboard(
    @CurrentUser() user: JwtPayload,
    @Query('technicianId') technicianId?: string,
  ) {
    const filterById =
      user.role === UserRole.TECHNICIAN
        ? user.sub
        : technicianId;

    return this.service.getDashboard(user.garageId, filterById);
  }
}
