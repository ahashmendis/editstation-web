-- Phase 7 (1/6): assignment_status.in_progress. Alone in its migration: Postgres refuses to use a
-- new enum value in the transaction that adds it. Spec 2026-11-14-phase7 §5.
alter type public.assignment_status add value 'in_progress' after 'confirmed';
