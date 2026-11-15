-- Phase 12D (1/3): notification_kind.late_balance_payable (spec §6, call 8: late-balance protection
-- triggered, admin). Alone in its migration: Postgres refuses to use a new enum value in the
-- transaction that adds it.
alter type public.notification_kind add value 'late_balance_payable';
