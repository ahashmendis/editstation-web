-- Phase 12C: client_milestones and app_settings schema, RLS (admin only: editors A and B, the
-- pending applicant, a suspended editor and anon read nothing), the guard trigger (verification
-- rules, frozen money, refunds as negative rows) and the business-timezone helpers.
begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Runs p_sql as the table owner and returns 'ok' or the SQLSTATE, rolling the statement back.
create function pg_temp.state(p_sql text)
returns text language plpgsql as $$
begin
  begin
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    return case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
end;
$$;

create function pg_temp.visible(p_uid uuid, p_aal text, p_table text)
returns int language plpgsql as $$
declare
  n int;
begin
  perform pg_temp.as_user(p_uid, p_aal);
  execute format('select count(*) from public.%I', p_table) into n;
  reset role;
  return n;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('99000000-0000-0000-0000-00000000000a', 'p12c-admin@test.local', '{}', '{}'),
  ('99000000-0000-0000-0000-000000000001', 'p12c-editor-a@test.local', '{}', '{}'),
  ('99000000-0000-0000-0000-000000000002', 'p12c-editor-b@test.local', '{}', '{}'),
  ('99000000-0000-0000-0000-000000000003', 'p12c-applicant@test.local', '{}', '{}'),
  ('99000000-0000-0000-0000-000000000004', 'p12c-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p12c-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('99000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000002');
update public.editor_profiles set access_status = 'suspended' where user_id = '99000000-0000-0000-0000-000000000004';

insert into public.projects (id, title, brief_type, status, first_opened_at) values
  ('99000000-0000-0000-0000-0000000000f1', 'Billing P', 'fully_instructed', 'assigned', now());
update public.project_terms set status = 'agreed', agreed_at = now()
where project_id = '99000000-0000-0000-0000-0000000000f1';
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at) values
  ('99000000-0000-0000-0000-0000000000f1', '99000000-0000-0000-0000-000000000001', 'confirmed', 1000, 1000, 'LKR', now());
insert into public.client_milestones (id, project_id, terms_id, seq, kind, share_percent, amount, currency)
select v.id, '99000000-0000-0000-0000-0000000000f1', t.id, v.seq, v.kind::public.client_milestone_kind, 50, 5000, 'LKR'
from public.project_terms t,
  (values ('99000000-0000-0000-0000-0000000000d1'::uuid, 1, 'deposit'),
          ('99000000-0000-0000-0000-0000000000d2'::uuid, 2, 'balance')) v(id, seq, kind)
where t.project_id = '99000000-0000-0000-0000-0000000000f1';

-- ---------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------
select ok((select bool_and(relrowsecurity) from pg_class
           where oid in ('public.client_milestones'::regclass, 'public.app_settings'::regclass)),
  'RLS is on for client_milestones and app_settings');
select ok(not has_table_privilege('anon', 'public.client_milestones', 'select')
  and not has_table_privilege('anon', 'public.app_settings', 'select'), 'anon has no table access');
select ok(not (has_table_privilege('authenticated', 'public.client_milestones', 'insert')
  or has_table_privilege('authenticated', 'public.client_milestones', 'update')
  or has_table_privilege('authenticated', 'public.client_milestones', 'delete')
  or has_table_privilege('authenticated', 'public.app_settings', 'insert')
  or has_table_privilege('authenticated', 'public.app_settings', 'update')
  or has_table_privilege('authenticated', 'public.app_settings', 'delete')), 'no API role can write either table');
select is(pg_temp.visible('99000000-0000-0000-0000-00000000000a', 'aal2', 'client_milestones'), 2,
  'an MFA admin reads the client milestones');
select is(pg_temp.visible('99000000-0000-0000-0000-00000000000a', 'aal1', 'client_milestones'), 0,
  'an admin without MFA reads none');
select is(pg_temp.visible('99000000-0000-0000-0000-000000000001', 'aal1', 'client_milestones'), 0,
  'editor A (confirmed on the project) cannot read the client milestones');
select is(pg_temp.visible('99000000-0000-0000-0000-000000000002', 'aal1', 'client_milestones'), 0,
  'editor B reads none');
select is(pg_temp.visible('99000000-0000-0000-0000-000000000003', 'aal1', 'client_milestones'), 0,
  'the pending applicant reads none');
select is(pg_temp.visible('99000000-0000-0000-0000-000000000004', 'aal1', 'client_milestones'), 0,
  'the suspended editor reads none');
select is(pg_temp.visible('99000000-0000-0000-0000-00000000000a', 'aal2', 'app_settings'), 1,
  'the admin reads the settings');
select is(pg_temp.visible('99000000-0000-0000-0000-000000000001', 'aal1', 'app_settings'), 0,
  'an editor reads no settings');

-- ---------------------------------------------------------------------------
-- Business timezone (call 4)
-- ---------------------------------------------------------------------------
select is(private.business_timezone(), 'Asia/Colombo', 'the business timezone defaults to Asia/Colombo');
select is(private.business_date('2026-11-15 20:00:00+00'), '2026-11-16'::date,
  '20:00 UTC is already the next calendar day in Colombo');
update public.app_settings set value = '"Not/AZone"' where key = 'business_timezone';
select is(private.business_timezone(), 'Asia/Colombo', 'an unknown stored timezone falls back to Asia/Colombo');
update public.app_settings set value = '"Asia/Colombo"' where key = 'business_timezone';

-- ---------------------------------------------------------------------------
-- Guard: verification rules and frozen money (hold for the table owner too)
-- ---------------------------------------------------------------------------
select is(pg_temp.state($$ delete from public.client_milestones where id = '99000000-0000-0000-0000-0000000000d2' $$),
  'ES409', 'a milestone cannot be deleted');
select is(pg_temp.state($$ update public.client_milestones set amount = 1 where id = '99000000-0000-0000-0000-0000000000d1' $$),
  'ES409', 'the amount cannot change');
select is(pg_temp.state($$ update public.client_milestones set verification_status = 'verified', verified_at = now(),
  received_at = now(), transfer_reference = 'R' where id = '99000000-0000-0000-0000-0000000000d1' $$),
  'ES409', 'expected cannot jump to verified');
select is(pg_temp.state($$ insert into public.client_milestones (project_id, terms_id, seq, kind, share_percent, amount,
  currency, verification_status, received_at, transfer_reference, verified_at)
  select project_id, terms_id, 9, 'balance', 10, 1, 'LKR', 'verified', now(), 'R', now()
  from public.client_milestones where id = '99000000-0000-0000-0000-0000000000d1' $$),
  'ES409', 'a milestone cannot be inserted as verified');
select is(pg_temp.state($$ update public.client_milestones set verification_status = 'received_unverified',
  received_at = now() where id = '99000000-0000-0000-0000-0000000000d1' $$),
  '23514', 'a received payment needs a transfer reference');

update public.client_milestones set verification_status = 'received_unverified', received_at = now(),
  transfer_reference = 'REF-1' where id = '99000000-0000-0000-0000-0000000000d1';
update public.client_milestones set verification_status = 'verified', verified_at = now()
where id = '99000000-0000-0000-0000-0000000000d1';
select is(pg_temp.state($$ update public.client_milestones set verification_status = 'received_unverified',
  verified_at = null where id = '99000000-0000-0000-0000-0000000000d1' $$),
  'ES409', 'verified is final without the audited correction');
select is(pg_temp.state($$ update public.client_milestones set transfer_reference = 'OTHER'
  where id = '99000000-0000-0000-0000-0000000000d1' $$), 'ES409', 'a verified transfer reference is frozen');
select is(pg_temp.state($$ select set_config('es.client_milestone_correction', '99000000-0000-0000-0000-0000000000d2', true);
  update public.client_milestones set verification_status = 'received_unverified', verified_at = null
  where id = '99000000-0000-0000-0000-0000000000d1' $$), 'ES409', 'the correction flag must name this row');

-- ---------------------------------------------------------------------------
-- Refunds: negative rows reversing a received payment of the same project and currency
-- ---------------------------------------------------------------------------
create function pg_temp.refund(p_amount numeric, p_reverses uuid, p_currency text default 'LKR')
returns text language sql as $$
  select pg_temp.state(format($q$ insert into public.client_milestones (project_id, terms_id, seq, kind, amount, currency,
    reverses_id) select project_id, terms_id, (select max(seq) + 1 from public.client_milestones), 'refund', %s, %L, %L
    from public.client_milestones where id = '99000000-0000-0000-0000-0000000000d1' $q$, p_amount, p_currency, p_reverses));
$$;
select is(pg_temp.refund(500, '99000000-0000-0000-0000-0000000000d1'), '23514', 'a refund must be negative');
select is(pg_temp.refund(-500, '99000000-0000-0000-0000-0000000000d2'), 'ES409',
  'a refund cannot reverse a payment that was never received');
select is(pg_temp.refund(-500, '99000000-0000-0000-0000-0000000000d1', 'USD'), 'ES409',
  'a refund is in the currency of the payment');
select is(pg_temp.refund(-5000.01, '99000000-0000-0000-0000-0000000000d1'), 'ES409',
  'a refund cannot exceed the payment');
insert into public.client_milestones (id, project_id, terms_id, seq, kind, amount, currency, reverses_id)
select '99000000-0000-0000-0000-0000000000e1', project_id, terms_id, 3, 'refund', -3000, 'LKR', id
from public.client_milestones where id = '99000000-0000-0000-0000-0000000000d1';
select is((select amount from public.client_milestones where id = '99000000-0000-0000-0000-0000000000e1'), -3000.00::numeric,
  'a partial refund is stored as a negative row');
select is(pg_temp.refund(-2000.01, '99000000-0000-0000-0000-0000000000d1'), 'ES409',
  'refunds together cannot exceed the payment');
select is(pg_temp.refund(-2000, '99000000-0000-0000-0000-0000000000d1'), 'ok', 'the remainder can still be refunded');
select is(pg_temp.refund(-1, '99000000-0000-0000-0000-0000000000e1'), 'ES409', 'a refund cannot be refunded');
select is(pg_temp.state($$ insert into public.client_milestones (project_id, terms_id, seq, kind, share_percent, amount,
  currency, reverses_id) select project_id, terms_id, 9, 'balance', 10, 1, 'LKR', id
  from public.client_milestones where id = '99000000-0000-0000-0000-0000000000d1' $$),
  '23514', 'only a refund reverses another row');

-- ---------------------------------------------------------------------------
-- Voided rows are frozen; only uninvoiced, unpaid rows can be voided
-- ---------------------------------------------------------------------------
select is(pg_temp.state($$ update public.client_milestones set voided_at = now()
  where id = '99000000-0000-0000-0000-0000000000d1' $$), '23514', 'a received payment cannot be voided');
update public.client_milestones set voided_at = now() where id = '99000000-0000-0000-0000-0000000000d2';
select is(pg_temp.state($$ update public.client_milestones set invoice_issued_at = now(), due_date = current_date
  where id = '99000000-0000-0000-0000-0000000000d2' $$), 'ES409', 'a voided milestone is frozen');

select * from finish();
rollback;
