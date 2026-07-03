-- FAQ Option A: scope entries by project_key (non-destructive; preserves tours and other data)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'faq_items' AND column_name = 'project_key'
  ) THEN
    ALTER TABLE faq_items ADD COLUMN project_key VARCHAR(120) NOT NULL DEFAULT 'default';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'faq_items' AND indexname = 'idx_faq_org_project'
  ) THEN
    CREATE INDEX idx_faq_org_project ON faq_items(organization_id, project_key);
  END IF;
END $$;

-- Ensure legacy rows without explicit value stay on the default pack
UPDATE faq_items SET project_key = 'default' WHERE project_key IS NULL OR btrim(project_key) = '';
