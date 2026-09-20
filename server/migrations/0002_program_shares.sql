-- Unlisted program shares (D1). Apply: npx wrangler d1 migrations apply forge
--
-- The payload column is write-once: it holds the allowlisted public program only.
-- Never store workout history, loads, health, goals, coach memory, conversations,
-- private notes or raw imported source here. Only `status`, `revoked_at` and the
-- abuse-report columns change after insert.
CREATE TABLE program_shares (
  id TEXT PRIMARY KEY,
  token_hash TEXT UNIQUE NOT NULL,
  token_prefix TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  report_count INTEGER NOT NULL DEFAULT 0,
  last_reported_at TEXT,
  last_report_reason TEXT
);

CREATE INDEX idx_program_shares_token ON program_shares(token_hash);
CREATE INDEX idx_program_shares_owner ON program_shares(owner_id, created_at);
