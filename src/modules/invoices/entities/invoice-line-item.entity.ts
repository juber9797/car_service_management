import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  ManyToOne, JoinColumn,
} from 'typeorm';
import { LineItemType } from '../../../common/enums';
import { Invoice } from './invoice.entity';

@Entity('invoice_line_items')
export class InvoiceLineItem {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'invoice_id' })
  invoiceId: string;

  @Column({ name: 'garage_id' })
  garageId: string;

  @Column({ name: 'task_id', type: 'text', nullable: true })
  taskId: string | null;

  @Column({ name: 'spare_part_id', type: 'text', nullable: true })
  sparePartId: string | null;

  @Column({ name: 'item_type', type: 'varchar', length: 20 })
  itemType: LineItemType;

  @Column({ length: 500 })
  description: string;

  @Column({ type: 'real', default: 1 })
  quantity: number;

  @Column({ name: 'unit_price', type: 'real' })
  unitPrice: number;

  @Column({ name: 'sort_order', default: 0 })
  sortOrder: number;

  @ManyToOne(() => Invoice, (inv) => inv.lineItems, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'invoice_id' })
  invoice: Invoice;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
