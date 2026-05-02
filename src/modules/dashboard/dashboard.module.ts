import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobCard } from '../job-cards/entities/job-card.entity';
import { DashboardController } from './dashboard.controller';
import { DashboardService } from './dashboard.service';

@Module({
  imports: [TypeOrmModule.forFeature([JobCard])],
  controllers: [DashboardController],
  providers: [DashboardService],
})
export class DashboardModule {}
