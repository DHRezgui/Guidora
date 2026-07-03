-- Track FAQ corpus changes separately from usage metrics (views / helpful votes).
-- Prevents false "reindex required" after SDK tracking updates touch updated_at.

ALTER TABLE faq_items
  ADD COLUMN IF NOT EXISTS content_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE faq_items
SET content_updated_at = created_at;
