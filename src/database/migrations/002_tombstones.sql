-- Tombstones table — records every soft-delete so offline clients
-- know to purge their local copy on next pull.
CREATE TABLE tombstones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id   UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL,
    entity_id   UUID NOT NULL,
    deleted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT tombstones_entity_unique UNIQUE (entity_type, entity_id)
);

CREATE INDEX idx_tombstones_garage_time ON tombstones(garage_id, deleted_at);

-- Auto-write tombstone when a job_card or task is soft-deleted
CREATE OR REPLACE FUNCTION write_tombstone()
RETURNS TRIGGER AS $$
BEGIN
    -- soft-delete is when deleted_at transitions from NULL to a timestamp
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        INSERT INTO tombstones(garage_id, entity_type, entity_id)
        VALUES (NEW.garage_id, TG_TABLE_NAME, NEW.id)
        ON CONFLICT (entity_type, entity_id) DO UPDATE SET deleted_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_job_cards_tombstone
    AFTER UPDATE ON job_cards FOR EACH ROW EXECUTE FUNCTION write_tombstone();

CREATE TRIGGER trg_tasks_tombstone
    AFTER UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION write_tombstone();
