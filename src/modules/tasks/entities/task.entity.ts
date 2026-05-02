import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  UpdateDateColumn, DeleteDateColumn, Index,
} from 'typeorm';
import { TaskStatus } from '../../../common/enums';

@Entity('tasks')
export class Task {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'garage_id' })
  @Index()
  garageId: string;

  @Column({ name: 'job_card_id' })
  @Index()
  jobCardId: string;

  @Column({ name: 'assigned_to_id', nullable: true })
  @Index()
  assignedToId: string | null;

  @Column({ length: 255 })
  title: string;

  @Column({ type: 'text', nullable: true })
  description: string | null;

  @Column({ type: 'enum', enum: TaskStatus, default: TaskStatus.PENDING })
  @Index()
  status: TaskStatus;

  @Column({ name: 'estimated_hours', type: 'decimal', precision: 6, scale: 2, nullable: true })
  estimatedHours: number | null;

  @Column({ name: 'actual_hours', type: 'decimal', precision: 6, scale: 2, nullable: true })
  actualHours: number | null;

  @Column({ name: 'labor_rate', type: 'decimal', precision: 10, scale: 2, nullable: true })
  laborRate: number | null;

  @Column({ name: 'sort_order', default: 0 })
  sortOrder: number;

  @Column({ name: 'started_at', type: 'timestamptz', nullable: true })
  startedAt: Date | null;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt: Date | null;

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
