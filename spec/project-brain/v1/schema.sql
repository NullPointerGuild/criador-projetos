PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
PRAGMA application_id = 1095783985;
PRAGMA user_version = 2;

BEGIN IMMEDIATE;

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL CHECK(
    length(checksum_sha256) = 64 AND checksum_sha256 NOT GLOB '*[^0-9a-f]*'
  ),
  applied_at TEXT NOT NULL
) STRICT;

CREATE TABLE projects (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'PRJ-*'),
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  root_path TEXT NOT NULL,
  intent_revision INTEGER NOT NULL CHECK(intent_revision > 0),
  intent_sha256 TEXT NOT NULL CHECK(
    length(intent_sha256) = 64 AND intent_sha256 NOT GLOB '*[^0-9a-f]*'
  ),
  purpose_primary TEXT NOT NULL,
  purpose_secondary_json TEXT NOT NULL DEFAULT '[]' CHECK(
    json_valid(purpose_secondary_json) AND json_type(purpose_secondary_json) = 'array'
  ),
  mode TEXT NOT NULL,
  autonomy TEXT NOT NULL CHECK(autonomy IN ('CONTROLLED', 'SHARED')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE actors (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'ACT-*'),
  kind TEXT NOT NULL CHECK(kind IN ('HUMAN', 'ROLE', 'AGENT_INSTANCE', 'PROVIDER', 'SYSTEM')),
  name TEXT NOT NULL,
  parent_actor_id INTEGER REFERENCES actors(id),
  provider TEXT,
  model TEXT,
  capabilities_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(capabilities_json) AND json_type(capabilities_json) = 'object'
  ),
  active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
  created_at TEXT NOT NULL
) STRICT;

CREATE TABLE policy_snapshots (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL CHECK(project_id = 1) REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'POL-*'),
  autonomy TEXT NOT NULL CHECK(autonomy IN ('CONTROLLED', 'SHARED')),
  content_json TEXT NOT NULL CHECK(json_valid(content_json) AND json_type(content_json) = 'object'),
  sha256 TEXT NOT NULL CHECK(length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'),
  ratified_by_actor_id INTEGER NOT NULL REFERENCES actors(id),
  created_at TEXT NOT NULL
) STRICT;

CREATE TRIGGER policy_snapshots_no_update
BEFORE UPDATE ON policy_snapshots
BEGIN
  SELECT RAISE(ABORT, 'policy_snapshots is immutable');
END;

CREATE TRIGGER policy_snapshots_no_delete
BEFORE DELETE ON policy_snapshots
BEGIN
  SELECT RAISE(ABORT, 'policy_snapshots is immutable');
END;

CREATE TABLE tasks (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'TASK-*'),
  parent_task_id INTEGER REFERENCES tasks(id),
  title TEXT NOT NULL,
  objective TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN (
    'PROPOSED', 'READY', 'LEASED', 'EXECUTING', 'INPUT_REQUIRED', 'BLOCKED',
    'REVIEW', 'CHANGES_REQUESTED', 'COMPLETED', 'FAILED', 'CANCELLED', 'INTERRUPTED'
  )),
  priority INTEGER NOT NULL DEFAULT 50 CHECK(priority BETWEEN 0 AND 100),
  lease_owner_actor_id INTEGER REFERENCES actors(id),
  lease_expires_at TEXT,
  acceptance_json TEXT NOT NULL DEFAULT '[]' CHECK(
    json_valid(acceptance_json) AND json_type(acceptance_json) = 'array'
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(
    (state IN ('LEASED', 'EXECUTING') AND lease_owner_actor_id IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR (state NOT IN ('LEASED', 'EXECUTING') AND lease_owner_actor_id IS NULL AND lease_expires_at IS NULL)
  )
) STRICT;

CREATE TABLE task_dependencies (
  task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  depends_on_task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE RESTRICT,
  created_at TEXT NOT NULL,
  PRIMARY KEY(task_id, depends_on_task_id),
  CHECK(task_id <> depends_on_task_id)
) STRICT, WITHOUT ROWID;

CREATE TABLE work_orders (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'WO-*'),
  schema_version INTEGER NOT NULL CHECK(schema_version = 1),
  idempotency_key TEXT CHECK(
    idempotency_key IS NULL OR (
      length(idempotency_key) = 71
      AND substr(idempotency_key, 1, 7) = 'sha256:'
      AND substr(idempotency_key, 8) NOT GLOB '*[^0-9a-f]*'
    )
  ),
  policy_snapshot_id TEXT NOT NULL CHECK(policy_snapshot_id GLOB 'POL-*') REFERENCES policy_snapshots(ref),
  context_hash TEXT NOT NULL CHECK(
    length(context_hash) = 71
    AND substr(context_hash, 1, 7) = 'sha256:'
    AND substr(context_hash, 8) NOT GLOB '*[^0-9a-f]*'
  ),
  message_json TEXT NOT NULL CHECK(json_valid(message_json) AND json_type(message_json) = 'object'),
  created_at TEXT NOT NULL,
  UNIQUE(project_id, idempotency_key)
) STRICT;

CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  work_order_id INTEGER REFERENCES work_orders(id),
  actor_id INTEGER REFERENCES actors(id),
  parent_run_id INTEGER REFERENCES runs(id),
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'RUN-*'),
  provider TEXT NOT NULL,
  provider_version TEXT,
  model TEXT,
  effort TEXT,
  status TEXT NOT NULL CHECK(status IN (
    'CREATED', 'STARTING', 'RUNNING', 'INPUT_REQUIRED', 'BLOCKED', 'REVIEW',
    'SUCCEEDED', 'FAILED', 'CANCELLED', 'INTERRUPTED'
  )),
  workspace_path TEXT,
  branch TEXT,
  base_commit TEXT,
  head_commit TEXT,
  context_hash TEXT CHECK(
    context_hash IS NULL OR (
      length(context_hash) = 71
      AND substr(context_hash, 1, 7) = 'sha256:'
      AND substr(context_hash, 8) NOT GLOB '*[^0-9a-f]*'
    )
  ),
  process_id INTEGER,
  process_started_at TEXT,
  process_image_sha256 TEXT CHECK(
    process_image_sha256 IS NULL OR (
      length(process_image_sha256) = 64 AND process_image_sha256 NOT GLOB '*[^0-9a-f]*'
    )
  ),
  host_boot_id TEXT,
  supervisor_token TEXT,
  exit_code INTEGER,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  result_message_json TEXT CHECK(
    result_message_json IS NULL OR (
      json_valid(result_message_json) AND json_type(result_message_json) = 'object'
    )
  ),
  usage_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(usage_json) AND json_type(usage_json) = 'object'
  ),
  enforcement_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(enforcement_json) AND json_type(enforcement_json) = 'object'
  ),
  CHECK(
    (process_id IS NULL AND process_started_at IS NULL AND process_image_sha256 IS NULL AND host_boot_id IS NULL AND supervisor_token IS NULL)
    OR
    (process_id IS NOT NULL AND process_started_at IS NOT NULL AND process_image_sha256 IS NOT NULL AND host_boot_id IS NOT NULL AND supervisor_token IS NOT NULL)
  ),
  CHECK(status <> 'RUNNING' OR process_id IS NOT NULL)
) STRICT;

CREATE TRIGGER runs_enforcement_insert
BEFORE INSERT ON runs
WHEN EXISTS (
  SELECT 1 FROM json_each(NEW.enforcement_json)
  WHERE type <> 'text' OR value NOT IN ('OS_ENFORCED', 'PROVIDER_ENFORCED', 'APF_VERIFIED', 'ADVISORY', 'UNKNOWN')
)
BEGIN
  SELECT RAISE(ABORT, 'invalid observed enforcement level');
END;

CREATE TRIGGER runs_enforcement_update
BEFORE UPDATE OF enforcement_json ON runs
WHEN EXISTS (
  SELECT 1 FROM json_each(NEW.enforcement_json)
  WHERE type <> 'text' OR value NOT IN ('OS_ENFORCED', 'PROVIDER_ENFORCED', 'APF_VERIFIED', 'ADVISORY', 'UNKNOWN')
)
BEGIN
  SELECT RAISE(ABORT, 'invalid observed enforcement level');
END;

CREATE TABLE knowledge_items (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK(kind IN (
    'GOAL', 'REQUIREMENT', 'DECISION', 'CLAIM', 'EVIDENCE',
    'ASSUMPTION', 'RISK', 'RESEARCH', 'NOTE'
  )),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL,
  confidence TEXT CHECK(confidence IS NULL OR confidence IN ('HIGH', 'MEDIUM', 'LOW', 'UNKNOWN')),
  reversibility TEXT CHECK(reversibility IS NULL OR reversibility IN ('EASY', 'MODERATE', 'EXPENSIVE', 'NEARLY_IRREVERSIBLE')),
  source_type TEXT,
  source_uri TEXT,
  publisher TEXT,
  retrieved_at TEXT,
  data_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(data_json) AND json_type(data_json) = 'object'
  ),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE relations (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  source_ref TEXT NOT NULL,
  relation TEXT NOT NULL CHECK(relation IN (
    'SUPPORTS', 'CONTRADICTS', 'DEPENDS_ON', 'IMPLEMENTS', 'SUPERSEDES',
    'PRODUCED_BY', 'THREATENS', 'VALIDATES', 'OWNED_BY', 'REVIEWS', 'DERIVED_FROM'
  )),
  target_ref TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(project_id, source_ref, relation, target_ref),
  CHECK(source_ref <> target_ref)
) STRICT;

CREATE TABLE approvals (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id INTEGER REFERENCES tasks(id),
  run_id INTEGER REFERENCES runs(id),
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'APR-*'),
  decision TEXT NOT NULL CHECK(decision IN ('PENDING', 'APPROVED', 'DENIED', 'EXPIRED', 'REVOKED')),
  request_json TEXT NOT NULL CHECK(json_valid(request_json) AND json_type(request_json) = 'object'),
  decided_by_actor_id INTEGER REFERENCES actors(id),
  reason TEXT,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  decided_at TEXT
) STRICT;

CREATE TABLE artifacts (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'ART-*'),
  sha256 TEXT NOT NULL CHECK(length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'),
  storage_path TEXT NOT NULL,
  media_type TEXT,
  size_bytes INTEGER NOT NULL CHECK(size_bytes >= 0),
  produced_by_run_id INTEGER REFERENCES runs(id),
  created_at TEXT NOT NULL,
  UNIQUE(project_id, sha256)
) STRICT;

CREATE TABLE cost_entries (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id INTEGER REFERENCES tasks(id),
  run_id INTEGER REFERENCES runs(id),
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'COST-*'),
  category TEXT NOT NULL CHECK(category IN ('AI', 'INFRASTRUCTURE', 'TOOL', 'STORAGE', 'NETWORK', 'OTHER')),
  state TEXT NOT NULL CHECK(state IN ('ESTIMATED', 'COMMITTED', 'ACTUAL')),
  cost_basis TEXT NOT NULL CHECK(cost_basis IN ('METERED', 'LIST', 'CONTRACTED', 'SUBSCRIPTION_INCLUDED', 'NONE', 'UNKNOWN')),
  amount REAL,
  currency TEXT CHECK(currency IS NULL OR currency GLOB '[A-Z][A-Z][A-Z]'),
  input_tokens INTEGER CHECK(input_tokens IS NULL OR input_tokens >= 0),
  output_tokens INTEGER CHECK(output_tokens IS NULL OR output_tokens >= 0),
  duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
  provider TEXT,
  model TEXT,
  source TEXT NOT NULL,
  confidence TEXT NOT NULL CHECK(confidence IN ('HIGH', 'MEDIUM', 'LOW', 'UNKNOWN')),
  observed_at TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(data_json) AND json_type(data_json) = 'object'
  ),
  CHECK(state <> 'ACTUAL' OR cost_basis IN ('METERED', 'NONE')),
  CHECK(cost_basis <> 'UNKNOWN' OR amount IS NULL)
) STRICT;

CREATE TABLE attention_items (
  id INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  ref TEXT NOT NULL UNIQUE CHECK(ref GLOB 'ATTN-*'),
  class TEXT NOT NULL CHECK(class IN ('ACTION_REQUIRED', 'AWARENESS', 'ON_DEMAND', 'OPERATIONAL', 'ARCHIVE')),
  status TEXT NOT NULL CHECK(status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED', 'DISMISSED')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  subject_ref TEXT,
  created_at TEXT NOT NULL,
  resolved_at TEXT
) STRICT;

CREATE TABLE audit_events (
  sequence INTEGER PRIMARY KEY,
  project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL UNIQUE CHECK(event_id GLOB 'EVT-*'),
  occurred_at TEXT NOT NULL,
  actor_ref TEXT NOT NULL,
  event_type TEXT NOT NULL,
  subject_ref TEXT,
  run_id INTEGER REFERENCES runs(id),
  data_json TEXT NOT NULL DEFAULT '{}' CHECK(
    json_valid(data_json) AND json_type(data_json) = 'object'
  )
) STRICT;

CREATE TRIGGER audit_events_no_update
BEFORE UPDATE ON audit_events
BEGIN
  SELECT RAISE(ABORT, 'audit_events is append-only');
END;

CREATE TRIGGER audit_events_no_delete
BEFORE DELETE ON audit_events
BEGIN
  SELECT RAISE(ABORT, 'audit_events is append-only');
END;

CREATE TRIGGER audit_events_no_replace
BEFORE INSERT ON audit_events
WHEN EXISTS (
  SELECT 1 FROM audit_events
  WHERE sequence = NEW.sequence OR event_id = NEW.event_id
)
BEGIN
  SELECT RAISE(ABORT, 'audit_events is append-only');
END;

CREATE TRIGGER audit_events_no_backdate
BEFORE INSERT ON audit_events
WHEN NEW.occurred_at < COALESCE((SELECT MAX(occurred_at) FROM audit_events), NEW.occurred_at)
BEGIN
  SELECT RAISE(ABORT, 'audit_events rejects backdated insertion');
END;

CREATE INDEX idx_actors_project_kind ON actors(project_id, kind, active);
CREATE INDEX idx_policy_project_time ON policy_snapshots(project_id, created_at DESC);
CREATE INDEX idx_tasks_project_state ON tasks(project_id, state, priority DESC);
CREATE INDEX idx_tasks_lease ON tasks(project_id, lease_expires_at) WHERE lease_expires_at IS NOT NULL;
CREATE INDEX idx_runs_task_started ON runs(task_id, started_at DESC);
CREATE INDEX idx_runs_status ON runs(project_id, status, started_at DESC);
CREATE INDEX idx_knowledge_kind_status ON knowledge_items(project_id, kind, status);
CREATE INDEX idx_relations_source ON relations(project_id, source_ref, relation);
CREATE INDEX idx_relations_target ON relations(project_id, target_ref, relation);
CREATE INDEX idx_approvals_pending ON approvals(project_id, decision, expires_at);
CREATE INDEX idx_cost_project_time ON cost_entries(project_id, observed_at DESC);
CREATE INDEX idx_attention_open ON attention_items(project_id, status, class);
CREATE INDEX idx_audit_project_time ON audit_events(project_id, occurred_at, sequence);
CREATE INDEX idx_audit_subject ON audit_events(project_id, subject_ref, sequence);

CREATE VIRTUAL TABLE brain_fts USING fts5(
  entity_type UNINDEXED,
  entity_ref UNINDEXED,
  title,
  body,
  tokenize = 'unicode61 remove_diacritics 2'
);

COMMIT;
