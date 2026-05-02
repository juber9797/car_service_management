import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

@Entity('tombstones')
@Index(['entityType', 'entityId'], { unique: true })
export class Tombstone {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'garage_id' })
  @Index()
  garageId: string;

  @Column({ name: 'entity_type', length: 50 })
  entityType: string;

  @Column({ name: 'entity_id' })
  entityId: string;

  @Column({ name: 'deleted_at', type: 'datetime' })
  deletedAt: Date;
}
