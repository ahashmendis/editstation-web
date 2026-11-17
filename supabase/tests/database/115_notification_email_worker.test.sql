-- Notification emails (feature A): outbox columns, digest mapping, pre-launch backlog, worker
-- function security (anon, admin with and without MFA, editor A, editor B, pending applicant,
-- forged claims, service_role), claiming, retries, the claim token, the daily admin summary
-- (Asia/Colombo day of the claim), the confirmed-email rule and 14-day housekeeping.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

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

create function pg_temp.as_service()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
end;
$$;

-- p_who: 'anon'; 'service' (role and claim service_role); 'forged' (service_role claim on an
-- authenticated database role); 'claim_only' (service_role claim, no role switch: postgres);
-- or a user id (with p_aal). The call is always rolled back.
create function pg_temp.state_as(p_who text, p_aal text, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  begin
    if p_who = 'anon' then perform pg_temp.as_anon();
    elsif p_who = 'service' then perform pg_temp.as_service();
    elsif p_who = 'forged' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      perform set_config('role', 'authenticated', true);
    elsif p_who = 'claim_only' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    else perform pg_temp.as_user(p_who::uuid, p_aal); end if;
    execute p_sql;
    raise exception 'rollback' using errcode = 'EST00';
  exception when others then
    v := case when sqlstate = 'EST00' then 'ok' else sqlstate end;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;

-- Runs a worker query as the real service_role (role + claim) and keeps its effects; rows come
-- back as jsonb so the assertions run as postgres.
create function pg_temp.svc(p_sql text)
returns setof jsonb language plpgsql as $$
declare
  r jsonb;
begin
  perform pg_temp.as_service();
  for r in execute format('select to_jsonb(t) from (%s) t', p_sql) loop
    return next r;
  end loop;
  reset role;
  perform set_config('request.jwt.claims', '', true);
end;
$$;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
  ('e5000000-0000-0000-0000-00000000000a', 'mail-admin-a@test.local', now(), '{}', '{}'),
  ('e5000000-0000-0000-0000-00000000000b', 'mail-admin-b@test.local', null, '{}', '{}'),
  ('e5000000-0000-0000-0000-00000000000c', 'mail-admin-c@test.local', now(), '{}', '{}'),
  ('e5000000-0000-0000-0000-000000000001', 'mail-editor-a@test.local', now(), '{}', '{}'),
  ('e5000000-0000-0000-0000-000000000002', 'mail-editor-b@test.local', null, '{}', '{}'),
  ('e5000000-0000-0000-0000-000000000003', 'mail-applicant@test.local', now(), '{}', '{}');
select private.grant_admin_by_email('mail-admin-a@test.local', 'test');
select private.grant_admin_by_email('mail-admin-b@test.local', 'test');
select private.grant_admin_by_email('mail-admin-c@test.local', 'test');
update public.admin_users set revoked_at = now() where user_id = 'e5000000-0000-0000-0000-00000000000c';
update public.editor_profiles set access_status = 'active'
where user_id in ('e5000000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000002');

-- 1-2. Pre-launch backlog: queued rows are failed, and the migration ran it
select private.notify(array['e5000000-0000-0000-0000-000000000001'::uuid], 'invitation', 'project',
  gen_random_uuid(), 'Old invitation', 'SECRET BODY');
select private.fail_prelaunch_backlog();
select is((select count(*)::int from private.notification_outbox
  where status = 'queued' or (recipient_id = 'e5000000-0000-0000-0000-000000000001'
    and (status, last_error) is distinct from ('failed', 'pre-launch backlog'))), 0,
  'the pre-launch backlog is failed with reason "pre-launch backlog"');
select ok(exists (select 1 from supabase_migrations.schema_migrations
  where version = '20261117143615'
    and array_to_string(statements, ' ') like '%select private.fail_prelaunch_backlog()%'),
  'the worker migration fails the backlog when it is applied');

-- Start from an empty outbox (seed and setup rows) so claims see only this file's rows.
delete from private.notification_outbox;

-- 3-6. Columns
select has_column('private', 'notification_outbox', 'attempts', 'outbox has attempts');
select has_column('private', 'notification_outbox', 'last_error', 'outbox has last_error');
select has_column('private', 'notification_outbox', 'claimed_at', 'outbox has claimed_at');
select has_column('private', 'notification_outbox', 'digest', 'outbox has digest');

-- 7. Every kind is explicitly mapped
select is_empty($$ select k from unnest(enum_range(null::public.notification_kind)) k
  where private.email_is_digest(k) is null $$,
  'every notification kind is mapped to digest or individual email');

-- Queue: editor A (confirmed) x2, editor B (unconfirmed), applicant (confirmed), admins x3 kinds
select private.notify(array['e5000000-0000-0000-0000-000000000001'::uuid], 'invitation', 'project',
  gen_random_uuid(), 'Project invitation', 'SECRET BODY project "Hidden Title"');
select private.notify(array['e5000000-0000-0000-0000-000000000001'::uuid], 'payment_paid', 'payment',
  gen_random_uuid(), 'Payment marked paid', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-000000000002'::uuid], 'assignment_confirmed', 'project',
  gen_random_uuid(), 'Assignment confirmed', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-000000000003'::uuid], 'application_request',
  'editor_application', gen_random_uuid(), 'More information requested', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-00000000000a'::uuid, 'e5000000-0000-0000-0000-00000000000b'],
  'inquiry_new', 'client_inquiry', gen_random_uuid(), 'New client inquiry', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-00000000000a'::uuid, 'e5000000-0000-0000-0000-00000000000b'],
  'inquiry_new', 'client_inquiry', gen_random_uuid(), 'New client inquiry', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-00000000000a'::uuid, 'e5000000-0000-0000-0000-00000000000b'],
  'submission', 'project', gen_random_uuid(), 'Work submitted', 'SECRET BODY');

-- 8. Digest set on insert from the kind
select set_eq($$ select kind::text, digest from private.notification_outbox $$,
  $$ values ('invitation', false), ('payment_paid', false), ('assignment_confirmed', false),
            ('application_request', false), ('inquiry_new', true), ('submission', true) $$,
  'admin kinds are digest rows, editor and applicant kinds are individual');

-- 9-10. Catalogue rules
create temp table pub (sig text primary key);
insert into pub values ('public.worker_claim_emails(integer)'),
  ('public.worker_claim_admin_digest(timestamp with time zone)'),
  ('public.worker_mark_email(bigint, boolean, text, timestamp with time zone)');
select is_empty($$ select sig from pub p join pg_proc f on f.oid = p.sig::regprocedure
  where not f.prosecdef or not ('search_path=""' = any (coalesce(f.proconfig, '{}')))
     or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0)
     or not has_function_privilege('anon', f.oid, 'execute')
     or not has_function_privilege('authenticated', f.oid, 'execute')
     or not has_function_privilege('service_role', f.oid, 'execute') $$,
  'worker functions: security definer, empty search_path, anon + authenticated + service_role, no PUBLIC');
select is_empty($$ select s from unnest(array['private.email_is_digest(public.notification_kind)',
    'private.set_outbox_digest()', 'private.fail_prelaunch_backlog()', 'private.require_service_role()',
    'private.fail_exhausted_emails(timestamp with time zone)']) s
  where has_function_privilege('anon', s::regprocedure, 'execute')
     or has_function_privilege('authenticated', s::regprocedure, 'execute')
     or has_function_privilege('service_role', s::regprocedure, 'execute') $$,
  'the private email helpers are not executable by any API role');

-- 11. No API role can read or write the outbox directly (recipients included)
select ok(not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r,
    unnest(array['select', 'insert', 'update', 'delete']) p
  where has_table_privilege(r, 'private.notification_outbox', p)),
  'no API role (recipients included) has any privilege on the outbox');

-- 12. The returned columns never include a body
select is((select pg_get_function_result('public.worker_claim_emails(integer)'::regprocedure)),
  'TABLE(id bigint, email text, title text, kind notification_kind, claimed_at timestamp with time zone)',
  'worker_claim_emails returns id, email, title, kind and claimed_at only');

-- 13. ES403 for everyone except service_role
create temp table who (name text, who text, aal text);
insert into who values
  ('anon', 'anon', 'aal1'),
  ('admin_aal1', 'e5000000-0000-0000-0000-00000000000a', 'aal1'),
  ('admin_aal2', 'e5000000-0000-0000-0000-00000000000a', 'aal2'),
  ('editor_a', 'e5000000-0000-0000-0000-000000000001', 'aal1'),
  ('editor_b', 'e5000000-0000-0000-0000-000000000002', 'aal1'),
  ('applicant', 'e5000000-0000-0000-0000-000000000003', 'aal1');
create temp table calls (sql text);
insert into calls values ('select * from public.worker_claim_emails(25)'),
  ('select * from public.worker_claim_admin_digest(now())'),
  ('select public.worker_mark_email(1, true, null)');
grant select on who, calls to anon, authenticated, service_role;
select is_empty($$ select w.name || ' ' || c.sql || ' ' || pg_temp.state_as(w.who, w.aal, c.sql)
  from who w cross join calls c where pg_temp.state_as(w.who, w.aal, c.sql) <> 'ES403' $$,
  'every worker function raises ES403 for anon, admins, editors and applicants');

-- 14. The claim alone is not enough: the database role must be service_role too
select is_empty($$ select w || ' ' || c.sql from unnest(array['forged', 'claim_only']) w cross join calls c
  where pg_temp.state_as(w, 'aal1', c.sql) <> 'ES403' $$,
  'a service_role claim on another database role (authenticated or postgres) is ES403');

-- 15. service_role passes (its calls roll back inside state_as)
select set_eq($$ select pg_temp.state_as('service', 'aal1', sql) from calls where sql not like '%mark%' $$,
  $$ values ('ok') $$, 'the service_role role can claim');

-- 16. No refused call changed the outbox
select is((select count(*)::int from private.notification_outbox where claimed_at is not null or attempts > 0), 0,
  'refused and rolled-back calls claimed nothing');

-- Claim individual emails as the real service_role
create temp table c1 as
select (j ->> 'id')::bigint as id, j ->> 'email' as email, j ->> 'title' as title,
       (j ->> 'claimed_at')::timestamptz as claimed_at, j as raw
from pg_temp.svc('select * from public.worker_claim_emails(25)') j;

-- 17. Only confirmed recipients, only individual kinds, oldest first
select results_eq($$ select email, title from c1 order by id $$,
  $$ values ('mail-editor-a@test.local'::text, 'Project invitation'::text),
            ('mail-editor-a@test.local', 'Payment marked paid'),
            ('mail-applicant@test.local', 'More information requested') $$,
  'confirmed editor and applicant rows are claimed; the unconfirmed editor and admin rows are not');
-- 18
select ok(not exists (select 1 from c1 where raw::text ~* 'secret|hidden'),
  'no claimed row carries the notification body');
-- 19
select is((select count(*)::int from private.notification_outbox o join c1 using (id)
  where o.attempts = 1 and o.claimed_at = c1.claimed_at and o.status = 'queued'), 3,
  'claimed rows are leased, their attempt counted, and claimed_at returned');
-- 20. No double claim
select is_empty($$ select * from pg_temp.svc('select * from public.worker_claim_emails(25)') $$,
  'a claimed row is not claimed twice');
-- 21. Unconfirmed recipients are skipped
select is((select count(*)::int from private.notification_outbox where not digest and claimed_at is not null), 3,
  'the unconfirmed recipient row stays unclaimed');

-- 22. A report with a different claimed_at is refused (an expired lease cannot settle a newer claim)
select is(pg_temp.state_as('service', 'aal1',
  format('select public.worker_mark_email(%s, true, null, %L)', (select min(id) from c1),
    (select claimed_at - interval '1 second' from c1 order by id limit 1))), 'ES409',
  'a stale claimed_at is ES409');

-- 23. ok -> sent (with the matching claimed_at)
select count(*) from pg_temp.svc(format('select public.worker_mark_email(%s, true, null, %L)',
  (select min(id) from c1), (select claimed_at from c1 order by id limit 1)));
select is((select status || ' ' || (sent_at is not null)::text from private.notification_outbox
  where id = (select min(id) from c1)), 'sent true', 'a successful send is marked sent');
-- 24. Marking again conflicts; a missing id is unprocessable
select is(pg_temp.state_as('service', 'aal1',
  format('select public.worker_mark_email(%s, true, null)', (select min(id) from c1))), 'ES409',
  'a row that is not waiting for a result cannot be marked');
-- 25
select is(pg_temp.state_as('service', 'aal1', 'select public.worker_mark_email(-1, true, null)'), 'ES422',
  'an unknown row is ES422');

-- 26-27. Failure -> retry, and failed after the third attempt
create temp table f as select max(id) as id from c1;
select count(*) from pg_temp.svc(format('select public.worker_mark_email(%s, false, %L)',
  (select id from f), repeat('x', 500)));
select is((select status || ' ' || attempts || ' ' || char_length(last_error) || ' ' || (claimed_at is null)::text
  from private.notification_outbox where id = (select id from f)), 'queued 1 200 true',
  'a failed send returns to the queue with a short error');
select count(*) from pg_temp.svc('select * from public.worker_claim_emails(25)');
select count(*) from pg_temp.svc(format('select public.worker_mark_email(%s, false, ''provider 500'')', (select id from f)));
select count(*) from pg_temp.svc('select * from public.worker_claim_emails(25)');
select count(*) from pg_temp.svc(format('select public.worker_mark_email(%s, false, ''provider 500'')', (select id from f)));
select is((select status || ' ' || attempts from private.notification_outbox where id = (select id from f)),
  'failed 3', 'a row is failed after 3 attempts');
-- 28
select ok(not exists (select 1 from pg_temp.svc('select * from public.worker_claim_emails(25)') j
  where (j ->> 'id')::bigint = (select id from f)),
  'a failed row is never claimed again');

-- 29. A row whose worker died after its last attempt is failed once the lease ends
update private.notification_outbox set attempts = 3, claimed_at = now() - interval '1 hour'
where id = (select id from c1 order by id offset 1 limit 1);
select count(*) from pg_temp.svc('select * from public.worker_claim_emails(25)');
select is((select status from private.notification_outbox where id = (select id from c1 order by id offset 1 limit 1)),
  'failed', 'an exhausted row with an expired lease is failed');

-- Admin digest
create temp table d1 as
select (j ->> 'id')::bigint as id, j ->> 'email' as email, j -> 'counts' as counts,
       (j ->> 'total')::int as total, (j ->> 'claimed_at')::timestamptz as claimed_at
from pg_temp.svc('select * from public.worker_claim_admin_digest(now())') j;
-- 30
select results_eq($$ select email, counts, total from d1 $$,
  $$ values ('mail-admin-a@test.local'::text, '{"inquiry_new": 2, "submission": 1}'::jsonb, 3) $$,
  'one summary for the confirmed admin with per-kind counts; none for the unconfirmed or revoked admin');
-- 31
select is_empty($$ select * from pg_temp.svc('select * from public.worker_claim_admin_digest(now())') $$,
  'a summary in flight is not claimed twice');
select count(*) from pg_temp.svc(format('select public.worker_mark_email(%s, true, null, %L)',
  (select id from d1), (select claimed_at from d1)));
-- 32
select is((select count(*)::int from private.notification_outbox
  where recipient_id = 'e5000000-0000-0000-0000-00000000000a' and digest and status = 'sent'), 3,
  'marking the summary settles all its rows');

select private.notify(array['e5000000-0000-0000-0000-00000000000a'::uuid], 'counteroffer', 'project',
  gen_random_uuid(), 'Counteroffer received', 'SECRET BODY');
-- 33
select is_empty($$ select * from pg_temp.svc('select * from public.worker_claim_admin_digest(now())') $$,
  'no second summary on the same Colombo day');

-- The sent summary was claimed at 23:59 Colombo on 20 November and reported after midnight.
update private.notification_outbox
set claimed_at = '2026-11-20 23:59:00+05:30', sent_at = '2026-11-21 00:01:00+05:30'
where recipient_id = 'e5000000-0000-0000-0000-00000000000a' and digest and status = 'sent';
-- 34
select is_empty($$ select * from pg_temp.svc(
    'select * from public.worker_claim_admin_digest(''2026-11-20 18:00:00+05:30'')') $$,
  'a summary claimed at 23:59 counts for that Colombo day');
-- 35
select results_eq($$ select j ->> 'email', j -> 'counts', (j ->> 'total')::int from pg_temp.svc(
    'select * from public.worker_claim_admin_digest(''2026-11-21 08:00:00+05:30'')') j $$,
  $$ values ('mail-admin-a@test.local'::text, '{"counteroffer": 1}'::jsonb, 1) $$,
  'the next Colombo day brings the next summary even though the last one was reported after midnight');

-- 36-38. Housekeeping: rows queued over 14 days for unconfirmed or inactive recipients are failed
select private.notify(array['e5000000-0000-0000-0000-00000000000c'::uuid], 'inquiry_new', 'client_inquiry',
  gen_random_uuid(), 'New client inquiry', 'SECRET BODY');
select private.notify(array['e5000000-0000-0000-0000-000000000002'::uuid], 'invitation', 'project',
  gen_random_uuid(), 'Young invitation', 'SECRET BODY');
update private.notification_outbox o set created_at = now() - interval '15 days'
from public.notifications n
where n.id = o.notification_id and o.status = 'queued' and n.title <> 'Young invitation'
  and o.recipient_id in ('e5000000-0000-0000-0000-00000000000b', 'e5000000-0000-0000-0000-000000000002',
                         'e5000000-0000-0000-0000-00000000000c');
select count(*) from pg_temp.svc('select * from public.worker_claim_emails(25)');
select is((select count(*)::int from private.notification_outbox
  where recipient_id in ('e5000000-0000-0000-0000-00000000000b', 'e5000000-0000-0000-0000-000000000002')
    and created_at < now() - interval '14 days'
    and (status, last_error) is distinct from ('failed', 'no confirmed address')), 0,
  'old rows for unconfirmed recipients (admin and editor) fail with "no confirmed address"');
select is((select status || ' ' || last_error from private.notification_outbox
  where recipient_id = 'e5000000-0000-0000-0000-00000000000c'), 'failed recipient inactive',
  'old summary rows for a revoked admin fail with "recipient inactive"');
select is((select o.status from private.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.title = 'Young invitation'), 'queued',
  'a recent row for an unconfirmed recipient keeps waiting');

select * from finish();
rollback;
