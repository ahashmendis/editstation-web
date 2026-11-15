-- Phase 12B (1/3): notification_kind.asset_inaccessible (KB7a-3, spec §6). Alone in its migration:
-- Postgres refuses to use a new enum value in the transaction that adds it.
alter type public.notification_kind add value 'asset_inaccessible';
