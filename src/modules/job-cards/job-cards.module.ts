import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobCard } from './entities/job-card.entity';
import { JobCardsController } from './job-cards.controller';
import { JobCardsService } from './job-cards.service';

@Module({
  imports: [TypeOrmModule.forFeature([JobCard])],
  controllers: [JobCardsController],
  providers: [JobCardsService],
  exports: [JobCardsService],
})
export class JobCardsModule {}
