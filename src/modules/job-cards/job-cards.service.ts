import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { JobCard } from './entities/job-card.entity';
import { CreateJobCardDto } from './dto/create-job-card.dto';
import { UpdateJobCardDto } from './dto/update-job-card.dto';
import { JobCardStatus } from '../../common/enums';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

// Valid status transitions — prevents illegal state changes
const ALLOWED_TRANSITIONS: Record<JobCardStatus, JobCardStatus[]> = {
  [JobCardStatus.PENDING]:      [JobCardStatus.IN_PROGRESS, JobCardStatus.CANCELLED],
  [JobCardStatus.IN_PROGRESS]:  [JobCardStatus.ON_HOLD, JobCardStatus.COMPLETED, JobCardStatus.CANCELLED],
  [JobCardStatus.ON_HOLD]:      [JobCardStatus.IN_PROGRESS, JobCardStatus.CANCELLED],
  [JobCardStatus.COMPLETED]:    [],
  [JobCardStatus.CANCELLED]:    [],
};

@Injectable()
export class JobCardsService {
  constructor(
    @InjectRepository(JobCard)
    private readonly repo: Repository<JobCard>,
    private readonly dataSource: DataSource,
  ) {}

  async create(dto: CreateJobCardDto, user: JwtPayload): Promise<JobCard> {
    // Generate job number atomically via a DB-side function
    const [{ generate_job_number: jobNumber }] = await this.dataSource.query(
      'SELECT generate_job_number($1)',
      [user.garageId],
    ) as [{ generate_job_number: string }];

    const jobCard = this.repo.create({
      garageId: user.garageId,
      jobNumber,
      vehicleId: dto.vehicleId,
      customerId: dto.customerId,
      assignedToId: dto.assignedToId ?? null,
      description: dto.description,
      estimatedHours: dto.estimatedHours ?? null,
      mileageIn: dto.mileageIn ?? null,
      promisedAt: dto.promisedAt ? new Date(dto.promisedAt) : null,
      notes: dto.notes ?? null,
      clientId: dto.clientId ?? null,
      createdById: user.sub,
    });

    return this.repo.save(jobCard);
  }

  async findAll(
    garageId: string,
    filters: { status?: JobCardStatus; assignedToId?: string; page?: number; limit?: number },
  ): Promise<{ data: JobCard[]; total: number; page: number; limit: number }> {
    const page = filters.page ?? 1;
    const limit = Math.min(filters.limit ?? 20, 100);

    const qb = this.repo
      .createQueryBuilder('jc')
      .where('jc.garage_id = :garageId', { garageId })
      .andWhere('jc.deleted_at IS NULL')
      .orderBy('jc.created_at', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (filters.status) qb.andWhere('jc.status = :status', { status: filters.status });
    if (filters.assignedToId) qb.andWhere('jc.assigned_to_id = :assignedToId', { assignedToId: filters.assignedToId });

    const [data, total] = await qb.getManyAndCount();
    return { data, total, page, limit };
  }

  async findOne(id: string, garageId: string): Promise<JobCard> {
    const jobCard = await this.repo.findOne({
      where: { id, garageId },
    });
    if (!jobCard) throw new NotFoundException(`Job card ${id} not found`);
    return jobCard;
  }

  async update(id: string, dto: UpdateJobCardDto, user: JwtPayload): Promise<JobCard> {
    // Load with a row-level lock to prevent concurrent updates
    return this.dataSource.transaction(async (manager) => {
      const jobCard = await manager
        .createQueryBuilder(JobCard, 'jc')
        .where('jc.id = :id', { id })
        .andWhere('jc.garage_id = :garageId', { garageId: user.garageId })
        .setLock('pessimistic_write')
        .getOne();

      if (!jobCard) throw new NotFoundException(`Job card ${id} not found`);

      // Optimistic lock check — reject stale writes
      if (dto.version !== jobCard.version) {
        throw new ConflictException(
          `Version conflict: client has v${dto.version}, server is at v${jobCard.version}. Fetch latest and retry.`,
        );
      }

      // Validate status transition
      if (dto.status && dto.status !== jobCard.status) {
        const allowed = ALLOWED_TRANSITIONS[jobCard.status];
        if (!allowed.includes(dto.status)) {
          throw new BadRequestException(
            `Cannot transition from '${jobCard.status}' to '${dto.status}'`,
          );
        }

        if (dto.status === JobCardStatus.IN_PROGRESS && !jobCard.startedAt) {
          jobCard.startedAt = new Date();
        }
        if (dto.status === JobCardStatus.COMPLETED) {
          jobCard.completedAt = new Date();
        }
        jobCard.status = dto.status;
      }

      // Apply other field updates
      const updatable: (keyof UpdateJobCardDto)[] = [
        'assignedToId', 'description', 'estimatedHours',
        'actualHours', 'mileageOut', 'notes', 'internalNotes', 'clientId',
      ];
      for (const field of updatable) {
        if (dto[field] !== undefined) {
          (jobCard as Record<string, unknown>)[field] = dto[field];
        }
      }

      jobCard.version += 1;
      return manager.save(jobCard);
    });
  }

  async softDelete(id: string, garageId: string): Promise<void> {
    const jobCard = await this.findOne(id, garageId);
    if (jobCard.status === JobCardStatus.IN_PROGRESS) {
      throw new BadRequestException('Cannot delete a job card that is in progress');
    }
    await this.repo.softDelete(id);
  }
}
