import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { APP_GUARD, APP_INTERCEPTOR, APP_FILTER } from '@nestjs/core';

import appConfig from './config/app.config';
import databaseConfig from './config/database.config';

import { AuthModule } from './modules/auth/auth.module';
import { JobCardsModule } from './modules/job-cards/job-cards.module';
import { TasksModule } from './modules/tasks/tasks.module';
import { DashboardModule } from './modules/dashboard/dashboard.module';
import { InvoicesModule } from './modules/invoices/invoices.module';
import { SyncModule } from './modules/sync/sync.module';

import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { GlobalExceptionFilter } from './common/filters/http-exception.filter';

@Module({
  imports: [
    // --- Config ---
    ConfigModule.forRoot({
      isGlobal: true,
      load: [appConfig, databaseConfig],
      envFilePath: ['.env', '.env.local'],
    }),

    // --- Database ---
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        config.get('database') as object,
    }),

    // --- Feature Modules ---
    AuthModule,
    JobCardsModule,
    TasksModule,
    DashboardModule,
    InvoicesModule,
    SyncModule,
  ],
  providers: [
    // Apply JWT guard globally — mark public routes with @Public()
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_FILTER, useClass: GlobalExceptionFilter },
  ],
})
export class AppModule {}
