-- Phase 12C (1/4): notification_kind.project_auto_held (spec §6, call 8). Alone in its migration:
-- Postgres refuses to use a new enum value in the transaction that adds it.
alter type public.notification_kind add value 'project_auto_held';
