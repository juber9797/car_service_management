import {
  Controller, Get, Post, Patch, Delete, Body, Param, Query,
  ParseUUIDPipe, UseGuards, HttpCode, HttpStatus,
} from '@nestjs/common';
import { JobCardsService } from './job-cards.service';
import { CreateJobCardDto } from './dto/create-job-card.dto';
import { UpdateJobCardDto } from './dto/update-job-card.dto';
import { JobCardStatus, UserRole } from '../../common/enums';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@Controller('job-cards')
@UseGuards(JwtAuthGuard, RolesGuard)
export class JobCardsController {
  constructor(private readonly service: JobCardsService) {}

  /**
   * POST /api/v1/job-cards
   * Roles: admin, receptionist
   * Creates a new job card and auto-generates job number.
   */
  @Post()
  @Roles(UserRole.ADMIN, UserRole.RECEPTIONIST)
  create(
    @Body() dto: CreateJobCardDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.create(dto, user);
  }

  /**
   * GET /api/v1/job-cards
   * All roles.
   * Supports: ?status=in_progress&assignedToId=<uuid>&page=1&limit=20
   */
  @Get()
  findAll(
    @CurrentUser() user: JwtPayload,
    @Query('status') status?: JobCardStatus,
    @Query('assignedToId') assignedToId?: string,
    @Query('page') page?: number,
    @Query('limit') limit?: number,
  ) {
    return this.service.findAll(user.garageId, { status, assignedToId, page, limit });
  }

  /**
   * GET /api/v1/job-cards/:id
   */
  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.findOne(id, user.garageId);
  }

  /**
   * PATCH /api/v1/job-cards/:id
   * Updates status, assignment, or metadata. Requires version for optimistic locking.
   */
  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateJobCardDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.update(id, dto, user);
  }

  /**
   * DELETE /api/v1/job-cards/:id
   * Soft delete. Admin only.
   */
  @Delete(':id')
  @Roles(UserRole.ADMIN)
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.softDelete(id, user.garageId);
  }
}
