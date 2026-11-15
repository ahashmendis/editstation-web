-- Phase 12A: function security and role refusals. The 046 catalogue rules also run over the new
-- functions.
begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

create function pg_temp.state_as(p_uid uuid, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    v := case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
  reset role;
  return v;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('95000000-0000-0000-0000-00000000000a', 'p12x-admin@test.local', '{}', '{}'),
  ('95000000-0000-0000-0000-000000000001', 'p12x-editor-a@test.local', '{}', '{}'),
  ('95000000-0000-0000-0000-000000000003', 'p12x-applicant@test.local', '{}', '{}'),
  ('95000000-0000-0000-0000-000000000004', 'p12x-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12x-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active' where user_id = '95000000-0000-0000-0000-000000000001';
update public.editor_profiles set access_status = 'suspended' where user_id = '95000000-0000-0000-0000-000000000004';

create temp table pub (sig text primary key, call text not null, editor boolean not null);
insert into pub values
  ('public.admin_save_terms_draft(uuid, jsonb)',
   $$ select public.admin_save_terms_draft(gen_random_uuid(), '{}') $$, false),
  ('public.admin_agree_terms(uuid, integer, text)', $$ select public.admin_agree_terms(gen_random_uuid(), 1) $$, false),
  ('public.editor_get_terms(uuid)', $$ select * from public.editor_get_terms(gen_random_uuid()) $$, true);
grant select on pub to authenticated, anon;

create temp table priv (sig text primary key);
insert into priv values
  ('private.terms_shares_valid(smallint[])'), ('private.guard_project_terms()'), ('private.guard_project_terms_stages()'),
  ('private.guard_revision_allowance()'), ('private.create_initial_terms()'), ('private.project_work_started(uuid)'),
  ('private.project_has_live_editor(uuid)'), ('private.terms_ready(uuid)'), ('private.jsonb_days(jsonb, text, text)'),
  ('private.parse_terms_shares(jsonb)'), ('private.parse_terms_stages(jsonb)'), ('private.terms_stage_map(uuid, boolean)');

select ok((select bool_and(has_function_privilege('anon', sig::regprocedure, 'execute')
                           and has_function_privilege('authenticated', sig::regprocedure, 'execute')) from pub)
  and (select count(*) = 3 from pub), 'the three public functions exist and are executable by anon and authenticated');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0) $$,
  'every Phase 12A public function is security definer, has an empty search_path and no PUBLIC grant');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where (sig like 'public.admin\_%' and f.prosrc not like '%private.require_admin()%')
     or (sig like 'public.editor\_%' and f.prosrc not like '%private.require_active_editor()%') $$,
  'admin functions call require_admin and editor functions require_active_editor');
select is_empty($$ select sig from priv p join pg_proc f on f.oid = p.sig::regprocedure
  where not ('search_path=""' = any (coalesce(f.proconfig, '{}'))) $$,
  'Phase 12A private functions have an empty search_path');
select is_empty($$ select sig from priv
  where has_function_privilege('anon', sig::regprocedure, 'execute')
     or has_function_privilege('authenticated', sig::regprocedure, 'execute') $$,
  'no Phase 12A private function is executable by an API role');

select set_eq($$
  select p.sig || ' ' || who.name || ' ' || pg_temp.state_as(who.uid, who.aal, p.call)
  from pub p cross join (values
    ('anon', null::uuid, 'aal1'), ('admin_aal1', '95000000-0000-0000-0000-00000000000a'::uuid, 'aal1'),
    ('editor_a', '95000000-0000-0000-0000-000000000001'::uuid, 'aal1'),
    ('suspended', '95000000-0000-0000-0000-000000000004'::uuid, 'aal1'),
    ('applicant', '95000000-0000-0000-0000-000000000003'::uuid, 'aal1')) who(name, uid, aal)
  where not (p.editor and who.name = 'editor_a') $$,
  $$ select p.sig || ' ' || who.name || ' ' || case when who.name = 'anon' then 'ES401' else 'ES403' end
  from pub p cross join (values ('anon'), ('admin_aal1'), ('editor_a'), ('suspended'), ('applicant')) who(name)
  where not (p.editor and who.name = 'editor_a') $$,
  'anon gets ES401 and every other wrong identity ES403');
select is(pg_temp.state_as('95000000-0000-0000-0000-00000000000a', 'aal2',
  $$ select public.admin_save_terms_draft(gen_random_uuid(), '{}') $$), 'ES422', 'an unknown project is not found');

select * from finish();
rollback;
