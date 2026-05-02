import { registerAs } from '@nestjs/config';
import { TypeOrmModuleOptions } from '@nestjs/typeorm';

export default registerAs('database', (): TypeOrmModuleOptions => ({
  type: 'sqlite',
  database: process.env.DB_PATH ?? './car_workshop.sqlite',
  entities: [__dirname + '/../**/*.entity{.ts,.js}'],
  // synchronize creates all tables from entities automatically — no manual migrations needed
  synchronize: true,
  logging: process.env.NODE_ENV === 'development',
}));
