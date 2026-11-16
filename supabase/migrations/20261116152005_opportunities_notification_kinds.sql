-- Open opportunities (1/3): notification kinds. Spec docs/superpowers/specs/2026-11-16-open-opportunities-design.md
-- §4 and call 6 (owner approved 2026-11-16, decisions log "B/C amended").
--   interest_registered      -> admins, one per new interest
--   opportunity_selected     -> the chosen editor
--   opportunity_not_selected -> every other interested editor when the opportunity closes
-- Alone in its migration: a new enum value cannot be used in the transaction that adds it.
alter type public.notification_kind add value 'interest_registered';
alter type public.notification_kind add value 'opportunity_selected';
alter type public.notification_kind add value 'opportunity_not_selected';
