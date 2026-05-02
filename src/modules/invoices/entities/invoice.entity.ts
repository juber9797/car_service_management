import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  UpdateDateColumn, DeleteDateColumn, Index, OneToMany,
} from 'typeorm';
import { InvoiceStatus } from '../../../common/enums';
import { InvoiceLineItem } from './invoice-line-item.entity';

@Entity('invoices')
@Index(['invoiceNumber', 'garageId'], { unique: true })
export class Invoice {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'garage_id' })
  @Index()
  garageId: string;

  @Column({ name: 'invoice_number', length: 20 })
  invoiceNumber: string;

  @Column({ name: 'job_card_id' })
  @Index()
  jobCardId: string;

  @Column({ name: 'customer_id' })
  @Index()
  customerId: string;

  @Column({ type: 'varchar', length: 30, default: InvoiceStatus.DRAFT })
  @Index()
  status: InvoiceStatus;

  @Column({ type: 'real', default: 0 })
  subtotal: number;

  @Column({ name: 'discount_pct', type: 'real', default: 0 })
  discountPct: number;

  @Column({ name: 'discount_amount', type: 'real', default: 0 })
  discountAmount: number;

  @Column({ name: 'tax_pct', type: 'real', default: 0 })
  taxPct: number;

  @Column({ name: 'tax_amount', type: 'real', default: 0 })
  taxAmount: number;

  @Column({ type: 'real', default: 0 })
  total: number;

  @Column({ type: 'text', nullable: true })
  notes: string | null;

  @Column({ name: 'issued_at', type: 'datetime', nullable: true })
  issuedAt: Date | null;

  @Column({ name: 'due_at', type: 'datetime', nullable: true })
  dueAt: Date | null;

  @Column({ name: 'paid_at', type: 'datetime', nullable: true })
  paidAt: Date | null;

  @Column({ default: 1 })
  version: number;

  @Column({ name: 'created_by_id', type: 'text', nullable: true })
  createdById: string | null;

  @OneToMany(() => InvoiceLineItem, (item) => item.invoice, { cascade: true, eager: true })
  lineItems: InvoiceLineItem[];

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;

  @DeleteDateColumn({ name: 'deleted_at' })
  deletedAt: Date | null;
}
