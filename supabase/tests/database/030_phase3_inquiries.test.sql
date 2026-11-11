-- Phase 3: public client inquiries. Decisions N, O, U, V, H, KB3 (placeholder list).
-- Anonymous visitors can submit but read nothing; only MFA admins manage inquiries.
begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

create function pg_temp.as_user(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.as_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('30000000-0000-0000-0000-00000000000a', 'p3-admin@test.local', '{}', '{}'),
  ('30000000-0000-0000-0000-000000000003', 'p3-applicant@test.local', '{}', '{}');
select private.grant_admin_by_email('p3-admin@test.local', 'test');

-- An inactive option and a budget range, created as postgres.
insert into public.service_types (code, label, active) values ('retired', 'Retired service', false);
insert into public.budget_ranges (id, label, min_amount, max_amount)
values ('30000000-0000-0000-0000-0000000000b1', 'Test range', 1000, 2000);
insert into public.budget_ranges (id, label, active)
values ('30000000-0000-0000-0000-0000000000b2', 'Hidden range', false);

-- ---------------------------------------------------------------------------
-- Anonymous visitor
-- ---------------------------------------------------------------------------
select pg_temp.as_anon();

select is((select count(*)::int from public.service_types), 5, 'anon sees the 5 active service types');
select ok(not exists (select 1 from public.service_types where code = 'retired'), 'inactive service types are hidden');
select is((select count(*)::int from public.budget_ranges), 1, 'anon sees only active budget ranges');
select throws_ok($$ select 1 from public.client_inquiries $$, '42501', null, 'anon cannot read inquiries');
select throws_ok($$ select 1 from public.inquiry_notes $$, '42501', null, 'anon cannot read inquiry notes');

select lives_ok($$
  select public.submit_client_inquiry('Asha Perera', 'Lanka Agency', 'Asha@Example.com', '+94 77',
    'short_form_social', 'Ten reels for a product launch.', '10 x 30s reels',
    '30000000-0000-0000-0000-0000000000b1', '2026-12-31', 'Brand kit available',
    '[{"url":"https://example.com/ref","label":"Reference"}]'::jsonb, 'placeholder-2026-11-11')
$$, 'anon can submit an inquiry');

select lives_ok($$
  select public.submit_client_inquiry('Ravi', null, 'ravi@example.com', null, 'not_sure',
    'Not sure what we need yet.', null, null, null, null, null, 'placeholder-2026-11-11')
$$, 'a minimal inquiry with "prefer to discuss" budget is accepted');

select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'short_form_social',
    '', null, null, null, null, null, 'placeholder-2026-11-11')
$$, 'ES422', null, 'description is required');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'retired',
    'desc', null, null, null, null, null, 'placeholder-2026-11-11')
$$, 'ES422', null, 'inactive service types are rejected');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'long_form',
    'desc', null, '30000000-0000-0000-0000-0000000000b2', null, null, null, 'placeholder-2026-11-11')
$$, 'ES422', null, 'inactive budget ranges are rejected');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'long_form',
    'desc', null, null, null, null, '[{"url":"http://insecure.example"}]'::jsonb, 'placeholder-2026-11-11')
$$, 'ES422', null, 'reference links must be https');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'long_form', 'desc', null, null,
    null, null, (select jsonb_agg(jsonb_build_object('url', 'https://e.com/' || g)) from generate_series(1, 11) g),
    'placeholder-2026-11-11')
$$, 'ES422', null, 'at most 10 reference links');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'x@example.com', null, 'long_form',
    'desc', null, null, null, null, null, '')
$$, 'ES422', null, 'privacy notice acknowledgement is required');
select throws_ok($$
  select public.submit_client_inquiry('X', null, 'not-an-email', null, 'long_form',
    'desc', null, null, null, null, null, 'placeholder-2026-11-11')
$$, 'ES422', null, 'invalid email is rejected');

-- Per-email limit: 3 per hour (Asha already has 1).
select public.submit_client_inquiry('Asha', null, 'asha@example.com', null, 'long_form', 'second', null, null, null, null, null, 'v');
select public.submit_client_inquiry('Asha', null, 'ASHA@example.com', null, 'long_form', 'third', null, null, null, null, null, 'v');
select throws_ok($$
  select public.submit_client_inquiry('Asha', null, 'asha@example.com', null, 'long_form',
    'fourth', null, null, null, null, null, 'v')
$$, 'ES429', null, 'more than 3 inquiries per email per hour are refused');

-- Per-source limit: 5 per hour for one hashed IP, even with different emails.
select public.submit_client_inquiry('S' || g, null, 's' || g || '@example.com', null, 'long_form', 'desc',
  null, null, null, null, null, 'v', repeat('a', 64))
from generate_series(1, 5) g;
select throws_ok($$
  select public.submit_client_inquiry('S6', null, 's6@example.com', null, 'long_form', 'desc',
    null, null, null, null, null, 'v', repeat('a', 64))
$$, 'ES429', null, 'more than 5 inquiries per source per hour are refused');
select throws_ok($$
  select public.submit_client_inquiry('S7', null, 's7@example.com', null, 'long_form', 'desc',
    null, null, null, null, null, 'v', 'not-a-hash')
$$, 'ES422', null, 'a malformed source key is rejected');
select throws_ok($$ select 1 from private.inquiry_throttle $$, '42501', null,
  'the throttle table is not reachable by anon');

select throws_ok($$ select public.admin_set_inquiry_status(gen_random_uuid(), 'reviewing') $$,
  'ES401', null, 'anon cannot change inquiry status');

reset role;

select is((select count(*)::int from public.client_inquiries), 9, 'nine inquiries were stored');
select is(
  (select email from public.client_inquiries where contact_name = 'Asha Perera'), 'asha@example.com',
  'email is stored normalised');
select is(
  (select budget_label from public.client_inquiries where contact_name = 'Ravi'), 'Prefer to discuss',
  'no range selected means "Prefer to discuss"');
select is(
  (select count(*)::int from public.client_inquiry_links), 1, 'reference links are stored');

-- ---------------------------------------------------------------------------
-- Signed-in non-admin
-- ---------------------------------------------------------------------------
select pg_temp.as_user('30000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.client_inquiries), 0, 'an applicant sees no inquiries');
select throws_ok($$
  insert into public.inquiry_notes (inquiry_id, author_id, note)
  values ((select id from public.client_inquiries limit 1), '30000000-0000-0000-0000-000000000003', 'x')
$$, '42501', null, 'an applicant cannot add inquiry notes');
select throws_ok($$
  insert into public.service_types (code, label) values ('sneaky', 'Sneaky')
$$, '42501', null, 'an applicant cannot add service types');
select throws_ok($$ select public.admin_set_inquiry_status(gen_random_uuid(), 'reviewing') $$,
  'ES403', null, 'an applicant cannot change inquiry status');
reset role;

-- A stale token for a deleted account must not block a public submission.
select pg_temp.as_user('30000000-0000-0000-0000-0000000000ff');
select lives_ok($$
  select public.submit_client_inquiry('Stale', null, 'stale@example.com', null, 'long_form',
    'desc', null, null, null, null, null, 'v')
$$, 'a submission with a token for a non-existent account still succeeds');
reset role;

-- Admin without MFA.
select pg_temp.as_user('30000000-0000-0000-0000-00000000000a', 'aal1');
select is((select count(*)::int from public.client_inquiries), 0, 'admin without MFA sees no inquiries');
reset role;

-- ---------------------------------------------------------------------------
-- Admin with MFA
-- ---------------------------------------------------------------------------
create temp table inq as select id from public.client_inquiries where contact_name = 'Asha Perera';
grant select on inq to authenticated;

select pg_temp.as_user('30000000-0000-0000-0000-00000000000a', 'aal2');
select is((select count(*)::int from public.client_inquiries), 10, 'admin with MFA sees all inquiries');
select lives_ok($$ select public.admin_set_inquiry_status((select id from inq), 'reviewing', 'Looks promising') $$,
  'admin moves an inquiry to reviewing with a note');
select is((select count(*)::int from public.inquiry_notes where inquiry_id = (select id from inq)), 1,
  'the note is stored');
select throws_ok($$ select public.admin_set_inquiry_status((select id from inq), 'reviewing') $$,
  'ES409', null, 'setting the same status is refused');
select throws_ok($$ select public.admin_set_inquiry_status((select id from inq), 'converted') $$,
  'ES409', null, 'converted cannot be set by hand (Phase 4 conversion only)');
select lives_ok($$ select public.admin_set_inquiry_status((select id from inq), 'declined') $$,
  'admin declines an inquiry');
select lives_ok($$ select public.admin_set_inquiry_status((select id from inq), 'reviewing') $$,
  'a declined inquiry can be reopened by an admin');
select lives_ok($$
  insert into public.budget_ranges (label, min_amount, max_amount) values ('Admin range', 5000, 10000);
  update public.service_types set label = 'Renamed short-form' where code = 'short_form_social';
$$, 'admin manages budget ranges and service types');
reset role;

select is(
  (select service_type_label from public.client_inquiries where id = (select id from inq)),
  'Short-form / social video', 'renaming a service type does not change submitted inquiries');
select ok(
  (select count(*) from public.activity_logs
   where entity_type = 'client_inquiry' and action in ('inquiry.submitted', 'inquiry.reviewing', 'inquiry.declined')) >= 6,
  'inquiry submissions and status changes are audited');
select ok(
  not exists (select 1 from public.activity_logs where entity_type = 'client_inquiry' and details::text like '%@%'),
  'audit entries for inquiries contain no email addresses');

select * from finish();

rollback;
