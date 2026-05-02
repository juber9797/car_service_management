import { IsISO8601, IsOptional, IsString } from 'class-validator';

export class PullSyncDto {
  /**
   * The server timestamp from the previous successful pull.
   * Omit on first sync to get all records.
   */
  @IsOptional()
  @IsISO8601()
  since?: string;

  /** Entity types to pull. Omit for all. */
  @IsOptional()
  @IsString()
  entityTypes?: string;
}
