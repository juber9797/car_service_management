import {
  IsArray, IsEnum, IsISO8601, IsNumber, IsObject, IsOptional,
  IsString, IsUUID, ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { SyncOperation } from '../../../common/enums';

export class SyncChangeDto {
  /** The client-generated UUID for this change. Used for idempotency. */
  @IsUUID()
  changeId: string;

  /** Table / domain name: 'job_card' | 'task' */
  @IsString()
  entityType: string;

  /** UUID of the entity being mutated */
  @IsUUID()
  entityId: string;

  @IsEnum(SyncOperation)
  operation: SyncOperation;

  /**
   * Full local state of the entity (for create/update).
   * Undefined for delete operations.
   */
  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown>;

  /**
   * The version the client believes the server currently holds.
   * For creates, this should be 0.
   */
  @IsNumber()
  baseVersion: number;

  /** ISO-8601 timestamp of when this change was made locally */
  @IsISO8601()
  localTimestamp: string;
}

export class PushSyncDto {
  /** Stable device/client identifier — used for conflict attribution */
  @IsString()
  clientId: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SyncChangeDto)
  changes: SyncChangeDto[];
}
