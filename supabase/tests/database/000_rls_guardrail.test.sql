-- Guardrail: every table in the public schema must have Row Level Security enabled.
-- This holds before any tables exist and keeps holding as migrations are added.
-- Run with: npm run db:test   (requires `npm run db:start`)
begin;

create extension if not exists pgtap with schema extensions;

select plan(1);

select is_empty(
  $$
    select c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  $$,
  'every table in the public schema has RLS enabled'
);

select * from finish();

rollback;
