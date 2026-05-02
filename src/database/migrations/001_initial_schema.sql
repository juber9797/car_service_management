-- ============================================================
-- Car Service Workshop Management System - Initial Schema
-- PostgreSQL 15+
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_role AS ENUM ('admin', 'technician', 'receptionist');
CREATE TYPE job_card_status AS ENUM ('pending', 'in_progress', 'on_hold', 'completed', 'cancelled');
CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled');
CREATE TYPE invoice_status AS ENUM ('draft', 'issued', 'paid', 'overdue', 'void');
CREATE TYPE sync_operation AS ENUM ('create', 'update', 'delete');

-- ============================================================
-- GARAGES (Multi-tenant root)
-- ============================================================

CREATE TABLE garages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(255) NOT NULL,
    address     TEXT,
    phone       VARCHAR(20),
    email       VARCHAR(255),
    tax_number  VARCHAR(50),
    settings    JSONB NOT NULL DEFAULT '{}',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USERS
-- ============================================================

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    full_name       VARCHAR(255) NOT NULL,
    phone           VARCHAR(20),
    role            user_role NOT NULL DEFAULT 'technician',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,

    CONSTRAINT users_email_garage_unique UNIQUE (email, garage_id)
);

CREATE INDEX idx_users_garage_id ON users(garage_id);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role) WHERE deleted_at IS NULL;

-- ============================================================
-- CUSTOMERS
-- ============================================================

CREATE TABLE customers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id   UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    full_name   VARCHAR(255) NOT NULL,
    phone       VARCHAR(20) NOT NULL,
    email       VARCHAR(255),
    address     TEXT,
    notes       TEXT,
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ,

    CONSTRAINT customers_phone_garage_unique UNIQUE (phone, garage_id)
);

CREATE INDEX idx_customers_garage_id ON customers(garage_id);
CREATE INDEX idx_customers_phone ON customers(phone);
CREATE INDEX idx_customers_search ON customers USING gin(
    to_tsvector('english', full_name || ' ' || COALESCE(email, '') || ' ' || phone)
);

-- ============================================================
-- VEHICLES
-- ============================================================

CREATE TABLE vehicles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    make            VARCHAR(100) NOT NULL,
    model           VARCHAR(100) NOT NULL,
    year            SMALLINT NOT NULL CHECK (year >= 1900 AND year <= 2100),
    license_plate   VARCHAR(20) NOT NULL,
    vin             VARCHAR(17),
    color           VARCHAR(50),
    engine_type     VARCHAR(50),
    mileage         INTEGER,
    notes           TEXT,
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,

    CONSTRAINT vehicles_plate_garage_unique UNIQUE (license_plate, garage_id)
);

CREATE INDEX idx_vehicles_garage_id ON vehicles(garage_id);
CREATE INDEX idx_vehicles_customer_id ON vehicles(customer_id);
CREATE INDEX idx_vehicles_license_plate ON vehicles(license_plate);

-- ============================================================
-- JOB CARDS
-- ============================================================

CREATE TABLE job_cards (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id           UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    job_number          VARCHAR(20) NOT NULL,           -- e.g. JC-2024-0001
    vehicle_id          UUID NOT NULL REFERENCES vehicles(id) ON DELETE RESTRICT,
    customer_id         UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    assigned_to_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    status              job_card_status NOT NULL DEFAULT 'pending',
    description         TEXT NOT NULL,
    estimated_hours     DECIMAL(6,2),
    actual_hours        DECIMAL(6,2),
    mileage_in          INTEGER,
    mileage_out         INTEGER,
    promised_at         TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    notes               TEXT,
    internal_notes      TEXT,
    version             INTEGER NOT NULL DEFAULT 1,
    client_id           VARCHAR(100),                  -- last device that modified this
    created_by_id       UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT job_cards_number_garage_unique UNIQUE (job_number, garage_id)
);

CREATE INDEX idx_job_cards_garage_id ON job_cards(garage_id);
CREATE INDEX idx_job_cards_vehicle_id ON job_cards(vehicle_id);
CREATE INDEX idx_job_cards_customer_id ON job_cards(customer_id);
CREATE INDEX idx_job_cards_status ON job_cards(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_job_cards_assigned_to ON job_cards(assigned_to_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_job_cards_updated_at ON job_cards(updated_at);  -- for sync pulls

-- Auto-increment job number per garage
CREATE SEQUENCE IF NOT EXISTS job_card_seq START 1;

CREATE OR REPLACE FUNCTION generate_job_number(p_garage_id UUID)
RETURNS VARCHAR AS $$
DECLARE
    next_seq BIGINT;
BEGIN
    SELECT COALESCE(MAX(CAST(SPLIT_PART(job_number, '-', 3) AS INTEGER)), 0) + 1
    INTO next_seq
    FROM job_cards
    WHERE garage_id = p_garage_id;

    RETURN 'JC-' || TO_CHAR(NOW(), 'YYYY') || '-' || LPAD(next_seq::TEXT, 5, '0');
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TASKS
-- ============================================================

CREATE TABLE tasks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    job_card_id     UUID NOT NULL REFERENCES job_cards(id) ON DELETE CASCADE,
    assigned_to_id  UUID REFERENCES users(id) ON DELETE SET NULL,
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    status          task_status NOT NULL DEFAULT 'pending',
    estimated_hours DECIMAL(6,2),
    actual_hours    DECIMAL(6,2),
    labor_rate      DECIMAL(10,2),                     -- rate per hour at time of task
    sort_order      INTEGER NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    version         INTEGER NOT NULL DEFAULT 1,
    client_id       VARCHAR(100),
    created_by_id   UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_tasks_garage_id ON tasks(garage_id);
CREATE INDEX idx_tasks_job_card_id ON tasks(job_card_id);
CREATE INDEX idx_tasks_assigned_to ON tasks(assigned_to_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_status ON tasks(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_tasks_updated_at ON tasks(updated_at);

-- ============================================================
-- TASK STATUS HISTORY (immutable audit log)
-- ============================================================

CREATE TABLE task_status_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id         UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    garage_id       UUID NOT NULL REFERENCES garages(id),
    from_status     task_status,
    to_status       task_status NOT NULL,
    changed_by_id   UUID REFERENCES users(id),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_task_history_task_id ON task_status_history(task_id);

-- ============================================================
-- SPARE PARTS (catalog per garage)
-- ============================================================

CREATE TABLE spare_parts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    part_number     VARCHAR(100),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    unit_price      DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    stock_qty       INTEGER NOT NULL DEFAULT 0,
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_spare_parts_garage_id ON spare_parts(garage_id);

-- ============================================================
-- INVOICES
-- ============================================================

CREATE TABLE invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    invoice_number  VARCHAR(20) NOT NULL,
    job_card_id     UUID NOT NULL REFERENCES job_cards(id) ON DELETE RESTRICT,
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    status          invoice_status NOT NULL DEFAULT 'draft',
    subtotal        DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_pct    DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (discount_pct >= 0 AND discount_pct <= 100),
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_pct         DECIMAL(5,2) NOT NULL DEFAULT 0 CHECK (tax_pct >= 0),
    tax_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    total           DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes           TEXT,
    issued_at       TIMESTAMPTZ,
    due_at          TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ,
    version         INTEGER NOT NULL DEFAULT 1,
    created_by_id   UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,

    CONSTRAINT invoices_number_garage_unique UNIQUE (invoice_number, garage_id)
);

CREATE INDEX idx_invoices_garage_id ON invoices(garage_id);
CREATE INDEX idx_invoices_job_card_id ON invoices(job_card_id);
CREATE INDEX idx_invoices_customer_id ON invoices(customer_id);
CREATE INDEX idx_invoices_status ON invoices(status) WHERE deleted_at IS NULL;

-- ============================================================
-- INVOICE LINE ITEMS
-- ============================================================

CREATE TABLE invoice_line_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    garage_id       UUID NOT NULL REFERENCES garages(id),
    task_id         UUID REFERENCES tasks(id) ON DELETE SET NULL,
    spare_part_id   UUID REFERENCES spare_parts(id) ON DELETE SET NULL,
    item_type       VARCHAR(20) NOT NULL CHECK (item_type IN ('labor', 'part', 'misc')),
    description     VARCHAR(500) NOT NULL,
    quantity        DECIMAL(10,3) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price      DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    total_price     DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_line_items_invoice_id ON invoice_line_items(invoice_id);

-- ============================================================
-- SYNC LOG (outbox for change tracking)
-- ============================================================

CREATE TABLE sync_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id       UUID NOT NULL REFERENCES garages(id) ON DELETE CASCADE,
    entity_type     VARCHAR(50) NOT NULL,       -- 'job_card', 'task', etc.
    entity_id       UUID NOT NULL,
    operation       sync_operation NOT NULL,
    payload         JSONB NOT NULL,
    version         INTEGER NOT NULL,
    client_id       VARCHAR(100),               -- originating device
    user_id         UUID REFERENCES users(id),
    server_time     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sync_log_garage_time ON sync_log(garage_id, server_time);
CREATE INDEX idx_sync_log_entity ON sync_log(entity_type, entity_id);
CREATE INDEX idx_sync_log_client ON sync_log(client_id);

-- ============================================================
-- REFRESH TOKENS
-- ============================================================

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL UNIQUE,
    client_id   VARCHAR(100),
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

-- ============================================================
-- TRIGGERS: auto-update updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['garages','users','customers','vehicles','job_cards','tasks','spare_parts','invoices']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at
             BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION update_updated_at()',
            t, t
        );
    END LOOP;
END;
$$;

-- ============================================================
-- TRIGGERS: auto-write to sync_log after mutations
-- ============================================================

CREATE OR REPLACE FUNCTION write_sync_log()
RETURNS TRIGGER AS $$
DECLARE
    v_operation sync_operation;
    v_payload   JSONB;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_operation := 'create';
        v_payload   := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_operation := CASE WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
                            THEN 'delete' ELSE 'update' END;
        v_payload   := to_jsonb(NEW);
    ELSE
        v_operation := 'delete';
        v_payload   := to_jsonb(OLD);
    END IF;

    INSERT INTO sync_log(garage_id, entity_type, entity_id, operation, payload, version, client_id)
    VALUES (
        NEW.garage_id,
        TG_TABLE_NAME,
        NEW.id,
        v_operation,
        v_payload,
        NEW.version,
        NEW.client_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['job_cards','tasks']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_sync_log
             AFTER INSERT OR UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION write_sync_log()',
            t, t
        );
    END LOOP;
END;
$$;

-- ============================================================
-- SEED: Default garage for dev
-- ============================================================

INSERT INTO garages(id, name, address, phone, email)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Demo Garage',
    '123 Main Street',
    '+1-555-0100',
    'demo@garage.com'
);
