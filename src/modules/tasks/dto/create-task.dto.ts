import {
  IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min,
} from 'class-validator';

export class CreateTaskDto {
  @IsUUID()
  jobCardId: string;

  @IsString()
  @MaxLength(255)
  title: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  estimatedHours?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  laborRate?: number;

  @IsOptional()
  @IsNumber()
  sortOrder?: number;

  @IsOptional()
  @IsString()
  clientId?: string;
}
