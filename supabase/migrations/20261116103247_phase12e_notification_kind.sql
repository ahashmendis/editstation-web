-- Phase 12E (1/3): notification kind payout_details_changed (to admins) (spec §4.8, decision E:
-- every payout change is flagged to the admin for phone verification). Alone in its migration: a
-- new enum value cannot be used in the transaction that adds it.
alter type public.notification_kind add value 'payout_details_changed';
