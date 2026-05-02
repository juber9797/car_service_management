import {
  Controller, Get, Post, Patch, Body, Param,
  ParseUUIDPipe, UseGuards, Query,
} from '@nestjs/common';
import { TasksService } from './tasks.service';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskStatusDto } from './dto/update-task-status.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@Controller('tasks')
@UseGuards(JwtAuthGuard, RolesGuard)
export class TasksController {
  constructor(private readonly service: TasksService) {}

  /**
   * POST /api/v1/tasks
   * Add a new task to a job card.
   */
  @Post()
  create(@Body() dto: CreateTaskDto, @CurrentUser() user: JwtPayload) {
    return this.service.create(dto, user);
  }

  /**
   * GET /api/v1/tasks?jobCardId=<uuid>
   * All tasks for a specific job card, ordered by sort_order.
   */
  @Get()
  findByJobCard(
    @Query('jobCardId', ParseUUIDPipe) jobCardId: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.findByJobCard(jobCardId, user.garageId);
  }

  /**
   * GET /api/v1/tasks/:id
   */
  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.findOne(id, user.garageId);
  }

  /**
   * PATCH /api/v1/tasks/:id/status
   * Move task through: pending → in_progress → completed
   * Records immutable audit trail in task_status_history.
   * Requires version for optimistic locking.
   */
  @Patch(':id/status')
  updateStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateTaskStatusDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.updateStatus(id, dto, user);
  }

  /**
   * GET /api/v1/tasks/:id/history
   * Full status change audit log for a task.
   */
  @Get(':id/history')
  getHistory(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.getStatusHistory(id, user.garageId);
  }

  /**
   * PATCH /api/v1/tasks/:id/assign
   * Quickly reassign a task to another technician.
   */
  @Patch(':id/assign')
  assign(
    @Param('id', ParseUUIDPipe) id: string,
    @Body('assignedToId', ParseUUIDPipe) assignedToId: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.assign(id, assignedToId, user);
  }
}
