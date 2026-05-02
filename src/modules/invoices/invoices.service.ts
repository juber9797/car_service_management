import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { Invoice } from './entities/invoice.entity';
import { InvoiceLineItem } from './entities/invoice-line-item.entity';
import { GenerateInvoiceDto, LineItemDto } from './dto/generate-invoice.dto';
import { Task } from '../tasks/entities/task.entity';
import { InvoiceStatus, LineItemType, TaskStatus } from '../../common/enums';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

@Injectable()
export class InvoicesService {
  constructor(
    @InjectRepository(Invoice)
    private readonly invoiceRepo: Repository<Invoice>,
    @InjectRepository(InvoiceLineItem)
    private readonly lineItemRepo: Repository<InvoiceLineItem>,
    @InjectRepository(Task)
    private readonly taskRepo: Repository<Task>,
    private readonly dataSource: DataSource,
  ) {}

  async generate(dto: GenerateInvoiceDto, user: JwtPayload): Promise<Invoice> {
    return this.dataSource.transaction(async (manager) => {
      const invoiceNumber = await this.nextInvoiceNumber(user.garageId);

      const invoice = manager.create(Invoice, {
        garageId: user.garageId,
        invoiceNumber,
        jobCardId: dto.jobCardId,
        customerId: dto.customerId,
        discountPct: dto.discountPct ?? 0,
        taxPct: dto.taxPct ?? 0,
        notes: dto.notes ?? null,
        createdById: user.sub,
        status: InvoiceStatus.DRAFT,
      });

      const lineItems: Partial<InvoiceLineItem>[] = [];
      let sortOrder = 0;

      // Auto-populate labor lines from completed tasks
      if (dto.autoPopulateFromTasks) {
        const completedTasks = await this.taskRepo.find({
          where: {
            jobCardId: dto.jobCardId,
            garageId: user.garageId,
            status: TaskStatus.COMPLETED,
          },
        });

        for (const task of completedTasks) {
          const hours = Number(task.actualHours ?? task.estimatedHours ?? 0);
          const rate = Number(task.laborRate ?? 0);
          if (hours > 0 && rate > 0) {
            lineItems.push({
              garageId: user.garageId,
              taskId: task.id,
              itemType: LineItemType.LABOR,
              description: task.title,
              quantity: hours,
              unitPrice: rate,
              sortOrder: sortOrder++,
            });
          }
        }
      }

      // Append any additional / spare-part items
      for (const item of dto.additionalItems ?? []) {
        lineItems.push({
          garageId: user.garageId,
          taskId: item.taskId ?? null,
          sparePartId: item.sparePartId ?? null,
          itemType: item.itemType,
          description: item.description,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          sortOrder: item.sortOrder ?? sortOrder++,
        });
      }

      if (lineItems.length === 0) {
        throw new BadRequestException('Invoice must have at least one line item');
      }

      // Calculate totals — all arithmetic in JS to avoid floating-point surprises
      const subtotal = lineItems.reduce(
        (sum, li) => sum + Number(li.quantity) * Number(li.unitPrice),
        0,
      );
      const discountAmount = (subtotal * (dto.discountPct ?? 0)) / 100;
      const taxableAmount = subtotal - discountAmount;
      const taxAmount = (taxableAmount * (dto.taxPct ?? 0)) / 100;
      const total = taxableAmount + taxAmount;

      invoice.subtotal = this.round(subtotal);
      invoice.discountAmount = this.round(discountAmount);
      invoice.taxAmount = this.round(taxAmount);
      invoice.total = this.round(total);

      const saved = await manager.save(invoice);

      const items = lineItems.map((li) =>
        manager.create(InvoiceLineItem, { ...li, invoiceId: saved.id }),
      );
      await manager.save(items);

      return manager.findOneOrFail(Invoice, {
        where: { id: saved.id },
        relations: ['lineItems'],
      });
    });
  }

  async findAll(
    garageId: string,
    filters: { status?: InvoiceStatus; page?: number; limit?: number },
  ): Promise<{ data: Invoice[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = Math.min(filters.limit ?? 20, 100);

    const qb = this.invoiceRepo
      .createQueryBuilder('inv')
      .leftJoinAndSelect('inv.lineItems', 'li')
      .where('inv.garage_id = :garageId', { garageId })
      .andWhere('inv.deleted_at IS NULL')
      .orderBy('inv.created_at', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (filters.status) qb.andWhere('inv.status = :status', { status: filters.status });

    const [data, total] = await qb.getManyAndCount();
    return { data, total };
  }

  async findOne(id: string, garageId: string): Promise<Invoice> {
    const invoice = await this.invoiceRepo.findOne({
      where: { id, garageId },
      relations: ['lineItems'],
    });
    if (!invoice) throw new NotFoundException(`Invoice ${id} not found`);
    return invoice;
  }

  async issue(id: string, garageId: string): Promise<Invoice> {
    const invoice = await this.findOne(id, garageId);
    if (invoice.status !== InvoiceStatus.DRAFT) {
      throw new BadRequestException('Only draft invoices can be issued');
    }
    invoice.status = InvoiceStatus.ISSUED;
    invoice.issuedAt = new Date();
    invoice.dueAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // net-30
    invoice.version += 1;
    return this.invoiceRepo.save(invoice);
  }

  async markPaid(id: string, garageId: string): Promise<Invoice> {
    const invoice = await this.findOne(id, garageId);
    if (![InvoiceStatus.ISSUED, InvoiceStatus.OVERDUE].includes(invoice.status)) {
      throw new BadRequestException('Only issued or overdue invoices can be marked paid');
    }
    invoice.status = InvoiceStatus.PAID;
    invoice.paidAt = new Date();
    invoice.version += 1;
    return this.invoiceRepo.save(invoice);
  }

  private async nextInvoiceNumber(garageId: string): Promise<string> {
    const [row] = await this.dataSource.query<[{ count: string }]>(
      `SELECT COUNT(*) AS count FROM invoices WHERE garage_id = ?`,
      [garageId],
    );
    const seq = parseInt(row.count, 10) + 1;
    return `INV-${new Date().getFullYear()}-${String(seq).padStart(5, '0')}`;
  }

  private round(value: number): number {
    return Math.round(value * 100) / 100;
  }
}
