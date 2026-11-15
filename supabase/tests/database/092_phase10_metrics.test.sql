-- Phase 10: admin dashboard metrics (KB §14), admin-only and computed from stored data.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

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
  ('92000000-0000-0000-0000-00000000000a', 'p10m-admin@test.local', '{}', '{}'),
  ('92000000-0000-0000-0000-000000000001', 'p10m-editor-a@test.local', '{}', '{}'),
  ('92000000-0000-0000-0000-000000000002', 'p10m-editor-b@test.local', '{}', '{}'),
  ('92000000-0000-0000-0000-000000000003', 'p10m-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p10m-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('92000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002');

-- Refusals
select is(pg_temp.state_as(null, null, $$ select public.admin_dashboard_metrics() $$), 'ES401', 'anon is refused');
select is(pg_temp.state_as('92000000-0000-0000-0000-000000000001', 'aal1', $$ select public.admin_dashboard_metrics() $$),
  'ES403', 'editor A is refused');
select is(pg_temp.state_as('92000000-0000-0000-0000-000000000002', 'aal1', $$ select public.admin_dashboard_metrics() $$),
  'ES403', 'editor B is refused');
select is(pg_temp.state_as('92000000-0000-0000-0000-000000000003', 'aal1', $$ select public.admin_dashboard_metrics() $$),
  'ES403', 'a pending applicant is refused');
select is(pg_temp.state_as('92000000-0000-0000-0000-00000000000a', 'aal1', $$ select public.admin_dashboard_metrics() $$),
  'ES403', 'an admin without two-step verification is refused');
select ok(has_function_privilege('anon', 'public.admin_dashboard_metrics()', 'execute')
      and has_function_privilege('authenticated', 'public.admin_dashboard_metrics()', 'execute'),
  'follows the public-function rule');

-- Values: compare before and after adding known rows
create temp table m (k text primary key, v jsonb);
grant select, insert on m to authenticated;
select pg_temp.as_user('92000000-0000-0000-0000-00000000000a', 'aal2');
insert into m select 'before', public.admin_dashboard_metrics();
reset role;

insert into public.client_inquiries (contact_name, email, service_type_code, service_type_label,
  description, budget_label, privacy_notice_version, status)
values ('M One', 'm1@example.com', 'long_form', 'Long-form video', 'x', 'Prefer to discuss', 'v', 'new'),
       ('M Two', 'm2@example.com', 'long_form', 'Long-form video', 'x', 'Prefer to discuss', 'v', 'spam');
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('92000000-0000-0000-0000-0000000000f1', 'Metric Project', 'fully_instructed', 'open', now());
insert into public.assignments (id, project_id, editor_id, status, proposed_amount) values
  ('92000000-0000-0000-0000-0000000000b1', '92000000-0000-0000-0000-0000000000f1',
   '92000000-0000-0000-0000-000000000001', 'offered', 5000);
update public.editor_profiles set access_status = 'suspended' where user_id = '92000000-0000-0000-0000-000000000002';

select pg_temp.as_user('92000000-0000-0000-0000-00000000000a', 'aal2');
insert into m select 'after', public.admin_dashboard_metrics();
reset role;

create function pg_temp.d(p_path text[]) returns numeric language sql as $$
  select coalesce((select (v #>> p_path)::numeric from m where k = 'after'), 0)
       - coalesce((select (v #>> p_path)::numeric from m where k = 'before'), 0) $$;

select ok((select v ?& array['inquiries', 'applications', 'editors', 'projects', 'assignments', 'delivery',
    'revisions', 'payments', 'generated_at'] from m where k = 'after'), 'all metric groups are present');
select is(pg_temp.d('{inquiries,by_status,new}'), 1::numeric, 'new inquiries counted by status');
select is(pg_temp.d('{inquiries,by_status,spam}'), 1::numeric, 'spam counted by status');
select is(pg_temp.d('{projects,by_status,open}'), 1::numeric, 'projects counted by status');
select is(pg_temp.d('{editors,active}'), -1::numeric, 'active editors counted (one suspended)');
select ok((select (v #>> '{inquiries,conversion_rate}') is null
    or (v #>> '{inquiries,conversion_rate}')::numeric between 0 and 1 from m where k = 'after'),
  'conversion rate is a fraction or null');

select * from finish();
rollback;
