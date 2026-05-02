import {
  Controller, Get, Post, Patch, Body, Param,
  ParseUUIDPipe, UseGuards, Query, HttpCode, HttpStatus,
} from '@nestjs/common';
import { InvoicesService } from './invoices.service';
import { GenerateInvoiceDto } from './dto/generate-invoice.dto';
import { InvoiceStatus, UserRole } from '../../common/enums';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@Controller('invoices')
@UseGuards(JwtAuthGuard, RolesGuard)
export class InvoicesController {
  constructor(private readonly service: InvoicesService) {}

  /**
   * POST /api/v1/invoices
   * Generates an invoice from a completed job card.
   * Can auto-populate labor lines from completed tasks, or accept manual line items.
   * Applies discount and tax; all totals are server-calculated (never trust the client).
   */
  @Post()
  @Roles(UserRole.ADMIN, UserRole.RECEPTIONIST)
  generate(@Body() dto: GenerateInvoiceDto, @CurrentUser() user: JwtPayload) {
    return this.service.generate(dto, user);
  }

  /**
   * GET /api/v1/invoices?status=draft&page=1&limit=20
   */
  @Get()
  @Roles(UserRole.ADMIN, UserRole.RECEPTIONIST)
  findAll(
    @CurrentUser() user: JwtPayload,
    @Query('status') status?: InvoiceStatus,
    @Query('page') page?: number,
    @Query('limit') limit?: number,
  ) {
    return this.service.findAll(user.garageId, { status, page, limit });
  }

  /**
   * GET /api/v1/invoices/:id
   */
  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.findOne(id, user.garageId);
  }

  /**
   * PATCH /api/v1/invoices/:id/issue
   * Transitions draft → issued. Sets issued_at and due_at (net-30).
   */
  @Patch(':id/issue')
  @Roles(UserRole.ADMIN, UserRole.RECEPTIONIST)
  @HttpCode(HttpStatus.OK)
  issue(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.issue(id, user.garageId);
  }

  /**
   * PATCH /api/v1/invoices/:id/pay
   * Marks an issued invoice as paid.
   */
  @Patch(':id/pay')
  @Roles(UserRole.ADMIN, UserRole.RECEPTIONIST)
  @HttpCode(HttpStatus.OK)
  markPaid(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.service.markPaid(id, user.garageId);
  }
}
