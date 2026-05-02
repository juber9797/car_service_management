import {
  IsArray, IsEnum, IsNumber, IsOptional, IsString, IsUUID,
  Max, Min, ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { LineItemType } from '../../../common/enums';

export class LineItemDto {
  @IsEnum(LineItemType)
  itemType: LineItemType;

  @IsString()
  description: string;

  @IsNumber()
  @Min(0.001)
  quantity: number;

  @IsNumber()
  @Min(0)
  unitPrice: number;

  @IsOptional()
  @IsUUID()
  taskId?: string;

  @IsOptional()
  @IsUUID()
  sparePartId?: string;

  @IsOptional()
  @IsNumber()
  sortOrder?: number;
}

export class GenerateInvoiceDto {
  @IsUUID()
  jobCardId: string;

  @IsUUID()
  customerId: string;

  /**
   * If true, line items from all completed tasks on the job card
   * are auto-populated before any additional items below.
   */
  @IsOptional()
  autoPopulateFromTasks?: boolean;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => LineItemDto)
  additionalItems?: LineItemDto[];

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  discountPct?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  taxPct?: number;

  @IsOptional()
  @IsString()
  notes?: string;
}
