import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { JobCard } from '../job-cards/entities/job-card.entity';
import { Task } from '../tasks/entities/task.entity';
import { JobCardStatus, TaskStatus } from '../../common/enums';

export interface JobCardSummary {
  id: string;
  jobNumber: string;
  status: JobCardStatus;
  customerName?: string;
  vehicleInfo?: string;
  totalTasks: number;
  completedTasks: number;
  progressPercent: number;
  assignedToId: string | null;
  promisedAt: Date | null;
  startedAt: Date | null;
  createdAt: Date;
}

export interface DashboardStats {
  totalActive: number;
  byStatus: Record<JobCardStatus, number>;
  overdueJobs: number;
  avgCompletionTimeHours: number | null;
}

export interface DashboardResponse {
  stats: DashboardStats;
  activeJobCards: JobCardSummary[];
  generatedAt: string;
}

@Injectable()
export class DashboardService {
  constructor(
    @InjectRepository(JobCard)
    private readonly jobCardRepo: Repository<JobCard>,
    private readonly dataSource: DataSource,
  ) {}

  async getDashboard(garageId: string, technicianId?: string): Promise<DashboardResponse> {
    const [activeJobCards, stats] = await Promise.all([
      this.getActiveJobCards(garageId, technicianId),
      this.getStats(garageId),
    ]);

    return {
      stats,
      activeJobCards,
      generatedAt: new Date().toISOString(),
    };
  }

  private async getActiveJobCards(
    garageId: string,
    technicianId?: string,
  ): Promise<JobCardSummary[]> {
    // Single query: job cards + per-card task counts + customer/vehicle info
    const rows = await this.dataSource.query<Array<Record<string, unknown>>>(
      `
      SELECT
        jc.id,
        jc.job_number         AS "jobNumber",
        jc.status,
        jc.assigned_to_id     AS "assignedToId",
        jc.promised_at        AS "promisedAt",
        jc.started_at         AS "startedAt",
        jc.created_at         AS "createdAt",
        c.full_name           AS "customerName",
        v.make || ' ' || v.model || ' (' || v.license_plate || ')' AS "vehicleInfo",
        COUNT(t.id)           AS "totalTasks",
        COUNT(t.id) FILTER (WHERE t.status = 'completed') AS "completedTasks"
      FROM job_cards jc
      LEFT JOIN customers c  ON c.id = jc.customer_id
      LEFT JOIN vehicles  v  ON v.id = jc.vehicle_id
      LEFT JOIN tasks     t  ON t.job_card_id = jc.id AND t.deleted_at IS NULL
      WHERE jc.garage_id   = $1
        AND jc.deleted_at IS NULL
        AND jc.status NOT IN ('completed', 'cancelled')
        ${technicianId ? 'AND jc.assigned_to_id = $3' : ''}
      GROUP BY jc.id, c.full_name, v.make, v.model, v.license_plate
      ORDER BY jc.created_at DESC
      LIMIT 200
      `,
      technicianId ? [garageId, undefined, technicianId] : [garageId],
    );

    return rows.map((row) => {
      const total = Number(row['totalTasks']) || 0;
      const completed = Number(row['completedTasks']) || 0;
      return {
        id: row['id'] as string,
        jobNumber: row['jobNumber'] as string,
        status: row['status'] as JobCardStatus,
        customerName: row['customerName'] as string | undefined,
        vehicleInfo: row['vehicleInfo'] as string | undefined,
        totalTasks: total,
        completedTasks: completed,
        progressPercent: total === 0 ? 0 : Math.round((completed / total) * 100),
        assignedToId: row['assignedToId'] as string | null,
        promisedAt: row['promisedAt'] ? new Date(row['promisedAt'] as string) : null,
        startedAt: row['startedAt'] ? new Date(row['startedAt'] as string) : null,
        createdAt: new Date(row['createdAt'] as string),
      };
    });
  }

  private async getStats(garageId: string): Promise<DashboardStats> {
    const rows = await this.dataSource.query<Array<{ status: string; count: string }>>(
      `
      SELECT status, COUNT(*) AS count
      FROM job_cards
      WHERE garage_id = $1 AND deleted_at IS NULL
      GROUP BY status
      `,
      [garageId],
    );

    const byStatus = Object.values(JobCardStatus).reduce(
      (acc, s) => ({ ...acc, [s]: 0 }),
      {} as Record<JobCardStatus, number>,
    );
    let totalActive = 0;

    for (const row of rows) {
      const s = row.status as JobCardStatus;
      byStatus[s] = parseInt(row.count, 10);
      if (![JobCardStatus.COMPLETED, JobCardStatus.CANCELLED].includes(s)) {
        totalActive += byStatus[s];
      }
    }

    const [overdueRow] = await this.dataSource.query<[{ count: string }]>(
      `
      SELECT COUNT(*) AS count FROM job_cards
      WHERE garage_id = $1
        AND deleted_at IS NULL
        AND status NOT IN ('completed', 'cancelled')
        AND promised_at < NOW()
      `,
      [garageId],
    );

    const [avgRow] = await this.dataSource.query<[{ avg_hours: string | null }]>(
      `
      SELECT AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) / 3600) AS avg_hours
      FROM job_cards
      WHERE garage_id = $1
        AND status = 'completed'
        AND started_at IS NOT NULL
        AND completed_at IS NOT NULL
        AND completed_at > NOW() - INTERVAL '30 days'
      `,
      [garageId],
    );

    return {
      totalActive,
      byStatus,
      overdueJobs: parseInt(overdueRow.count, 10),
      avgCompletionTimeHours: avgRow.avg_hours
        ? Math.round(parseFloat(avgRow.avg_hours) * 10) / 10
        : null,
    };
  }
}
