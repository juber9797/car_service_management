import { NestFactory, Reflector } from '@nestjs/core';
import { ValidationPipe, VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, {
    logger: ['log', 'warn', 'error', 'debug'],
  });

  const config = app.get(ConfigService);
  const port = config.get<number>('app.port')!;
  const prefix = config.get<string>('app.apiPrefix')!;

  // Global route prefix
  app.setGlobalPrefix(prefix);

  // Strict validation — strip unknown fields, whitelist only
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  // CORS — lock down in production
  app.enableCors({
    origin: config.get('app.nodeEnv') === 'production'
      ? [/\.yourcompany\.com$/]
      : '*',
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'x-garage-id', 'x-client-id'],
  });

  // Swagger / OpenAPI
  if (config.get('app.nodeEnv') !== 'production') {
    const swagger = new DocumentBuilder()
      .setTitle('Car Workshop API')
      .setDescription('Production-grade Car Service Workshop Management System')
      .setVersion('1.0')
      .addBearerAuth()
      .addApiKey({ type: 'apiKey', in: 'header', name: 'x-garage-id' }, 'garage-id')
      .build();

    const document = SwaggerModule.createDocument(app, swagger);
    SwaggerModule.setup('docs', app, document);
  }

  // Graceful shutdown
  app.enableShutdownHooks();

  await app.listen(port);
  console.log(`🚗 Car Workshop API running on http://localhost:${port}/${prefix}`);
  if (config.get('app.nodeEnv') !== 'production') {
    console.log(`📖 Swagger UI at http://localhost:${port}/docs`);
  }
}

bootstrap().catch((err) => {
  console.error('Fatal startup error', err);
  process.exit(1);
});
