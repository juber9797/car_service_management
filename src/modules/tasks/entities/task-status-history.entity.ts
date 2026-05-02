import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
} from 'typeorm';
import { TaskStatus } from '../../../common/enums';

@Entity('task_status_history')
export class TaskStatusHistory {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'task_id' })
  taskId: string;

  @Column({ name: 'garage_id' })
  garageId: string;

  @Column({ name: 'from_status', type: 'enum', enum: TaskStatus, nullable: true })
  fromStatus: TaskStatus | null;

  @Column({ name: 'to_status', type: 'enum', enum: TaskStatus })
  toStatus: TaskStatus;

  @Column({ name: 'changed_by_id', nullable: true })
  changedById: string | null;

  @Column({ type: 'text', nullable: true })
  notes: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
