import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobCard } from '../job-cards/entities/job-card.entity';
import { Task } from '../tasks/entities/task.entity';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';
import { TombstoneService } from './tombstone.service';

@Module({
  imports: [TypeOrmModule.forFeature([JobCard, Task])],
  controllers: [SyncController],
  providers: [SyncService, TombstoneService],
})
export class SyncModule {}
