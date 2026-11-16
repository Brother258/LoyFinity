CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('customer', 'business_owner', 'business_staff', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE business_status AS ENUM ('pending_review', 'approved', 'suspended');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE qr_purpose AS ENUM ('checkin', 'redeem');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(254) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role user_role NOT NULL,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS users_email_lower_idx ON users (LOWER(email));

CREATE TABLE IF NOT EXISTS verification_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL UNIQUE,
  purpose VARCHAR(24) NOT NULL CHECK (purpose IN ('verify_email', 'reset_password')),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS verification_tokens_user_idx ON verification_tokens(user_id, purpose);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS refresh_tokens_user_idx ON refresh_tokens(user_id);

CREATE TABLE IF NOT EXISTS businesses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(140) NOT NULL,
  category VARCHAR(60) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  phone VARCHAR(32) NOT NULL DEFAULT '',
  website TEXT NOT NULL DEFAULT '',
  status business_status NOT NULL DEFAULT 'pending_review',
  subscription_plan VARCHAR(24) NOT NULL DEFAULT 'starter',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS business_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_role VARCHAR(24) NOT NULL CHECK (member_role IN ('owner', 'manager', 'staff')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (business_id, user_id)
);
CREATE INDEX IF NOT EXISTS business_members_user_idx ON business_members(user_id);

CREATE TABLE IF NOT EXISTS staff_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  email VARCHAR(254) NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  member_role VARCHAR(24) NOT NULL CHECK (member_role IN ('manager', 'staff')),
  expires_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  address VARCHAR(255) NOT NULL,
  location GEOGRAPHY(POINT, 4326) NOT NULL,
  phone VARCHAR(32) NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS branches_location_gix ON branches USING GIST(location);
CREATE INDEX IF NOT EXISTS branches_business_idx ON branches(business_id);

CREATE TABLE IF NOT EXISTS loyalty_programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  title VARCHAR(120) NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  program_type VARCHAR(16) NOT NULL DEFAULT 'visits' CHECK (program_type IN ('visits', 'points')),
  reward_visits INTEGER NOT NULL CHECK (reward_visits BETWEEN 1 AND 100),
  reward_description VARCHAR(180) NOT NULL,
  reward_value_cents INTEGER NOT NULL DEFAULT 0 CHECK (reward_value_cents >= 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS loyalty_programs_business_idx ON loyalty_programs(business_id, is_active);

CREATE TABLE IF NOT EXISTS customer_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES loyalty_programs(id) ON DELETE CASCADE,
  visits_count INTEGER NOT NULL DEFAULT 0 CHECK (visits_count >= 0),
  lifetime_visits INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_visits >= 0),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_visit_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (customer_id, program_id)
);
CREATE INDEX IF NOT EXISTS customer_progress_customer_idx ON customer_progress(customer_id);
CREATE INDEX IF NOT EXISTS customer_progress_program_idx ON customer_progress(program_id);

CREATE TABLE IF NOT EXISTS qr_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash CHAR(64) NOT NULL UNIQUE,
  purpose qr_purpose NOT NULL,
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES users(id) ON DELETE CASCADE,
  program_id UUID REFERENCES loyalty_programs(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((purpose = 'checkin' AND branch_id IS NOT NULL) OR (purpose = 'redeem' AND customer_id IS NOT NULL AND program_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS qr_tokens_expiry_idx ON qr_tokens(expires_at) WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES loyalty_programs(id) ON DELETE CASCADE,
  checked_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activity_day DATE NOT NULL DEFAULT CURRENT_DATE
);
CREATE UNIQUE INDEX IF NOT EXISTS checkins_one_per_branch_per_day
  ON checkins(customer_id, branch_id, activity_day);
CREATE INDEX IF NOT EXISTS checkins_business_time_idx ON checkins(business_id, checked_in_at DESC);
CREATE INDEX IF NOT EXISTS checkins_customer_time_idx ON checkins(customer_id, checked_in_at DESC);

CREATE TABLE IF NOT EXISTS redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES loyalty_programs(id) ON DELETE CASCADE,
  reward_description VARCHAR(180) NOT NULL,
  reward_value_cents INTEGER NOT NULL DEFAULT 0,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS redemptions_business_time_idx ON redemptions(business_id, redeemed_at DESC);

CREATE TABLE IF NOT EXISTS favorites (
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(customer_id, business_id)
);

CREATE TABLE IF NOT EXISTS campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  title VARCHAR(120) NOT NULL,
  message VARCHAR(500) NOT NULL,
  segment VARCHAR(24) NOT NULL DEFAULT 'inactive_30d' CHECK (segment IN ('all', 'inactive_30d', 'active', 'reward_ready')),
  status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'sent')),
  scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS campaigns_business_idx ON campaigns(business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(140) NOT NULL,
  body VARCHAR(500) NOT NULL,
  kind VARCHAR(24) NOT NULL DEFAULT 'general',
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS notifications_user_time_idx ON notifications(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(80) NOT NULL,
  target_type VARCHAR(40) NOT NULL,
  target_id UUID,
  ip_hash CHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS audit_logs_actor_time_idx ON audit_logs(actor_id, created_at DESC);


-- Hashed per-route, per-IP, per-identity fixed-window counters for auth abuse controls.
CREATE TABLE IF NOT EXISTS auth_rate_limits (
  bucket_key CHAR(64) NOT NULL,
  window_id BIGINT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  PRIMARY KEY (bucket_key, window_id)
);
CREATE INDEX IF NOT EXISTS auth_rate_limits_window_idx ON auth_rate_limits(window_id);
