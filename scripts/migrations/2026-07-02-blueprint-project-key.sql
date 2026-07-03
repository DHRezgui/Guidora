-- Scope organization journey blueprints to SDK project / flowVersion (aligned with FAQ project_key).
ALTER TABLE organization_journey_blueprints
  ADD COLUMN IF NOT EXISTS project_key VARCHAR(120) NOT NULL DEFAULT 'default';

CREATE INDEX IF NOT EXISTS idx_org_journey_blueprints_org_project
  ON organization_journey_blueprints (organization_id, project_key);

COMMENT ON COLUMN organization_journey_blueprints.project_key IS
  'SDK project key (same convention as FAQ project_key / contextualEngine.flowVersion).';
