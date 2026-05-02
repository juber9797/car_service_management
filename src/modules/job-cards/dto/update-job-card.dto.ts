import {
  IsEnum, IsNumber, IsOptional, IsString, IsUUID, Min,
} from 'class-validator';
import { JobCardStatus } from '../../../common/enums';

export class UpdateJobCardDto {
  @IsOptional()
  @IsEnum(JobCardStatus)
  status?: JobCardStatus;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  estimatedHours?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  actualHours?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  mileageOut?: number;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsString()
  internalNotes?: string;

  @IsOptional()
  @IsString()
  clientId?: string;

  /** Optimistic locking — client must send the version it last saw */
  @IsNumber()
  version: number;
}
