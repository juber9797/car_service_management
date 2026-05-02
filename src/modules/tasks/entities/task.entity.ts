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

  @Column({ name: 'assigned_to_id', type: 'text', nullable: true })
  @Index()
  assignedToId: string | null;

  @Column({ length: 255 })
  title: string;

  @Column({ type: 'text', nullable: true })
  description: string | null;

  @Column({ type: 'varchar', length: 30, default: TaskStatus.PENDING })
  @Index()
  status: TaskStatus;

  @Column({ name: 'estimated_hours', type: 'real', nullable: true })
  estimatedHours: number | null;

  @Column({ name: 'actual_hours', type: 'real', nullable: true })
  actualHours: number | null;

  @Column({ name: 'labor_rate', type: 'real', nullable: true })
  laborRate: number | null;

  @Column({ name: 'sort_order', default: 0 })
  sortOrder: number;

  @Column({ name: 'started_at', type: 'datetime', nullable: true })
  startedAt: Date | null;

  @Column({ name: 'completed_at', type: 'datetime', nullable: true })
  completedAt: Date | null;

  @Column({ default: 1 })
  version: number;

  @Column({ name: 'client_id', type: 'varchar', length: 100, nullable: true })
  clientId: string | null;

  @Column({ name: 'created_by_id', type: 'text', nullable: true })
  createdById: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  @Index()
  updatedAt: Date;

  @DeleteDateColumn({ name: 'deleted_at' })
  deletedAt: Date | null;
}
