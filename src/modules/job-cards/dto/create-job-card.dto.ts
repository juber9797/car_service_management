import {
  IsString, IsUUID, IsOptional, IsNumber, IsDateString, Min, MaxLength,
} from 'class-validator';

export class CreateJobCardDto {
  @IsUUID()
  vehicleId: string;

  @IsUUID()
  customerId: string;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsString()
  @MaxLength(1000)
  description: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  estimatedHours?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  mileageIn?: number;

  @IsOptional()
  @IsDateString()
  promisedAt?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsString()
  clientId?: string;
}
