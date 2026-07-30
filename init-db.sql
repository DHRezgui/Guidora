-- Extension pour UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Extension pour les vecteurs (pgvector pour RAG)
--CREATE EXTENSION IF NOT EXISTS vector;

-- =====================================================
-- TYPES ENUM (version sécurisée - idempotente)
-- =====================================================

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN CREATE TYPE user_role AS ENUM ('SUPER_ADMIN', 'ADMIN', 'DEVELOPER', 'USER'); END IF; END $$;
DO $$ BEGIN
  ALTER TYPE user_role ADD VALUE 'SUPER_ADMIN';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'plan_type') THEN CREATE TYPE plan_type AS ENUM ('FREE', 'STARTER', 'PRO', 'ENTERPRISE'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'position_type') THEN CREATE TYPE position_type AS ENUM ('TOP', 'BOTTOM', 'LEFT', 'RIGHT', 'CENTER', 'TOP_LEFT', 'TOP_RIGHT', 'BOTTOM_LEFT', 'BOTTOM_RIGHT'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'action_type') THEN CREATE TYPE action_type AS ENUM ('CLICK', 'HOVER', 'SCROLL', 'NEXT', 'SKIP', 'COMPLETE'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'step_type') THEN CREATE TYPE step_type AS ENUM ('tooltip', 'highlight', 'modal', 'form', 'tutorial', 'checklist'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tour_user_state_status') THEN CREATE TYPE tour_user_state_status AS ENUM ('DISMISSED', 'COMPLETED', 'ELIGIBLE'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tour_replay_policy') THEN CREATE TYPE tour_replay_policy AS ENUM ('never', 'after_period', 'always_on_new_version'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tour_environment') THEN CREATE TYPE tour_environment AS ENUM ('sandbox', 'production'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tour_sandbox_status') THEN CREATE TYPE tour_sandbox_status AS ENUM ('pending', 'approved', 'rejected', 'returned'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'tour_sandbox_status' AND e.enumlabel = 'returned') THEN ALTER TYPE tour_sandbox_status ADD VALUE 'returned'; END IF; END $$;
DO $$ BEGIN
  CREATE TYPE tour_access_mode AS ENUM ('view', 'collaborate');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'tour_user_state_status' AND e.enumlabel = 'ELIGIBLE') THEN ALTER TYPE tour_user_state_status ADD VALUE 'ELIGIBLE'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_type') THEN CREATE TYPE event_type AS ENUM ('PAGE_VIEW', 'CLICK', 'SCROLL', 'HOVER', 'EXIT', 'FORM_SUBMIT', 'ERROR'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'progress_status') THEN CREATE TYPE progress_status AS ENUM ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'ABANDONED'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ticket_status') THEN CREATE TYPE ticket_status AS ENUM ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN CREATE TYPE priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'metric_type') THEN CREATE TYPE metric_type AS ENUM ('TOUR_COMPLETION', 'ABANDONMENT_RATE', 'HELP_TRIGGER', 'FAQ_SEARCH', 'SUPPORT_TICKET', 'TUTORIAL_VIEW'); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sidebar_position') THEN CREATE TYPE sidebar_position AS ENUM ('LEFT', 'RIGHT'); END IF; END $$;


-- =====================================================
-- TABLE: organizations
-- Entreprises utilisant le module d'onboarding
-- =====================================================
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    api_key VARCHAR(255) UNIQUE NOT NULL,
    plan plan_type NOT NULL DEFAULT 'FREE',
    domain VARCHAR(255),
    settings JSONB DEFAULT '{}',
    max_tours INTEGER DEFAULT 5,
    max_users INTEGER DEFAULT 100,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organizations' AND indexname = 'idx_organizations_api_key') THEN CREATE INDEX idx_organizations_api_key ON organizations(api_key); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organizations' AND indexname = 'idx_organizations_plan') THEN CREATE INDEX idx_organizations_plan ON organizations(plan); END IF; END $$;

-- =====================================================
-- TABLE: users
-- Gestion des utilisateurs du systeme
-- =====================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role user_role NOT NULL DEFAULT 'USER',
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT false,
    email_verified BOOLEAN DEFAULT false,
    email_verification_token VARCHAR(255),
    reset_password_token VARCHAR(255),
    reset_password_expires TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
    edit_locked_at TIMESTAMP WITH TIME ZONE NULL,
    edit_lock_expires_at TIMESTAMP WITH TIME ZONE NULL
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'users' AND indexname = 'idx_users_email') THEN CREATE INDEX idx_users_email ON users(email); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'users' AND indexname = 'idx_users_edit_lock_expires') THEN CREATE INDEX idx_users_edit_lock_expires ON users(edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL; END IF; END $$;

ALTER TABLE organizations
  ADD COLUMN IF NOT EXISTS edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS edit_locked_at TIMESTAMP WITH TIME ZONE NULL,
  ADD COLUMN IF NOT EXISTS edit_lock_expires_at TIMESTAMP WITH TIME ZONE NULL;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organizations' AND indexname = 'idx_organizations_edit_lock_expires') THEN CREATE INDEX idx_organizations_edit_lock_expires ON organizations(edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'users' AND indexname = 'idx_users_role') THEN CREATE INDEX idx_users_role ON users(role); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'users' AND indexname = 'idx_users_organization_id') THEN CREATE INDEX idx_users_organization_id ON users(organization_id); END IF; END $$;

-- Add new columns for password reset and email verification (for existing databases)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='email_verification_token') THEN
    ALTER TABLE users ADD COLUMN email_verification_token VARCHAR(255);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='reset_password_token') THEN
    ALTER TABLE users ADD COLUMN reset_password_token VARCHAR(255);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='reset_password_expires') THEN
    ALTER TABLE users ADD COLUMN reset_password_expires TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

DROP TABLE IF EXISTS organization_users;

-- =====================================================
-- TABLE: guided_tours
-- Parcours guidés créés par les administrateurs
-- =====================================================
CREATE TABLE IF NOT EXISTS guided_tours (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    target_url VARCHAR(500) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    priority INTEGER DEFAULT 0,
    trigger_conditions JSONB DEFAULT '{}',
    simulation_context JSONB,
    replay_policy tour_replay_policy NOT NULL DEFAULT 'never',
    replay_after_days INTEGER NOT NULL DEFAULT 0,
    current_reset_version INTEGER NOT NULL DEFAULT 0,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='replay_policy') THEN
    ALTER TABLE guided_tours ADD COLUMN replay_policy tour_replay_policy NOT NULL DEFAULT 'never';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='replay_after_days') THEN
    ALTER TABLE guided_tours ADD COLUMN replay_after_days INTEGER NOT NULL DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='current_reset_version') THEN
    ALTER TABLE guided_tours ADD COLUMN current_reset_version INTEGER NOT NULL DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_private') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_private BOOLEAN NOT NULL DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='assigned_admin_ids') THEN
    ALTER TABLE guided_tours ADD COLUMN assigned_admin_ids UUID[] NOT NULL DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='assigned_to_admins_at') THEN
    ALTER TABLE guided_tours ADD COLUMN assigned_to_admins_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='edit_locked_by') THEN
    ALTER TABLE guided_tours ADD COLUMN edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='edit_locked_at') THEN
    ALTER TABLE guided_tours ADD COLUMN edit_locked_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='edit_lock_expires_at') THEN
    ALTER TABLE guided_tours ADD COLUMN edit_lock_expires_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_submission_message') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_submission_message TEXT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_view_share_message') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_view_share_message TEXT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_view_share_message_at') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_view_share_message_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_collaborate_share_message') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_collaborate_share_message TEXT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='developer_collaborate_share_message_at') THEN
    ALTER TABLE guided_tours ADD COLUMN developer_collaborate_share_message_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='environment') THEN
    ALTER TABLE guided_tours ADD COLUMN environment tour_environment NOT NULL DEFAULT 'production';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='sandbox_status') THEN
    ALTER TABLE guided_tours ADD COLUMN sandbox_status tour_sandbox_status NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='in_collaboration') THEN
    ALTER TABLE guided_tours ADD COLUMN in_collaboration BOOLEAN NOT NULL DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='show_in_guides') THEN
    ALTER TABLE guided_tours ADD COLUMN show_in_guides BOOLEAN NOT NULL DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='production_managed_by_admin_id') THEN
    ALTER TABLE guided_tours ADD COLUMN production_managed_by_admin_id UUID NULL REFERENCES users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='is_sandbox_test_active') THEN
    ALTER TABLE guided_tours ADD COLUMN is_sandbox_test_active BOOLEAN NOT NULL DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='sandbox_rejection_reason') THEN
    ALTER TABLE guided_tours ADD COLUMN sandbox_rejection_reason TEXT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='sandbox_rejected_at') THEN
    ALTER TABLE guided_tours ADD COLUMN sandbox_rejected_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='sandbox_rejected_by') THEN
    ALTER TABLE guided_tours ADD COLUMN sandbox_rejected_by UUID NULL REFERENCES users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guided_tours' AND column_name='sandbox_test_started_by') THEN
    ALTER TABLE guided_tours ADD COLUMN sandbox_test_started_by UUID NULL;
  END IF;
END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tours' AND indexname = 'idx_tours_org_id') THEN CREATE INDEX idx_tours_org_id ON guided_tours(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tours' AND indexname = 'idx_tours_active') THEN CREATE INDEX idx_tours_active ON guided_tours(is_active); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tours' AND indexname = 'idx_tours_target_url') THEN CREATE INDEX idx_tours_target_url ON guided_tours(target_url); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tours' AND indexname = 'idx_guided_tours_org_environment') THEN CREATE INDEX idx_guided_tours_org_environment ON guided_tours(organization_id, environment); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tours' AND indexname = 'idx_guided_tours_edit_lock_expires') THEN CREATE INDEX idx_guided_tours_edit_lock_expires ON guided_tours(edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL; END IF; END $$;

-- Partage parcours (lecture seule / collaboration sandbox)
CREATE TABLE IF NOT EXISTS guided_tour_access_grants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tour_id UUID NOT NULL REFERENCES guided_tours(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    access_mode tour_access_mode NOT NULL,
    granted_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tour_id, user_id)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tour_access_grants' AND indexname = 'idx_tour_access_grants_tour') THEN CREATE INDEX idx_tour_access_grants_tour ON guided_tour_access_grants(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tour_access_grants' AND indexname = 'idx_tour_access_grants_user') THEN CREATE INDEX idx_tour_access_grants_user ON guided_tour_access_grants(user_id); END IF; END $$;

-- Audit transferts propriété développeur
CREATE TABLE IF NOT EXISTS guided_tour_developer_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tour_id UUID NOT NULL REFERENCES guided_tours(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL,
    from_user_id UUID NOT NULL,
    to_user_id UUID NOT NULL,
    transferred_by UUID NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tour_developer_transfers' AND indexname = 'idx_tour_developer_transfers_tour') THEN CREATE INDEX idx_tour_developer_transfers_tour ON guided_tour_developer_transfers(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'guided_tour_developer_transfers' AND indexname = 'idx_tour_developer_transfers_org') THEN CREATE INDEX idx_tour_developer_transfers_org ON guided_tour_developer_transfers(organization_id); END IF; END $$;

-- =====================================================
-- TABLE: tour_user_states
-- Etat du parcours par utilisateur (dismissed/completed)
-- =====================================================
CREATE TABLE IF NOT EXISTS tour_user_states (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tour_id UUID NOT NULL REFERENCES guided_tours(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    environment tour_environment NOT NULL DEFAULT 'production',
    status tour_user_state_status NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    next_eligible_at TIMESTAMP WITH TIME ZONE,
    reset_version INTEGER NOT NULL DEFAULT 0,
    seen_count INTEGER NOT NULL DEFAULT 0,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_tour_user_states_tour_user_env UNIQUE (tour_id, user_id, environment)
);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='environment') THEN
    ALTER TABLE tour_user_states ADD COLUMN environment tour_environment NOT NULL DEFAULT 'production';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_tour_user_states_tour_user'
  ) THEN
    ALTER TABLE tour_user_states DROP CONSTRAINT uq_tour_user_states_tour_user;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_tour_user_states_tour_user_env'
  ) THEN
    ALTER TABLE tour_user_states
      ADD CONSTRAINT uq_tour_user_states_tour_user_env UNIQUE (tour_id, user_id, environment);
  END IF;
  UPDATE tour_user_states tus
  SET environment = 'sandbox'
  FROM guided_tours gt
  WHERE tus.tour_id = gt.id
    AND gt.environment = 'sandbox'
    AND tus.environment = 'production';
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='expires_at') THEN
    ALTER TABLE tour_user_states ADD COLUMN expires_at TIMESTAMP WITH TIME ZONE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='next_eligible_at') THEN
    ALTER TABLE tour_user_states ADD COLUMN next_eligible_at TIMESTAMP WITH TIME ZONE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='reset_version') THEN
    ALTER TABLE tour_user_states ADD COLUMN reset_version INTEGER NOT NULL DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='seen_count') THEN
    ALTER TABLE tour_user_states ADD COLUMN seen_count INTEGER NOT NULL DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tour_user_states' AND column_name='last_seen_at') THEN
    ALTER TABLE tour_user_states ADD COLUMN last_seen_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tour_user_states' AND indexname = 'idx_tour_user_states_org_user') THEN CREATE INDEX idx_tour_user_states_org_user ON tour_user_states(organization_id, user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tour_user_states' AND indexname = 'idx_tour_user_states_tour_id') THEN CREATE INDEX idx_tour_user_states_tour_id ON tour_user_states(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tour_user_states' AND indexname = 'idx_tour_user_states_tour_user_env') THEN CREATE INDEX idx_tour_user_states_tour_user_env ON tour_user_states(tour_id, user_id, environment); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tour_user_states' AND indexname = 'idx_tour_user_states_next_eligible_at') THEN CREATE INDEX idx_tour_user_states_next_eligible_at ON tour_user_states(next_eligible_at); END IF; END $$;

-- =====================================================
-- TABLE: steps
-- Étapes individuelles d'un parcours guidé
-- =====================================================
CREATE TABLE IF NOT EXISTS steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tour_id UUID NOT NULL REFERENCES guided_tours(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    target_selector VARCHAR(500),
    step_target_url VARCHAR(500),
    position position_type DEFAULT 'BOTTOM',
    action action_type DEFAULT 'NEXT',
    skip_allowed BOOLEAN DEFAULT true,
    highlight_element BOOLEAN DEFAULT true,
    step_type step_type DEFAULT 'highlight',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(tour_id, order_index)
);

-- Add step_type for existing databases
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='steps' AND column_name='step_type') THEN
        ALTER TABLE steps ADD COLUMN step_type step_type DEFAULT 'highlight';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='steps' AND column_name='step_target_url') THEN
        ALTER TABLE steps ADD COLUMN step_target_url VARCHAR(500);
    END IF;
END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'steps' AND indexname = 'idx_steps_tour_id') THEN CREATE INDEX idx_steps_tour_id ON steps(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'steps' AND indexname = 'idx_steps_order') THEN CREATE INDEX idx_steps_order ON steps(tour_id, order_index); END IF; END $$;

-- =====================================================
-- TABLE: user_progress
-- Suivi de la progression des utilisateurs
-- =====================================================
CREATE TABLE IF NOT EXISTS user_progress (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tour_id UUID NOT NULL REFERENCES guided_tours(id) ON DELETE CASCADE,
    current_step_id UUID REFERENCES steps(id) ON DELETE SET NULL,
    completed_steps UUID[] DEFAULT ARRAY[]::UUID[],
    status progress_status DEFAULT 'NOT_STARTED',
    completion_rate DECIMAL(5,2) DEFAULT 0.00,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    last_interaction_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, tour_id)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'user_progress' AND indexname = 'idx_progress_user_id') THEN CREATE INDEX idx_progress_user_id ON user_progress(user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'user_progress' AND indexname = 'idx_progress_tour_id') THEN CREATE INDEX idx_progress_tour_id ON user_progress(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'user_progress' AND indexname = 'idx_progress_status') THEN CREATE INDEX idx_progress_status ON user_progress(status); END IF; END $$;

-- =====================================================
-- TABLE: behavior_events
-- Événements de comportement utilisateur
-- =====================================================
CREATE TABLE IF NOT EXISTS behavior_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_id UUID NOT NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    event_type event_type NOT NULL,
    page_url VARCHAR(500) NOT NULL,
    element_selector VARCHAR(500),
    element_text VARCHAR(255),
    scroll_depth INTEGER,
    time_on_page INTEGER, -- en secondes
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_events' AND indexname = 'idx_events_user_id') THEN CREATE INDEX idx_events_user_id ON behavior_events(user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_events' AND indexname = 'idx_events_session_id') THEN CREATE INDEX idx_events_session_id ON behavior_events(session_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_events' AND indexname = 'idx_events_org_id') THEN CREATE INDEX idx_events_org_id ON behavior_events(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_events' AND indexname = 'idx_events_type') THEN CREATE INDEX idx_events_type ON behavior_events(event_type); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_events' AND indexname = 'idx_events_timestamp') THEN CREATE INDEX idx_events_timestamp ON behavior_events(timestamp); END IF; END $$;

-- =====================================================
-- TABLE: behavior_analysis
-- Analyses comportementales et prédictions
-- =====================================================
CREATE TABLE IF NOT EXISTS behavior_analysis (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_id UUID NOT NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    page_url VARCHAR(500) NOT NULL,
    time_on_page INTEGER DEFAULT 0,
    scroll_depth DECIMAL(5,2) DEFAULT 0.00,
    click_misses INTEGER DEFAULT 0,
    hesitations INTEGER DEFAULT 0,
    abandonment_risk DECIMAL(5,4) DEFAULT 0.0000,
    help_triggered BOOLEAN DEFAULT false,
    analyzed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_analysis' AND indexname = 'idx_analysis_user_id') THEN CREATE INDEX idx_analysis_user_id ON behavior_analysis(user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_analysis' AND indexname = 'idx_analysis_session_id') THEN CREATE INDEX idx_analysis_session_id ON behavior_analysis(session_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_analysis' AND indexname = 'idx_analysis_org_id') THEN CREATE INDEX idx_analysis_org_id ON behavior_analysis(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_analysis' AND indexname = 'idx_analysis_risk') THEN CREATE INDEX idx_analysis_risk ON behavior_analysis(abandonment_risk); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'behavior_analysis' AND indexname = 'idx_analysis_timestamp') THEN CREATE INDEX idx_analysis_timestamp ON behavior_analysis(analyzed_at); END IF; END $$;

-- =====================================================
-- TABLE: ml_models
-- Modèles de machine learning
-- =====================================================
CREATE TABLE IF NOT EXISTS ml_models (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id VARCHAR(100) UNIQUE NOT NULL,
    version VARCHAR(50) NOT NULL,
    algorithm VARCHAR(100) DEFAULT 'LightGBM',
    hyperparameters JSONB DEFAULT '{}',
    training_data_count INTEGER DEFAULT 0,
    accuracy DECIMAL(5,4),
    precision_score DECIMAL(5,4),
    recall_score DECIMAL(5,4),
    f1_score DECIMAL(5,4),
    is_active BOOLEAN DEFAULT false,
    trained_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'ml_models' AND indexname = 'idx_models_active') THEN CREATE INDEX idx_models_active ON ml_models(is_active); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'ml_models' AND indexname = 'idx_models_version') THEN CREATE INDEX idx_models_version ON ml_models(version); END IF; END $$;

-- =====================================================
-- TABLE: sidebars
-- Configuration de la sidebar d'aide
-- =====================================================
CREATE TABLE IF NOT EXISTS sidebars (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID UNIQUE NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title VARCHAR(255) DEFAULT 'Aide',
    position sidebar_position DEFAULT 'RIGHT',
    theme JSONB DEFAULT '{"primaryColor": "#007bff", "backgroundColor": "#ffffff"}',
    show_faq BOOLEAN DEFAULT true,
    show_tutorials BOOLEAN DEFAULT true,
    show_support BOOLEAN DEFAULT true,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'sidebars' AND indexname = 'idx_sidebar_org_id') THEN CREATE INDEX idx_sidebar_org_id ON sidebars(organization_id); END IF; END $$;

-- =====================================================
-- TABLE: faq_items
-- Questions-réponses de la FAQ avec embeddings
-- =====================================================
CREATE TABLE IF NOT EXISTS faq_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_key VARCHAR(120) NOT NULL DEFAULT 'default',
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    category VARCHAR(100),
    tags VARCHAR(50)[] DEFAULT ARRAY[]::VARCHAR[],
    --embedding vector(384), -- sentence-transformers all-MiniLM-L6-v2
    view_count INTEGER DEFAULT 0,
    helpful_count INTEGER DEFAULT 0,
    not_helpful_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    content_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
    edit_locked_at TIMESTAMP WITH TIME ZONE NULL,
    edit_lock_expires_at TIMESTAMP WITH TIME ZONE NULL
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'edit_locked_by') THEN
    ALTER TABLE faq_items ADD COLUMN edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'edit_locked_at') THEN
    ALTER TABLE faq_items ADD COLUMN edit_locked_at TIMESTAMP WITH TIME ZONE NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'edit_lock_expires_at') THEN
    ALTER TABLE faq_items ADD COLUMN edit_lock_expires_at TIMESTAMP WITH TIME ZONE NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'project_key') THEN
    ALTER TABLE faq_items ADD COLUMN project_key VARCHAR(120) NOT NULL DEFAULT 'default';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'content_updated_at') THEN
    ALTER TABLE faq_items ADD COLUMN content_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    UPDATE faq_items SET content_updated_at = created_at;
  END IF;
END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_org_project') THEN CREATE INDEX idx_faq_org_project ON faq_items(organization_id, project_key); END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_items_edit_lock_expires') THEN CREATE INDEX idx_faq_items_edit_lock_expires ON faq_items(edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL; END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_org_id') THEN CREATE INDEX idx_faq_org_id ON faq_items(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_category') THEN CREATE INDEX idx_faq_category ON faq_items(category); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_active') THEN CREATE INDEX idx_faq_active ON faq_items(is_active); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_search') THEN CREATE INDEX idx_faq_search ON faq_items USING GIN (to_tsvector('english', question || ' ' || answer)); END IF; END $$;
--DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_embedding') THEN CREATE INDEX idx_faq_embedding ON faq_items USING ivfflat (embedding vector_cosine_ops); END IF; END $$;

-- =====================================================
-- TABLE: faq_projects
-- Paquets FAQ enregistrés (visibles même sans question)
-- =====================================================
CREATE TABLE IF NOT EXISTS faq_projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_key VARCHAR(120) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_faq_projects_org_key UNIQUE (organization_id, project_key)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'faq_projects' AND indexname = 'idx_faq_projects_org') THEN CREATE INDEX idx_faq_projects_org ON faq_projects(organization_id); END IF; END $$;

-- =====================================================
-- TABLE: tutorials
-- Tutoriels vidéo et guides
-- =====================================================
CREATE TABLE IF NOT EXISTS tutorials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    video_url VARCHAR(500),
    thumbnail_url VARCHAR(500),
    duration INTEGER, -- en secondes
    category VARCHAR(100),
    tags VARCHAR(50)[] DEFAULT ARRAY[]::VARCHAR[],
    order_index INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tutorials' AND indexname = 'idx_tutorials_org_id') THEN CREATE INDEX idx_tutorials_org_id ON tutorials(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tutorials' AND indexname = 'idx_tutorials_category') THEN CREATE INDEX idx_tutorials_category ON tutorials(category); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tutorials' AND indexname = 'idx_tutorials_active') THEN CREATE INDEX idx_tutorials_active ON tutorials(is_active); END IF; END $$;

-- =====================================================
-- TABLE: tutorial_views
-- Suivi des vues de tutoriels
-- =====================================================
CREATE TABLE IF NOT EXISTS tutorial_views (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tutorial_id UUID NOT NULL REFERENCES tutorials(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_id UUID NOT NULL,
    watch_duration INTEGER DEFAULT 0, -- en secondes
    completed BOOLEAN DEFAULT false,
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tutorial_views' AND indexname = 'idx_tutorial_views_tutorial_id') THEN CREATE INDEX idx_tutorial_views_tutorial_id ON tutorial_views(tutorial_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tutorial_views' AND indexname = 'idx_tutorial_views_user_id') THEN CREATE INDEX idx_tutorial_views_user_id ON tutorial_views(user_id); END IF; END $$;

-- =====================================================
-- TABLE: support_tickets
-- Tickets de support créés par les utilisateurs
-- =====================================================
CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    subject VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status ticket_status DEFAULT 'OPEN',
    priority priority_level DEFAULT 'MEDIUM',
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    page_url VARCHAR(500),
    project_key VARCHAR(120) NOT NULL DEFAULT 'default',
    session_data JSONB DEFAULT '{}',
    admin_replies JSONB NOT NULL DEFAULT '[]'::jsonb,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_org_id') THEN CREATE INDEX idx_tickets_org_id ON support_tickets(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_user_id') THEN CREATE INDEX idx_tickets_user_id ON support_tickets(user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_status') THEN CREATE INDEX idx_tickets_status ON support_tickets(status); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_priority') THEN CREATE INDEX idx_tickets_priority ON support_tickets(priority); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_assigned') THEN CREATE INDEX idx_tickets_assigned ON support_tickets(assigned_to); END IF; END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'project_key') THEN
    ALTER TABLE support_tickets ADD COLUMN project_key VARCHAR(120) NOT NULL DEFAULT 'default';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'admin_replies') THEN
    ALTER TABLE support_tickets ADD COLUMN admin_replies JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'deleted_at') THEN
    ALTER TABLE support_tickets ADD COLUMN deleted_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'deleted_by') THEN
    ALTER TABLE support_tickets ADD COLUMN deleted_by UUID NULL REFERENCES users(id) ON DELETE SET NULL;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'collaborators') THEN
    ALTER TABLE support_tickets ADD COLUMN collaborators JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'edit_locked_by') THEN
    ALTER TABLE support_tickets ADD COLUMN edit_locked_by UUID NULL REFERENCES users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'edit_locked_at') THEN
    ALTER TABLE support_tickets ADD COLUMN edit_locked_at TIMESTAMPTZ NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'edit_lock_expires_at') THEN
    ALTER TABLE support_tickets ADD COLUMN edit_lock_expires_at TIMESTAMPTZ NULL;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'assigned_at') THEN
    ALTER TABLE support_tickets ADD COLUMN assigned_at TIMESTAMPTZ NULL;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_tickets' AND column_name = 'lifecycle_history') THEN
    ALTER TABLE support_tickets ADD COLUMN lifecycle_history JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_org_project') THEN CREATE INDEX idx_tickets_org_project ON support_tickets(organization_id, project_key); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'support_tickets' AND indexname = 'idx_tickets_edit_lock_expires') THEN CREATE INDEX idx_tickets_edit_lock_expires ON support_tickets(edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL; END IF; END $$;

-- =====================================================
-- TABLE: analytics
-- Métriques et statistiques d'utilisation
-- =====================================================
CREATE TABLE IF NOT EXISTS analytics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    tour_id UUID REFERENCES guided_tours(id) ON DELETE CASCADE,
    metric_type metric_type NOT NULL,
    metric_value DECIMAL(10,2) NOT NULL,
    metadata JSONB DEFAULT '{}',
    period_start TIMESTAMP WITH TIME ZONE,
    period_end TIMESTAMP WITH TIME ZONE,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'analytics' AND indexname = 'idx_analytics_org_id') THEN CREATE INDEX idx_analytics_org_id ON analytics(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'analytics' AND indexname = 'idx_analytics_tour_id') THEN CREATE INDEX idx_analytics_tour_id ON analytics(tour_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'analytics' AND indexname = 'idx_analytics_metric_type') THEN CREATE INDEX idx_analytics_metric_type ON analytics(metric_type); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'analytics' AND indexname = 'idx_analytics_period') THEN CREATE INDEX idx_analytics_period ON analytics(period_start, period_end); END IF; END $$;

-- =====================================================
-- TABLE: generated_responses
-- Réponses générées par le RAG pour analytics
-- =====================================================
CREATE TABLE IF NOT EXISTS generated_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    query TEXT NOT NULL,
    generated_answer TEXT NOT NULL,
    context_faq_ids UUID[] DEFAULT ARRAY[]::UUID[],
    similarity_score DECIMAL(5,4),
    was_helpful BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'generated_responses' AND indexname = 'idx_generated_org_id') THEN CREATE INDEX idx_generated_org_id ON generated_responses(organization_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'generated_responses' AND indexname = 'idx_generated_user_id') THEN CREATE INDEX idx_generated_user_id ON generated_responses(user_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'generated_responses' AND indexname = 'idx_generated_timestamp') THEN CREATE INDEX idx_generated_timestamp ON generated_responses(created_at); END IF; END $$;

-- =====================================================
-- TABLE: contextual_feedback_aggregates
-- Agrégats cross-utilisateur des feedback contextuels (Phase 2 SDK)
-- =====================================================
CREATE TABLE IF NOT EXISTS contextual_feedback_aggregates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    target_url VARCHAR(500) NOT NULL,
    selector VARCHAR(1024) NOT NULL,
    intent VARCHAR(64) NOT NULL,
    shown_count INTEGER NOT NULL DEFAULT 0,
    clicked_count INTEGER NOT NULL DEFAULT 0,
    completed_count INTEGER NOT NULL DEFAULT 0,
    skipped_count INTEGER NOT NULL DEFAULT 0,
    first_seen_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_contextual_feedback_key UNIQUE (organization_id, target_url, selector, intent)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'contextual_feedback_aggregates' AND indexname = 'idx_contextual_feedback_org_url') THEN CREATE INDEX idx_contextual_feedback_org_url ON contextual_feedback_aggregates(organization_id, target_url); END IF; END $$;

-- =====================================================
-- FONCTIONS ET TRIGGERS
-- =====================================================

-- Fonction pour mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers pour updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users; CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_organizations_updated_at ON organizations; CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_guided_tours_updated_at ON guided_tours; CREATE TRIGGER update_guided_tours_updated_at BEFORE UPDATE ON guided_tours FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_tour_user_states_updated_at ON tour_user_states; CREATE TRIGGER update_tour_user_states_updated_at BEFORE UPDATE ON tour_user_states FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_steps_updated_at ON steps; CREATE TRIGGER update_steps_updated_at BEFORE UPDATE ON steps FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_user_progress_updated_at ON user_progress; CREATE TRIGGER update_user_progress_updated_at BEFORE UPDATE ON user_progress FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_sidebars_updated_at ON sidebars; CREATE TRIGGER update_sidebars_updated_at BEFORE UPDATE ON sidebars FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_faq_items_updated_at ON faq_items; CREATE TRIGGER update_faq_items_updated_at BEFORE UPDATE ON faq_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_tutorials_updated_at ON tutorials; CREATE TRIGGER update_tutorials_updated_at BEFORE UPDATE ON tutorials FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS update_support_tickets_updated_at ON support_tickets; CREATE TRIGGER update_support_tickets_updated_at BEFORE UPDATE ON support_tickets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Fonction pour calculer le taux de complétion
CREATE OR REPLACE FUNCTION calculate_completion_rate()
RETURNS TRIGGER AS $$
DECLARE
    total_steps INTEGER;
    completed_count INTEGER;
BEGIN
    -- Compter le nombre total d'étapes dans le tour
    SELECT COUNT(*) INTO total_steps
    FROM steps
    WHERE tour_id = NEW.tour_id;
    
    -- Compter le nombre d'étapes complétées
    completed_count := array_length(NEW.completed_steps, 1);
    
    IF completed_count IS NULL THEN
        completed_count := 0;
    END IF;
    
    -- Calculer le taux de complétion
    IF total_steps > 0 THEN
        NEW.completion_rate := (completed_count::DECIMAL / total_steps::DECIMAL) * 100;
    ELSE
        NEW.completion_rate := 0;
    END IF;
    
    -- Mettre à jour le statut si complet
    IF NEW.completion_rate >= 100 THEN
        NEW.status := 'COMPLETED';
        NEW.completed_at := NOW();
    ELSIF NEW.completion_rate > 0 THEN
        NEW.status := 'IN_PROGRESS';
    END IF;
    
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_completion_rate ON user_progress;
CREATE TRIGGER update_completion_rate 
BEFORE INSERT OR UPDATE ON user_progress 
FOR EACH ROW EXECUTE FUNCTION calculate_completion_rate();

-- Fonction pour générer une API key unique
CREATE OR REPLACE FUNCTION generate_api_key()
RETURNS TEXT AS $$
BEGIN
    RETURN 'onb_' || encode(gen_random_bytes(32), 'hex');
END;
$$ language 'plpgsql';

-- =====================================================
-- VUES UTILES
-- =====================================================

-- Vue pour les statistiques de tours
DROP VIEW IF EXISTS tour_statistics;
CREATE VIEW tour_statistics AS
SELECT 
    t.id as tour_id,
    t.name as tour_name,
    t.organization_id,
    COUNT(DISTINCT up.user_id) as total_users,
    COUNT(DISTINCT CASE WHEN up.status = 'COMPLETED' THEN up.user_id END) as completed_users,
    COUNT(DISTINCT CASE WHEN up.status = 'ABANDONED' THEN up.user_id END) as abandoned_users,
    ROUND(AVG(up.completion_rate), 2) as avg_completion_rate,
    COUNT(DISTINCT s.id) as total_steps
FROM guided_tours t
LEFT JOIN user_progress up ON t.id = up.tour_id
LEFT JOIN steps s ON t.id = s.tour_id
GROUP BY t.id, t.name, t.organization_id;

-- Vue pour les utilisateurs actifs
DROP VIEW IF EXISTS active_users_summary;
CREATE VIEW active_users_summary AS
SELECT 
    o.id as organization_id,
    o.name as organization_name,
    COUNT(DISTINCT up.user_id) as active_users,
    COUNT(DISTINCT CASE WHEN up.last_interaction_at > NOW() - INTERVAL '7 days' THEN up.user_id END) as weekly_active_users,
    COUNT(DISTINCT CASE WHEN up.last_interaction_at > NOW() - INTERVAL '30 days' THEN up.user_id END) as monthly_active_users
FROM organizations o
LEFT JOIN user_progress up ON o.id = (SELECT organization_id FROM guided_tours WHERE id = up.tour_id LIMIT 1)
GROUP BY o.id, o.name;

-- =====================================================
-- DEV SEED: default org + admin (UI sign-up not wired yet)
-- Email: admin@trustdev.local   Password: Trustdev123!
-- password_hash = bcrypt(Trustdev123!, cost 10) — matches Nest bcrypt.compare
-- =====================================================

INSERT INTO organizations (id, name, api_key, plan, is_active)
SELECT '00000000-0000-0000-0000-000000000001'::uuid,
       'Dev Organization',
       'dev-local-onboarding-api-key-seed',
       'ENTERPRISE'::plan_type,
       true
WHERE NOT EXISTS (
  SELECT 1 FROM organizations WHERE api_key = 'dev-local-onboarding-api-key-seed'
);

INSERT INTO users (id, email, password_hash, first_name, last_name, role, organization_id, is_active, email_verified)
SELECT '00000000-0000-0000-0000-000000000002'::uuid,
       'admin@trustdev.local',
       '$2b$10$p8v2xrIqueT3UG8NE5mf.O0jPEzEF21sY9s5bWcqyBgDgVtx/qvCu',
       'Admin',
       'Seed',
       'SUPER_ADMIN'::user_role,
       NULL,
       true,
       true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@trustdev.local');

UPDATE users
SET role = 'SUPER_ADMIN'::user_role,
    organization_id = NULL
WHERE email = 'admin@trustdev.local'
  AND role = 'ADMIN'::user_role;

-- =====================================================
-- Custom journey blueprints (dashboard + SDK remote fetch)
-- =====================================================
CREATE TABLE IF NOT EXISTS organization_journey_blueprints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    blueprint_id VARCHAR(128) NOT NULL,
    vertical VARCHAR(32) NOT NULL,
    is_published BOOLEAN NOT NULL DEFAULT false,
    payload JSONB NOT NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    edit_locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
    edit_locked_at TIMESTAMP WITH TIME ZONE,
    edit_lock_expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_org_journey_blueprint_id UNIQUE (organization_id, blueprint_id)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organization_journey_blueprints' AND indexname = 'idx_org_journey_blueprints_org_published') THEN
  CREATE INDEX idx_org_journey_blueprints_org_published ON organization_journey_blueprints (organization_id, is_published);
END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organization_journey_blueprints' AND indexname = 'idx_org_journey_blueprints_edit_lock_expires') THEN
  CREATE INDEX idx_org_journey_blueprints_edit_lock_expires ON organization_journey_blueprints (edit_lock_expires_at) WHERE edit_locked_by IS NOT NULL;
END IF; END $$;

DO $$ BEGIN
  CREATE TYPE blueprint_access_mode AS ENUM ('modify', 'publish');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS organization_journey_blueprint_access_grants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blueprint_row_id UUID NOT NULL REFERENCES organization_journey_blueprints(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    access_mode blueprint_access_mode NOT NULL,
    granted_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_blueprint_access_grant_user_mode UNIQUE (blueprint_row_id, user_id, access_mode)
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organization_journey_blueprint_access_grants' AND indexname = 'idx_blueprint_access_grants_row') THEN
  CREATE INDEX idx_blueprint_access_grants_row ON organization_journey_blueprint_access_grants (blueprint_row_id);
END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'organization_journey_blueprint_access_grants' AND indexname = 'idx_blueprint_access_grants_user') THEN
  CREATE INDEX idx_blueprint_access_grants_user ON organization_journey_blueprint_access_grants (user_id);
END IF; END $$;

DROP TRIGGER IF EXISTS update_organization_journey_blueprints_updated_at ON organization_journey_blueprints;
CREATE TRIGGER update_organization_journey_blueprints_updated_at
  BEFORE UPDATE ON organization_journey_blueprints
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- SDK integration tokens (PAT) for embedded apps
CREATE TABLE IF NOT EXISTS sdk_integration_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(120) NOT NULL,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    token_suffix VARCHAR(12) NOT NULL,
    scopes JSONB NOT NULL DEFAULT '[]',
    revoked_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'sdk_integration_tokens' AND indexname = 'idx_sdk_tokens_org_active') THEN
  CREATE INDEX idx_sdk_tokens_org_active ON sdk_integration_tokens (organization_id, revoked_at);
END IF; END $$;