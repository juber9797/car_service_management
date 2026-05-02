import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { Task } from './entities/task.entity';
import { TaskStatusHistory } from './entities/task-status-history.entity';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskStatusDto } from './dto/update-task-status.dto';
import { TaskStatus } from '../../common/enums';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

const ALLOWED_TASK_TRANSITIONS: Record<TaskStatus, TaskStatus[]> = {
  [TaskStatus.PENDING]:     [TaskStatus.IN_PROGRESS, TaskStatus.CANCELLED],
  [TaskStatus.IN_PROGRESS]: [TaskStatus.COMPLETED, TaskStatus.CANCELLED],
  [TaskStatus.COMPLETED]:   [],
  [TaskStatus.CANCELLED]:   [],
};

@Injectable()
export class TasksService {
  constructor(
    @InjectRepository(Task)
    private readonly taskRepo: Repository<Task>,
    @InjectRepository(TaskStatusHistory)
    private readonly historyRepo: Repository<TaskStatusHistory>,
    private readonly dataSource: DataSource,
  ) {}

  async create(dto: CreateTaskDto, user: JwtPayload): Promise<Task> {
    const task = this.taskRepo.create({
      garageId: user.garageId,
      jobCardId: dto.jobCardId,
      assignedToId: dto.assignedToId ?? null,
      title: dto.title,
      description: dto.description ?? null,
      estimatedHours: dto.estimatedHours ?? null,
      laborRate: dto.laborRate ?? null,
      sortOrder: dto.sortOrder ?? 0,
      clientId: dto.clientId ?? null,
      createdById: user.sub,
    });

    const saved = await this.taskRepo.save(task);

    await this.historyRepo.save(
      this.historyRepo.create({
        taskId: saved.id,
        garageId: user.garageId,
        fromStatus: null,
        toStatus: TaskStatus.PENDING,
        changedById: user.sub,
      }),
    );

    return saved;
  }

  async findByJobCard(jobCardId: string, garageId: string): Promise<Task[]> {
    return this.taskRepo.find({
      where: { jobCardId, garageId },
      order: { sortOrder: 'ASC', createdAt: 'ASC' },
    });
  }

  async findOne(id: string, garageId: string): Promise<Task> {
    const task = await this.taskRepo.findOne({ where: { id, garageId } });
    if (!task) throw new NotFoundException(`Task ${id} not found`);
    return task;
  }

  async updateStatus(
    id: string,
    dto: UpdateTaskStatusDto,
    user: JwtPayload,
  ): Promise<Task> {
    return this.dataSource.transaction(async (manager) => {
      // SQLite serialises writes within a transaction — no explicit row lock needed
      const task = await manager.findOne(Task, {
        where: { id, garageId: user.garageId },
      });

      if (!task) throw new NotFoundException(`Task ${id} not found`);

      if (dto.version !== task.version) {
        throw new ConflictException(
          `Version conflict on task ${id}: client v${dto.version} vs server v${task.version}`,
        );
      }

      if (dto.status !== task.status) {
        const allowed = ALLOWED_TASK_TRANSITIONS[task.status];
        if (!allowed.includes(dto.status)) {
          throw new BadRequestException(
            `Cannot transition task from '${task.status}' to '${dto.status}'`,
          );
        }

        const previousStatus = task.status;
        task.status = dto.status;

        if (dto.status === TaskStatus.IN_PROGRESS && !task.startedAt) {
          task.startedAt = new Date();
        }
        if (dto.status === TaskStatus.COMPLETED) {
          task.completedAt = new Date();
          if (dto.actualHours !== undefined) task.actualHours = dto.actualHours;
        }

        await manager.save(
          manager.create(TaskStatusHistory, {
            taskId: task.id,
            garageId: user.garageId,
            fromStatus: previousStatus,
            toStatus: dto.status,
            changedById: user.sub,
            notes: dto.notes ?? null,
          }),
        );
      }

      if (dto.assignedToId !== undefined) task.assignedToId = dto.assignedToId;
      if (dto.clientId !== undefined) task.clientId = dto.clientId;
      task.version += 1;

      return manager.save(task);
    });
  }

  async getStatusHistory(taskId: string, garageId: string): Promise<TaskStatusHistory[]> {
    await this.findOne(taskId, garageId);
    return this.historyRepo.find({
      where: { taskId },
      order: { createdAt: 'ASC' },
    });
  }

  async assign(id: string, assignedToId: string, user: JwtPayload): Promise<Task> {
    const task = await this.findOne(id, user.garageId);
    task.assignedToId = assignedToId;
    task.version += 1;
    return this.taskRepo.save(task);
  }
}
