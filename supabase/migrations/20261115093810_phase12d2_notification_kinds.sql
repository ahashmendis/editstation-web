-- Phase 12D part 2 (2/5): notification kinds adjustment_offered (to the editor) and
-- adjustment_answered (to admins) (spec §6, call 8). Alone in their migration: a new enum value
-- cannot be used in the transaction that adds it.
alter type public.notification_kind add value 'adjustment_offered';
alter type public.notification_kind add value 'adjustment_answered';
