import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  UpdateDateColumn, DeleteDateColumn, Index, ManyToOne, JoinColumn,
} from 'typeorm';
import { JobCardStatus } from '../../../common/enums';

@Entity('job_cards')
@Index(['jobNumber', 'garageId'], { unique: true })
export class JobCard {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'garage_id' })
  @Index()
  garageId: string;

  @Column({ name: 'job_number', length: 20 })
  jobNumber: string;

  @Column({ name: 'vehicle_id' })
  @Index()
  vehicleId: string;

  @Column({ name: 'customer_id' })
  @Index()
  customerId: string;

  @Column({ name: 'assigned_to_id', nullable: true })
  assignedToId: string | null;

  @Column({ type: 'enum', enum: JobCardStatus, default: JobCardStatus.PENDING })
  @Index()
  status: JobCardStatus;

  @Column({ type: 'text' })
  description: string;

  @Column({ name: 'estimated_hours', type: 'decimal', precision: 6, scale: 2, nullable: true })
  estimatedHours: number | null;

  @Column({ name: 'actual_hours', type: 'decimal', precision: 6, scale: 2, nullable: true })
  actualHours: number | null;

  @Column({ name: 'mileage_in', type: 'int', nullable: true })
  mileageIn: number | null;

  @Column({ name: 'mileage_out', type: 'int', nullable: true })
  mileageOut: number | null;

  @Column({ name: 'promised_at', type: 'timestamptz', nullable: true })
  promisedAt: Date | null;

  @Column({ name: 'started_at', type: 'timestamptz', nullable: true })
  startedAt: Date | null;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt: Date | null;

  @Column({ type: 'text', nullable: true })
  notes: string | null;

  @Column({ name: 'internal_notes', type: 'text', nullable: true })
  internalNotes: string | null;

  @Column({ default: 1 })
  version: number;

  @Column({ name: 'client_id', length: 100, nullable: true })
  clientId: string | null;

  @Column({ name: 'created_by_id', nullable: true })
  createdById: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  @Index()
  updatedAt: Date;

  @DeleteDateColumn({ name: 'deleted_at', type: 'timestamptz' })
  deletedAt: Date | null;
}
