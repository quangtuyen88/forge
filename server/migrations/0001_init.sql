-- Forge worker schema v1 (D1). Apply: npx wrangler d1 migrations apply forge
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT,
  apple_sub TEXT UNIQUE,
  google_sub TEXT UNIQUE,
  tier TEXT NOT NULL DEFAULT 'free',
  referral_code TEXT UNIQUE NOT NULL,
  referred_by TEXT,
  promo_code TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE auth_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen TEXT NOT NULL
);

CREATE TABLE email_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE records (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  id TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL,
  UNIQUE(user_id, type, id)
);

CREATE TABLE subscription_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  event TEXT NOT NULL,
  product_id TEXT,
  price REAL,
  currency TEXT,
  promo_code TEXT,
  occurred_at TEXT NOT NULL,
  raw TEXT
);

CREATE TABLE referrals (
  referee_id TEXT PRIMARY KEY,
  referrer_id TEXT NOT NULL,
  redeemed_at TEXT NOT NULL,
  rewarded_at TEXT
);

CREATE TABLE coach_usage (
  user_id TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(user_id, day)
);

-- social (wave 5)
CREATE TABLE profiles (
  user_id TEXT PRIMARY KEY,
  handle TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
);

CREATE TABLE follows (
  follower_id TEXT NOT NULL,
  followee_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(follower_id, followee_id)
);

CREATE TABLE posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE kudos (
  post_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(post_id, user_id)
);

CREATE TABLE comments (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_records_user_seq ON records(user_id, seq);
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at);
CREATE INDEX idx_follows_followee ON follows(followee_id);
