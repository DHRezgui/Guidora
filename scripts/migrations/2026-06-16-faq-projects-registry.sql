-- FAQ project packs registry (empty projects visible in dashboard before first question)
CREATE TABLE IF NOT EXISTS faq_projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_key VARCHAR(120) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_faq_projects_org_key UNIQUE (organization_id, project_key)
);

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'faq_projects' AND indexname = 'idx_faq_projects_org'
  ) THEN
    CREATE INDEX idx_faq_projects_org ON faq_projects(organization_id);
  END IF;
END $$;
