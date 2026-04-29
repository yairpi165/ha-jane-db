-- Jane Memory Schema v1.4
-- Run against the 'jane' database after add-on starts

-- S1.6: pgvector for semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- Memory entries: replaces the 7 MD files
CREATE TABLE IF NOT EXISTS memory_entries (
    id SERIAL PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    user_name VARCHAR(100),
    content TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- v1.1: Fix unique constraint — NULL != NULL caused duplicates
-- Clean any existing duplicates (keep highest id = latest content)
DELETE FROM memory_entries a USING memory_entries b
WHERE a.id < b.id
  AND a.category = b.category
  AND a.user_name IS NOT DISTINCT FROM b.user_name;

ALTER TABLE memory_entries DROP CONSTRAINT IF EXISTS memory_entries_category_user_name_key;
DROP INDEX IF EXISTS uq_memory_category_user;
CREATE UNIQUE INDEX uq_memory_category_user
    ON memory_entries (category, user_name) NULLS NOT DISTINCT;

-- Events: replaces actions.md + history.log (append-only audit trail)
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    event_type VARCHAR(50) NOT NULL,
    user_name VARCHAR(100),
    description TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_user ON events(user_name);

-- S1.3: Semantic Memory — Household Graph
CREATE TABLE IF NOT EXISTS persons (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    role VARCHAR(50),
    birth_date DATE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS relationships (
    id SERIAL PRIMARY KEY,
    person_a_id INT REFERENCES persons(id) ON DELETE CASCADE,
    person_b_id INT REFERENCES persons(id) ON DELETE CASCADE,
    relation VARCHAR(50) NOT NULL,
    UNIQUE(person_a_id, person_b_id, relation)
);

-- S1.3: Preference Memory
CREATE TABLE IF NOT EXISTS preferences (
    id SERIAL PRIMARY KEY,
    person_name VARCHAR(100) NOT NULL,
    key VARCHAR(200) NOT NULL,
    value TEXT NOT NULL,
    confidence REAL DEFAULT 1.0,
    inferred BOOLEAN DEFAULT FALSE,
    source VARCHAR(50) DEFAULT 'extraction',
    last_reinforced TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(person_name, key)
);

CREATE INDEX IF NOT EXISTS idx_preferences_person ON preferences(person_name);
CREATE INDEX IF NOT EXISTS idx_preferences_confidence ON preferences(confidence) WHERE confidence > 0.3;

-- S1.4: Episodic Memory

CREATE TABLE IF NOT EXISTS event_entities (
    id SERIAL PRIMARY KEY,
    event_id INT REFERENCES events(id) ON DELETE CASCADE,
    entity_id VARCHAR(200) NOT NULL,
    friendly_name VARCHAR(200)
);
CREATE INDEX IF NOT EXISTS idx_event_entities_event ON event_entities(event_id);
CREATE INDEX IF NOT EXISTS idx_event_entities_entity ON event_entities(entity_id);

CREATE TABLE IF NOT EXISTS episodes (
    id SERIAL PRIMARY KEY,
    title VARCHAR(300) NOT NULL,
    summary TEXT NOT NULL,
    start_ts TIMESTAMPTZ NOT NULL,
    end_ts TIMESTAMPTZ NOT NULL,
    episode_type VARCHAR(50) NOT NULL DEFAULT 'activity',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_episodes_start ON episodes(start_ts DESC);
CREATE INDEX IF NOT EXISTS idx_episodes_type ON episodes(episode_type);

CREATE TABLE IF NOT EXISTS daily_summaries (
    id SERIAL PRIMARY KEY,
    summary_date DATE NOT NULL UNIQUE,
    summary TEXT NOT NULL,
    event_count INT DEFAULT 0,
    episode_count INT DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_daily_summaries_date ON daily_summaries(summary_date DESC);

-- S1.5: Routine Memory
CREATE TABLE IF NOT EXISTS routines (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL UNIQUE,
    trigger_phrase VARCHAR(300) NOT NULL,
    steps JSONB NOT NULL DEFAULT '[]',
    script_id VARCHAR(200),
    confidence REAL DEFAULT 1.0,
    occurrence_count INT DEFAULT 1,
    last_used TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- S3.1 (JANE-42, D12): scope discriminator for personal vs shared routines.
-- JANE-71 prepared the read-side tier classification; this column is the
-- write-side anchor. Existing rows backfill to 'shared' (Phase 1 default
-- behavior). VARCHAR + CHECK rather than a true ENUM type for evolvability,
-- mirroring the policies.key pattern.
ALTER TABLE routines ADD COLUMN IF NOT EXISTS scope VARCHAR(20) DEFAULT 'shared'
    CHECK (scope IN ('personal', 'shared'));

-- S1.5: Policy Memory
CREATE TABLE IF NOT EXISTS policies (
    id SERIAL PRIMARY KEY,
    person_name VARCHAR(100) NOT NULL,
    key VARCHAR(100) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(person_name, key)
);

-- Anti-repetition tracking (replaces in-memory list)
CREATE TABLE IF NOT EXISTS response_tracking (
    id SERIAL PRIMARY KEY,
    opening TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed rows removed in v1.1 — auto-migration populates from MD files

-- S1.6: Embedding columns for semantic search (text-embedding-004 = 768 dims)
ALTER TABLE episodes ADD COLUMN IF NOT EXISTS embedding vector(768);
ALTER TABLE daily_summaries ADD COLUMN IF NOT EXISTS embedding vector(768);

-- IVFFlat indexes for cosine similarity (lists tuned for ~3000 rows)
-- Note: IVFFlat requires SET ivfflat.probes = 3 at query time for good recall
CREATE INDEX IF NOT EXISTS idx_episodes_embedding ON episodes
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 10);
CREATE INDEX IF NOT EXISTS idx_daily_embedding ON daily_summaries
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 5);

-- S3.1 (JANE-42): Household Modes — transition audit log.
-- Every mode change writes one row: voice / automation / time / presence.
-- `from_mode` is nullable for the first row written after install.
-- `reason` carries the trigger phrase (voice), automation name (automation),
-- or time-rule string (time) — feeds Phase 4 Decision Log with rich context.
CREATE TABLE IF NOT EXISTS household_mode_transitions (
    id SERIAL PRIMARY KEY,
    from_mode VARCHAR(50),
    to_mode VARCHAR(50) NOT NULL,
    trigger VARCHAR(50),
    triggered_by VARCHAR(100),
    reason TEXT,
    ts TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_household_mode_transitions_ts
    ON household_mode_transitions(ts DESC);

-- S3.1 (JANE-42, D11): user_overrides — schema-only here, populated by S3.2.
-- Defining the table now so KPI baselines (false_positive_alert_rate,
-- manual_override_rate) start measuring from S3.1 deploy instead of losing
-- weeks of override data between the S3.1 and S3.2 deployments.
CREATE TABLE IF NOT EXISTS user_overrides (
    id SERIAL PRIMARY KEY,
    action_type VARCHAR(100) NOT NULL,
    user_name VARCHAR(100),
    override_type VARCHAR(50) CHECK (override_type IN ('dismissed', 'reversed', 'corrected')),
    ts TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_overrides_ts ON user_overrides(ts DESC);

-- S3.2 (JANE-45, D5): correlate dismissals with the proactive_decision row
-- they overrode, instead of relying on a 5-minute time-window heuristic.
-- ON DELETE SET NULL so override rows survive event archival.
ALTER TABLE user_overrides ADD COLUMN IF NOT EXISTS proactive_decision_id
    INT REFERENCES events(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_user_overrides_proactive_decision
    ON user_overrides(proactive_decision_id) WHERE proactive_decision_id IS NOT NULL;
