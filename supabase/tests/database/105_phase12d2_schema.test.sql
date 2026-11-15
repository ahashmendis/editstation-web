-- Phase 12D part 2: catalogue (enums, tables, columns, RLS, grants) and row visibility of the
-- admin-only tables as admin, admin without MFA, editor A, editor B, pending applicant and anon.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pg_temp.as_user(uuid, text) to authenticated;
create function pg_temp.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

select enum_has_labels('public', 'adjustment_kind', array['extra_round', 'scope_change', 'cancellation'],
  'adjustment kinds');
select enum_has_labels('public', 'adjustment_status', array['offered', 'accepted', 'declined', 'withdrawn'],
  'adjustment statuses');
select enum_has_labels('public', 'scope_quote_status', array['drafted', 'sent', 'accepted', 'declined'],
  'scope quote statuses');
select ok('cancelled' = any (enum_range(null::public.payment_status)::text[]), 'payment_status has cancelled');
select ok(array['adjustment_offered', 'adjustment_answered'] <@ enum_range(null::public.notification_kind)::text[],
  'the two new notification kinds exist');

select columns_are('public', 'compensation_adjustments', array['id', 'assignment_id', 'project_id', 'editor_id', 'kind',
  'amount', 'currency', 'revision_request_id', 'scope_quote_id', 'status', 'note', 'offered_by', 'offered_at',
  'answered_by', 'answered_at', 'withdrawn_by', 'withdrawn_at', 'created_at', 'updated_at'],
  'compensation_adjustments columns (editor pay only, no client money)');
select columns_are('public', 'scope_change_quotes', array['id', 'project_id', 'revision_request_id', 'description',
  'amount', 'currency', 'status', 'sent_at', 'answered_at', 'answered_by', 'created_by', 'created_at', 'updated_at'],
  'scope_change_quotes columns');
select has_column('public', 'cancellation_settlements', 'client_refund', 'settlements record the client refund');
select has_column('public', 'client_milestones', 'settlement_id', 'refund rows link their settlement');
select has_column('public', 'revision_requests', 'adjustment_required', 'revision_requests.adjustment_required');

select is_empty($$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('compensation_adjustments', 'scope_change_quotes', 'cancellation_settlements')
    and not c.relrowsecurity $$, 'RLS is on for the three new tables');
select is_empty($$ select table_name || ' ' || privilege_type from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon', 'authenticated')
    and table_name in ('compensation_adjustments', 'scope_change_quotes', 'cancellation_settlements')
    and privilege_type <> 'SELECT' $$, 'no write grants for any API role');
select is_empty($$ select table_name from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'anon'
    and table_name in ('compensation_adjustments', 'scope_change_quotes', 'cancellation_settlements') $$,
  'anon has no grant at all');

-- Seed one row per table (table owner) and read as each role.
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('d7000000-0000-0000-0000-00000000000a', 'p12d2c-admin@test.local', '{}', '{}'),
  ('d7000000-0000-0000-0000-000000000001', 'p12d2c-editor-a@test.local', '{}', '{}'),
  ('d7000000-0000-0000-0000-000000000002', 'p12d2c-editor-b@test.local', '{}', '{}'),
  ('d7000000-0000-0000-0000-000000000003', 'p12d2c-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p12d2c-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('d7000000-0000-0000-0000-000000000001', 'd7000000-0000-0000-0000-000000000002');
insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('d7000000-0000-0000-0000-0000000000f1', 'Catalogue', 'fully_instructed', 'in_progress', now());
update public.project_terms set status = 'agreed', agreed_at = now()
where project_id = 'd7000000-0000-0000-0000-0000000000f1';
insert into public.assignments (id, project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('d7000000-0000-0000-0000-0000000000b1', 'd7000000-0000-0000-0000-0000000000f1',
   'd7000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.compensation_adjustments (assignment_id, project_id, editor_id, kind, amount, currency)
values ('d7000000-0000-0000-0000-0000000000b1', 'd7000000-0000-0000-0000-0000000000f1',
        'd7000000-0000-0000-0000-000000000001', 'cancellation', 10, 'LKR');

create function pg_temp.visible(p_uid uuid, p_aal text) returns text language plpgsql as $$
declare
  v text;
begin
  if p_uid is null then perform pg_temp.as_anon(); else perform pg_temp.as_user(p_uid, p_aal); end if;
  begin
    select (select count(*) from public.compensation_adjustments)::text || ','
      || (select count(*) from public.scope_change_quotes)::text || ','
      || (select count(*) from public.cancellation_settlements)::text into v;
  exception when insufficient_privilege then
    v := 'denied';
  end;
  reset role;
  return v;
end;
$$;
select is(pg_temp.visible('d7000000-0000-0000-0000-00000000000a', 'aal2'), '1,0,0', 'an MFA admin reads the offers');
select is(pg_temp.visible('d7000000-0000-0000-0000-00000000000a', 'aal1'), '0,0,0', 'an admin without MFA reads nothing');
select is(pg_temp.visible('d7000000-0000-0000-0000-000000000001', 'aal1'), '0,0,0',
  'editor A reads no rows directly (own offers come through editor_list_adjustments)');
select is(pg_temp.visible('d7000000-0000-0000-0000-000000000002', 'aal1'), '0,0,0', 'editor B reads nothing');
select is(pg_temp.visible('d7000000-0000-0000-0000-000000000003', 'aal1'), '0,0,0', 'a pending applicant reads nothing');
select is(pg_temp.visible(null, null), 'denied', 'anon is refused');

select throws_ok($$ update public.compensation_adjustments set status = 'accepted' $$, '23514', null,
  'accepted needs answered_at (status check)');
select throws_ok($$ insert into public.compensation_adjustments (assignment_id, project_id, editor_id, kind, amount,
    currency, revision_request_id) values ('d7000000-0000-0000-0000-0000000000b1', 'd7000000-0000-0000-0000-0000000000f1',
    'd7000000-0000-0000-0000-000000000001', 'scope_change', 10, 'LKR', null) $$, '23514', null,
  'a scope change offer must name its quote');
select throws_ok($$ insert into public.payments (assignment_id, project_id, editor_id, milestone_seq, amount, currency)
  values ('d7000000-0000-0000-0000-0000000000b1', 'd7000000-0000-0000-0000-0000000000f1',
          'd7000000-0000-0000-0000-000000000001', null, 10, 'LKR') $$, '23514', null,
  'a payment without a milestone must be an extra pay or settlement line');

select * from finish();
rollback;
