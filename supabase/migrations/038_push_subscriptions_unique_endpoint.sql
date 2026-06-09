-- Migration 038: Add unique constraint on push_subscriptions.endpoint for upsert support

-- Drop existing index if it exists (to avoid conflicts)
DROP INDEX IF EXISTS idx_push_subscriptions_endpoint;

-- Create unique index on endpoint (required for ON CONFLICT upsert)
CREATE UNIQUE INDEX idx_push_subscriptions_endpoint ON push_subscriptions(endpoint);
