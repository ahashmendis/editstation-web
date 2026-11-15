-- Phase 12D part 2 (1/5): payment_status.cancelled (spec §4.3, call 2; revises decision I). A row
-- is cancelled only by a cancellation settlement and is final, like paid. Alone in its migration:
-- Postgres refuses to use a new enum value in the transaction that adds it.
alter type public.payment_status add value 'cancelled';
