PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

INSERT INTO projects(
  ref, name, slug, root_path, intent_revision, intent_sha256,
  purpose_primary, purpose_secondary_json, mode, autonomy, created_at, updated_at
) VALUES(
  'PRJ-APF-0001', 'APF', 'apf', 'C:/fixture/apf', 1,
  'a3ff64c1df88e9f2163a87c5843011eb620e28c1b9933eab670dcb9285918c3c',
  'personal', '["open_source","experiment"]', 'experiment', 'CONTROLLED',
  '2026-08-28T21:00:00Z', '2026-08-28T21:00:00Z'
);

INSERT INTO actors(project_id, ref, kind, name, capabilities_json, created_at)
VALUES
  (1, 'ACT-CORE-0001', 'SYSTEM', 'APF Core', '{"control_plane":true}', '2026-08-28T21:00:00Z'),
  (1, 'ACT-CODEX-0001', 'AGENT_INSTANCE', 'Codex executor', '{"structured_output":true}', '2026-08-28T21:00:00Z'),
  (1, 'ACT-HUMAN-0001', 'HUMAN', 'Local project owner', '{}', '2026-08-28T21:00:00Z');

INSERT INTO policy_snapshots(
  project_id, ref, autonomy, content_json, sha256, ratified_by_actor_id, created_at
) VALUES(
  1, 'POL-0001', 'CONTROLLED',
  '{"autonomy":"CONTROLLED","production":"DENY","financial_spending":"DENY","external_communication":"DENY"}',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  3, '2026-08-28T21:01:00Z'
);

INSERT INTO tasks(
  project_id, ref, title, objective, state, priority, acceptance_json, created_at, updated_at
) VALUES(
  1, 'TASK-0001', 'Validate Project Brain schema',
  'Prove schema, FTS, append-only audit and backup behavior.', 'READY', 90,
  '["schema applies","FTS returns decision","audit rejects mutation","backup restores"]',
  '2026-08-28T21:05:00Z', '2026-08-28T21:05:00Z'
);

INSERT INTO work_orders(
  project_id, task_id, ref, schema_version, idempotency_key,
  policy_snapshot_id, context_hash, message_json, created_at
) VALUES(
  1, 1, 'WO-0001', 1,
  'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'POL-0001',
  'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '{"schema_version":1,"message_id":"WO-0001","message_type":"WORK_ORDER","project_id":"PRJ-APF-0001","task_id":"TASK-0001","created_at":"2026-08-28T21:06:00Z","idempotency_key":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","actor":{"role":"central_orchestrator","agent_instance":"core-local","authority":"CORE"},"policy_snapshot_id":"POL-0001","budget":{"duration_seconds":60,"enforcement":"HARD"},"context":{"pack_hash":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","refs":[]},"payload":{"objective":"Validate the Project Brain schema without changing product code.","acceptance":["Schema applies to an empty SQLite database"],"allowed_paths":[],"protected_paths":[".git/**",".apf/**",".tools/**"],"grants":[],"provider_profile":"local_validation","max_attempts":1}}',
  '2026-08-28T21:06:00Z'
);

INSERT INTO runs(
  project_id, task_id, work_order_id, actor_id, ref, provider, provider_version,
  model, effort, status, started_at, ended_at, exit_code, result_message_json, usage_json,
  enforcement_json
) VALUES(
  1, 1, 1, 2, 'RUN-0001', 'local_validation', '1', NULL, NULL, 'SUCCEEDED',
  '2026-08-28T21:07:00Z', '2026-08-28T21:07:01Z', 0,
  '{"schema_version":1,"message_id":"RES-0001","message_type":"RESULT","project_id":"PRJ-APF-0001","task_id":"TASK-0001","run_id":"RUN-0001","created_at":"2026-08-28T21:07:01Z","actor":{"role":"validator","agent_instance":"core-local","authority":"CORE"},"policy_snapshot_id":"POL-0001","context":{"pack_hash":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","refs":[]},"payload":{"outcome":"SUCCEEDED","summary":"The deterministic foundation validation completed.","changes":[],"checks":[{"name":"foundation-validation","status":"PASSED","evidence_ref":"EVD-0001","summary":"Schema, FTS, audit and backup checks passed."}],"artifacts":[],"risks":[],"assumptions":[],"blockers":[],"usage":{"input_tokens":0,"output_tokens":0,"cost":0,"currency":"USD","duration_ms":1000,"state":"ACTUAL","cost_basis":"NONE","source":"local deterministic validation","confidence":"HIGH"},"next_action":"Continue to the provider capability gate."}}',
  '{"input_tokens":0,"output_tokens":0,"cost":0,"currency":"USD","duration_ms":1000,"state":"ACTUAL","cost_basis":"NONE","source":"local deterministic validation","confidence":"HIGH"}',
  '{"filesystem":"APF_VERIFIED","network":"UNKNOWN"}'
);

INSERT INTO knowledge_items(
  project_id, ref, kind, title, body, status, confidence, reversibility,
  data_json, created_at, updated_at
) VALUES
  (1, 'DEC-0001', 'DECISION', 'Deterministic control plane',
   'State transitions, leases, budgets, grants and audit belong to code, not a model.',
   'ACCEPTED', 'HIGH', 'EXPENSIVE',
   '{"dissent":[],"revisit_when":"control plane requirements materially change"}',
   '2026-08-28T21:08:00Z', '2026-08-28T21:08:00Z'),
  (1, 'EVD-0001', 'EVIDENCE', 'Foundation validation',
   'SQLite schema, FTS, append-only audit and backup restore passed locally.',
   'CURRENT', 'HIGH', NULL,
   '{"reproducible":true}',
   '2026-08-28T21:09:00Z', '2026-08-28T21:09:00Z'),
  (1, 'ASM-0001', 'ASSUMPTION', 'SQLite supports V1',
   'One logical writer and local WAL are sufficient for the initial workload.',
   'OPEN', 'MEDIUM', NULL,
   '{"impact_if_wrong":"HIGH","validation":"scale spike"}',
   '2026-08-28T21:10:00Z', '2026-08-28T21:10:00Z'),
  (1, 'RISK-0001', 'RISK', 'False security claim',
   'A provider subprocess may retain user authority despite APF policy.',
   'OPEN', 'HIGH', NULL,
   '{"probability":"HIGH","impact":"CRITICAL"}',
   '2026-08-28T21:11:00Z', '2026-08-28T21:11:00Z');

INSERT INTO relations(project_id, source_ref, relation, target_ref, created_at)
VALUES
  (1, 'EVD-0001', 'SUPPORTS', 'DEC-0001', '2026-08-28T21:12:00Z'),
  (1, 'RISK-0001', 'THREATENS', 'DEC-0001', '2026-08-28T21:12:00Z');

INSERT INTO cost_entries(
  project_id, task_id, run_id, ref, category, state, cost_basis, amount, currency,
  duration_ms, provider, source, confidence, observed_at, data_json
) VALUES(
  1, 1, 1, 'COST-0001', 'TOOL', 'ACTUAL', 'NONE', 0.0, 'USD', 1000,
  'sqlite', 'local deterministic validation', 'HIGH', '2026-08-28T21:13:00Z', '{}'
);

INSERT INTO attention_items(
  project_id, ref, class, status, title, body, subject_ref, created_at
) VALUES(
  1, 'ATTN-0001', 'ACTION_REQUIRED', 'OPEN', 'License decision',
  'Ratify MIT or authorize Apache-2.0 before external contributions.',
  'DEC-LICENSE', '2026-08-28T21:14:00Z'
);

INSERT INTO audit_events(
  project_id, event_id, occurred_at, actor_ref, event_type, subject_ref, run_id, data_json
) VALUES
  (1, 'EVT-0001', '2026-08-28T21:05:00Z', 'ACT-CORE-0001', 'task.created', 'TASK-0001', NULL, '{}'),
  (1, 'EVT-0002', '2026-08-28T21:07:01Z', 'ACT-CORE-0001', 'run.completed', 'RUN-0001', 1, '{"outcome":"SUCCEEDED"}'),
  (1, 'EVT-0003', '2026-08-28T21:08:00Z', 'ACT-CORE-0001', 'decision.accepted', 'DEC-0001', NULL, '{}');

INSERT INTO brain_fts(entity_type, entity_ref, title, body)
SELECT kind, ref, title, body FROM knowledge_items;

COMMIT;
