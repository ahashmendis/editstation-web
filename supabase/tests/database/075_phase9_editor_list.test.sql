-- Phase 9: editor_list_payments. Review Focus 9.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

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

create function pg_temp.assignment(p_title text, p_editor uuid)
returns uuid language plpgsql as $$
declare
  v_project uuid;
  v_id uuid;
begin
  perform pg_temp.as_user('75000000-0000-0000-0000-00000000000a', 'aal2');
  v_project := public.admin_create_project(jsonb_build_object('title', p_title, 'brief_type', 'fully_instructed',
    'deadline', '2026-12-31', 'brief', jsonb_build_object('instructions', 'Cut it'),
    'deliverables', jsonb_build_array(jsonb_build_object('name', 'Main'))));
  perform public.admin_set_project_status(v_project, 'open');
  v_id := public.admin_make_offer(v_project, p_editor, 10000, 'LKR');
  perform pg_temp.as_user(p_editor);
  perform public.editor_respond_offer(v_id, 'accept');
  perform pg_temp.as_user('75000000-0000-0000-0000-00000000000a', 'aal2');
  perform public.admin_confirm_assignment(v_id);
  reset role;
  return v_id;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('75000000-0000-0000-0000-00000000000a', 'p9l-admin@test.local', '{}', '{}'),
  ('75000000-0000-0000-0000-000000000001', 'p9l-editor-a@test.local', '{}', '{}'),
  ('75000000-0000-0000-0000-000000000002', 'p9l-editor-b@test.local', '{}', '{}'),
  ('75000000-0000-0000-0000-000000000003', 'p9l-applicant@test.local', '{}', '{}'),
  ('75000000-0000-0000-0000-000000000004', 'p9l-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p9l-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('75000000-0000-0000-0000-000000000001', '75000000-0000-0000-0000-000000000002',
                  '75000000-0000-0000-0000-000000000004');

create temp table ids (kind text primary key, id uuid not null);
grant select on ids to authenticated;
insert into ids select 'a1', pg_temp.assignment('Alpha film', '75000000-0000-0000-0000-000000000001');
insert into ids select 'b1', pg_temp.assignment('Beta film', '75000000-0000-0000-0000-000000000002');
insert into ids select 's1', pg_temp.assignment('Sigma film', '75000000-0000-0000-0000-000000000004');
update public.editor_profiles set access_status = 'suspended' where user_id = '75000000-0000-0000-0000-000000000004';
create function pg_temp.a(p_kind text) returns uuid language sql as $$ select id from ids where kind = p_kind $$;
grant execute on function pg_temp.a(text) to authenticated;
create temp table a_project as select project_id from public.assignments where id = pg_temp.a('a1');
grant select on a_project to authenticated;
create temp table a_payments as select id from public.payments where editor_id = '75000000-0000-0000-0000-000000000001';
grant select on a_payments to authenticated;

select is(pg_get_function_result('public.editor_list_payments()'::regprocedure),
  'TABLE(id uuid, project_id uuid, project_title text, kind payment_kind, amount numeric, currency character, '
  || 'status payment_status, on_hold_reason text, reversal_reason text, reverses_payment_id uuid, due_date date, '
  || 'transfer_date date, transaction_reference text, approved_at timestamp with time zone, '
  || 'marked_paid_at timestamp with time zone, created_at timestamp with time zone)',
  'editor_list_payments returns exactly the declared columns (no actor ids)');

select pg_temp.as_user('75000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.editor_list_payments()), 1, 'A lists one payment');
select ok((select bool_and(project_title = 'Alpha film' and amount = 10000 and status = 'not_due')
  from public.editor_list_payments()), 'A sees own payment with its project title');
select set_eq($$ select id from public.editor_list_payments() $$,
  $$ select id from a_payments $$,
  'A lists exactly own payments');
select pg_temp.as_user('75000000-0000-0000-0000-000000000002');
select ok((select count(*) = 1 and bool_and(project_title = 'Beta film') from public.editor_list_payments()),
  'B lists only own payment');
select pg_temp.as_user('75000000-0000-0000-0000-000000000004');
select throws_ok($$ select * from public.editor_list_payments() $$, 'ES403', null, 'a suspended editor is refused');
select pg_temp.as_user('75000000-0000-0000-0000-000000000003');
select throws_ok($$ select * from public.editor_list_payments() $$, 'ES403', null, 'an applicant is refused');
select pg_temp.as_user('75000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select * from public.editor_list_payments() $$, 'ES403', null, 'an admin is refused');
reset role;
select pg_temp.as_anon();
select throws_ok($$ select * from public.editor_list_payments() $$, 'ES401', null, 'anon is refused');
reset role;

-- After reassignment A keeps the payment and its project title but loses the project itself.
select pg_temp.as_user('75000000-0000-0000-0000-00000000000a', 'aal2');
select public.admin_reassign(pg_temp.a('a1'));
select pg_temp.as_user('75000000-0000-0000-0000-000000000001');
select ok((select count(*) = 1 and bool_and(project_title = 'Alpha film' and status = 'on_hold'
    and on_hold_reason like 'The assignment ended%') from public.editor_list_payments()),
  'after reassignment A still lists the held payment with its title');
select is((select count(*)::int from public.projects where id = (select project_id from a_project)), 0,
  'A can no longer read the project');
select is((select count(*)::int from public.payments), 0, 'A never reads payment rows directly');

-- B never sees A's rows even when B has none of its own visible
select pg_temp.as_user('75000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.editor_list_payments()
  where id in (select id from public.payments where editor_id = '75000000-0000-0000-0000-000000000001')), 0,
  'B never lists A''s payments');
select is((select count(*)::int from public.editor_list_payments() where project_id = (select project_id from a_project)),
  0, 'B sees nothing for A''s project');

reset role;
select * from finish();
rollback;
