-- Schema guardrails that must hold as migrations are added.
-- Run with: npm run db:test   (requires local Supabase running)
begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

-- 1. Every table in the public schema has Row Level Security enabled.
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

-- 2. Every function in the public (API-exposed) schema is executable by BOTH
--    anon and authenticated, and must authorise inside its own body.
--    Why: in this Supabase Postgres image, a "permission denied for function"
--    raised for anon/authenticated crashes the server (supautils hint bug), so a
--    public function that an API role cannot execute is a denial-of-service hole.
--    Functions that are not meant for the API belong in the `private` schema.
select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (
        select 1 from pg_catalog.pg_depend d
        where d.objid = p.oid and d.deptype = 'e'
      )
      and not (
        has_function_privilege('anon', p.oid, 'execute')
        and has_function_privilege('authenticated', p.oid, 'execute')
      )
  $$,
  'every public function is executable by anon and authenticated (authorise in the body)'
);

select * from finish();

rollback;
