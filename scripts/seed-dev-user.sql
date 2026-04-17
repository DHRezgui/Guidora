-- Idempotent dev seed (run anytime against an existing DB), e.g.:
-- docker compose -f docker-compose.dev.yml exec -T postgres \
--   psql -U admin -d onboarding -v ON_ERROR_STOP=1 -f /dev/stdin < scripts/seed-dev-user.sql
--
-- Login: admin@trustdev.local / Trustdev123!

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
       'ADMIN'::user_role,
       (SELECT id FROM organizations WHERE api_key = 'dev-local-onboarding-api-key-seed' LIMIT 1),
       true,
       true
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@trustdev.local')
  AND EXISTS (
    SELECT 1 FROM organizations WHERE api_key = 'dev-local-onboarding-api-key-seed'
  );
