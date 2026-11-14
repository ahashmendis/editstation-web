-- Phase 6: editor stage helper and tiered editor reads (spec §6, decision B).
-- Review Focus 11 (on-hold project stays visible) and 12 (archived project hidden, restored back).
begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

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

-- Sorted values of a one-column query run as the current role.
create function pg_temp.vis(p_sql text)
returns text[] language plpgsql as $$
declare
  v text[];
begin
  execute format('select coalesce(array_agg(x order by x collate "C"), ''{}'') from (%s) s(x)', p_sql) into v;
  return v;
end;
$$;
grant execute on function pg_temp.vis(text) to authenticated;

create function pg_temp.counts()
returns int[] language sql as $$
  select array[
    (select count(*)::int from public.projects),
    (select count(*)::int from public.project_deliverables),
    (select count(*)::int from public.project_references),
    (select count(*)::int from public.project_assets),
    (select count(*)::int from public.brief_versions),
    (select count(*)::int from public.assignments),
    (select count(*)::int from public.negotiation_offers),
    (select count(*)::int from public.project_access),
    (select count(*)::int from public.asset_access_grants),
    (select count(*)::int from public.project_notes),
    (select count(*)::int from public.project_internal),
    (select count(*)::int from public.clients)];
$$;
grant execute on function pg_temp.counts() to authenticated;

create function pg_temp.anon_denied()
returns int language plpgsql as $$
declare
  t text;
  v int := 0;
begin
  foreach t in array array['projects', 'project_deliverables', 'project_references', 'project_assets',
    'brief_versions', 'assignments', 'negotiation_offers', 'project_access', 'asset_access_grants',
    'project_notes', 'project_internal', 'clients'] loop
    begin
      execute format('select count(*) from public.%I', t);
    exception when insufficient_privilege then v := v + 1;
    end;
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.anon_denied() to anon;

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('53000000-0000-0000-0000-00000000000a', 'p6v-admin@test.local', '{}', '{}'),
  ('53000000-0000-0000-0000-000000000001', 'p6v-editor-a@test.local', '{}', '{}'),
  ('53000000-0000-0000-0000-000000000002', 'p6v-editor-b@test.local', '{}', '{}'),
  ('53000000-0000-0000-0000-000000000003', 'p6v-applicant@test.local', '{}', '{}'),
  ('53000000-0000-0000-0000-000000000004', 'p6v-suspended@test.local', '{}', '{}');
select private.grant_admin_by_email('p6v-admin@test.local', 'test');
update public.editor_profiles set access_status = 'active'
where user_id in ('53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000002',
                  '53000000-0000-0000-0000-000000000004');

create temp table k (kind text primary key, id uuid not null, status public.project_status not null,
  archived boolean not null);
insert into k values
  ('inv', '53000000-0000-0000-0000-0000000000f1', 'open', false),
  ('avail', '53000000-0000-0000-0000-0000000000f2', 'open', false),
  ('offer', '53000000-0000-0000-0000-0000000000f3', 'open', false),
  ('conf', '53000000-0000-0000-0000-0000000000f4', 'assigned', false),
  ('hold', '53000000-0000-0000-0000-0000000000f5', 'on_hold', false),
  ('cancel', '53000000-0000-0000-0000-0000000000f6', 'cancelled', false),
  ('arch', '53000000-0000-0000-0000-0000000000f7', 'assigned', true),
  ('revoked', '53000000-0000-0000-0000-0000000000f8', 'open', false),
  ('none', '53000000-0000-0000-0000-0000000000f9', 'open', false),
  ('s', '53000000-0000-0000-0000-0000000000fa', 'assigned', false);
grant select on k to authenticated;

insert into public.projects (id, title, brief_type, status, status_before_hold, first_opened_at, archived_at)
select id, kind, 'fully_instructed', status, case when status = 'on_hold' then 'open'::public.project_status end,
  now(), case when archived then now() end
from k;
insert into public.project_deliverables (project_id, name) select id, kind from k;
insert into public.brief_versions (project_id, version, instructions) select id, 1, kind || '-v1' from k;
insert into public.brief_versions (project_id, version, instructions)
select id, 2, kind || '-v2' from k where kind = 'conf';
update public.projects set current_brief_version = 2 where id = (select id from k where kind = 'conf');
insert into public.project_references (project_id, url, title, early_access)
select id, 'https://ref.example.com/' || kind || e, kind || '-' || e, e = 'early'
from k, unnest(array['early', 'late']) e;
insert into public.project_assets (project_id, label, url, early_access)
select id, kind || '-' || e, 'https://drive.example.com/' || kind || e, e = 'early'
from k, unnest(array['early', 'late']) e;
insert into public.asset_access_grants (project_id, editor_id, shared_with_email, provider)
select id, '53000000-0000-0000-0000-000000000001', 'a@drive.example.com', 'google_drive' from k;
insert into public.project_notes (project_id, note) select id, 'Note on ' || kind from k;
insert into public.clients (id, name, email) values ('53000000-0000-0000-0000-0000000000c1', 'Client', 'c@example.com');
insert into public.project_internal (project_id, client_id, client_price)
select id, '53000000-0000-0000-0000-0000000000c1', 99999 from k;

-- Access rows (A unless noted).
insert into public.project_access (project_id, editor_id, reason, revoked_at)
select k.id, x.editor::uuid, x.reason::public.project_access_reason, case when x.revoked then now() end
from (values
  ('inv', '53000000-0000-0000-0000-000000000001', 'invited', false),
  ('avail', '53000000-0000-0000-0000-000000000001', 'available', false),
  ('conf', '53000000-0000-0000-0000-000000000001', 'invited', false),
  ('conf', '53000000-0000-0000-0000-000000000002', 'invited', true),
  ('hold', '53000000-0000-0000-0000-000000000001', 'invited', false),
  ('cancel', '53000000-0000-0000-0000-000000000001', 'invited', false),
  ('revoked', '53000000-0000-0000-0000-000000000001', 'invited', true),
  ('s', '53000000-0000-0000-0000-000000000004', 'invited', false)) x(kind, editor, reason, revoked)
join k on k.kind = x.kind;

-- Assignments.
insert into public.assignments (project_id, editor_id, status, proposed_amount, agreed_amount, agreed_currency,
  confirmed_at, closed_at)
select k.id, x.editor::uuid, x.status::public.assignment_status, 5000,
  case when x.status in ('confirmed', 'not_selected') then 5000 end,
  case when x.status in ('confirmed', 'not_selected') then 'LKR' end,
  case when x.status = 'confirmed' then now() end,
  case when x.status = 'not_selected' then now() end
from (values
  ('conf', '53000000-0000-0000-0000-000000000001', 'confirmed'),
  ('conf', '53000000-0000-0000-0000-000000000002', 'not_selected'),
  ('offer', '53000000-0000-0000-0000-000000000002', 'offered'),
  ('arch', '53000000-0000-0000-0000-000000000001', 'confirmed'),
  ('s', '53000000-0000-0000-0000-000000000004', 'confirmed')) x(kind, editor, status)
join k on k.kind = x.kind;
insert into public.negotiation_offers (assignment_id, from_role, action, amount, currency)
select id, 'admin', 'offer', 5000, 'LKR' from public.assignments where project_id in (select id from k);

-- S is suspended after the rows exist.
update public.editor_profiles set access_status = 'suspended' where user_id = '53000000-0000-0000-0000-000000000004';

create temp table expected as select pg_temp.counts() as c;
create temp table a_counts (c int[]);
grant select, insert on a_counts to authenticated;
grant select on expected to authenticated;

-- ---------------------------------------------------------------------------
-- Stage function
-- ---------------------------------------------------------------------------
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select is((select array_agg(kind || '=' || private.editor_project_stage(id) order by kind collate "C") from k),
  array['arch=none', 'avail=opportunity', 'cancel=none', 'conf=assigned', 'hold=opportunity', 'inv=opportunity',
        'none=none', 'offer=none', 'revoked=none', 's=none'],
  'editor A stages: invited/available/on-hold opportunity, confirmed assigned, others none');
reset role;
select pg_temp.as_user('53000000-0000-0000-0000-000000000002');
select is((select array_agg(kind || '=' || private.editor_project_stage(id) order by kind collate "C") from k
  where kind in ('offer', 'conf', 'inv')),
  array['conf=none', 'inv=none', 'offer=opportunity'],
  'editor B stages: a live offer without access is an opportunity; not selected is none');
reset role;

-- ---------------------------------------------------------------------------
-- Editor A
-- ---------------------------------------------------------------------------
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
insert into a_counts select pg_temp.counts();
select is(pg_temp.vis('select title from public.projects'), array['avail', 'conf', 'hold', 'inv'],
  'A sees the projects they are invited to or confirmed on');
select is(pg_temp.vis('select name from public.project_deliverables'), array['avail', 'conf', 'hold', 'inv'],
  'A sees the deliverables of those projects');
select is(pg_temp.vis('select title from public.project_references'),
  array['avail-early', 'conf-early', 'conf-late', 'hold-early', 'inv-early'],
  'A sees early-access references of opportunities and every reference of the confirmed project');
select is(pg_temp.vis('select label from public.project_assets'),
  array['avail-early', 'conf-early', 'conf-late', 'hold-early', 'inv-early'],
  'A sees early-access assets of opportunities and every asset of the confirmed project');
select is(pg_temp.vis('select instructions from public.brief_versions'), array['conf-v1', 'conf-v2'],
  'A sees every brief version of the confirmed project only');
select is(pg_temp.vis('select k.kind from public.assignments a join k on k.id = a.project_id'),
  array['arch', 'conf'], 'A sees only their own assignments');
select is(pg_temp.vis('select k.kind from public.negotiation_offers n join public.assignments a on a.id = n.assignment_id
  join k on k.id = a.project_id'), array['arch', 'conf'], 'A sees only the negotiation rows of their own assignments');
select is(pg_temp.vis('select k.kind from public.project_access pa join k on k.id = pa.project_id'),
  array['avail', 'cancel', 'conf', 'hold', 'inv', 'revoked'], 'A sees only their own access rows');
select is((select count(*)::int from public.negotiation_offers), 2, 'A sees no other editor''s negotiation rows');
select is((pg_temp.counts())[9:12], array[0,0,0,0],
  'A sees no folder shares, notes, internal records or clients');
select throws_ok($$ update public.assignments set agreed_amount = 1 $$, '42501', null,
  'A cannot update assignments directly');
select throws_ok($$ insert into public.project_access (project_id, editor_id, reason)
  values ('53000000-0000-0000-0000-0000000000f9', '53000000-0000-0000-0000-000000000001', 'invited') $$,
  '42501', null, 'A cannot grant themselves access');
reset role;

-- ---------------------------------------------------------------------------
-- Editor B
-- ---------------------------------------------------------------------------
select pg_temp.as_user('53000000-0000-0000-0000-000000000002');
select is(pg_temp.vis('select title from public.projects'), array['offer'], 'B sees only the project with their offer');
select is(pg_temp.vis('select name from public.project_deliverables'), array['offer'], 'B sees only its deliverables');
select is(pg_temp.vis('select title from public.project_references'), array['offer-early'],
  'B sees only its early-access reference');
select is(pg_temp.vis('select label from public.project_assets'), array['offer-early'],
  'B sees only its early-access asset');
select is(pg_temp.vis('select instructions from public.brief_versions'), '{}'::text[], 'B sees no brief versions');
select is(pg_temp.vis('select k.kind from public.assignments a join k on k.id = a.project_id'),
  array['conf', 'offer'], 'B sees their own offer and their not-selected assignment');
select is(pg_temp.vis('select k.kind from public.negotiation_offers n join public.assignments a on a.id = n.assignment_id
  join k on k.id = a.project_id'), array['conf', 'offer'], 'B sees only the negotiation rows of their own assignments');
select is(pg_temp.vis('select k.kind from public.project_access pa join k on k.id = pa.project_id'),
  array['conf'], 'B sees only their own (revoked) access row');
select is((pg_temp.counts())[9:12], array[0,0,0,0],
  'B sees no folder shares, notes, internal records or clients');
reset role;

-- ---------------------------------------------------------------------------
-- Suspended editor, applicant, admin without MFA, anon, admin with MFA
-- ---------------------------------------------------------------------------
select pg_temp.as_user('53000000-0000-0000-0000-000000000004');
select is(pg_temp.counts(), array[0,0,0,0,0,0,0,0,0,0,0,0],
  'a suspended editor sees nothing, not even their own access, assignment or history');
select ok((select bool_and(private.editor_project_stage(id) = 'none') from k), 'every stage is none for S');
reset role;
select pg_temp.as_user('53000000-0000-0000-0000-000000000003');
select is(pg_temp.counts(), array[0,0,0,0,0,0,0,0,0,0,0,0], 'a pending applicant sees nothing');
select ok((select bool_and(private.editor_project_stage(id) = 'none') from k), 'every stage is none for an applicant');
reset role;
select pg_temp.as_user('53000000-0000-0000-0000-00000000000a', 'aal1');
select is(pg_temp.counts(), array[0,0,0,0,0,0,0,0,0,0,0,0], 'admin without MFA sees nothing');
reset role;
select pg_temp.as_anon();
select is(pg_temp.anon_denied(), 12, 'anon is refused (42501) on every table');
reset role;
select pg_temp.as_user('53000000-0000-0000-0000-00000000000a', 'aal2');
select is(pg_temp.counts(), (select c from expected), 'admin with MFA still sees every row of every table');
select ok((select c[1] = 10 and c[6] = 5 and c[8] = 8 from expected), 'the fixtures exist');
reset role;

-- ---------------------------------------------------------------------------
-- Immediate loss and recovery of access
-- ---------------------------------------------------------------------------
update public.editor_profiles set access_status = 'suspended' where user_id = '53000000-0000-0000-0000-000000000001';
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select is(pg_temp.counts(), array[0,0,0,0,0,0,0,0,0,0,0,0], 'suspending A hides everything immediately');
reset role;
update public.editor_profiles set access_status = 'active' where user_id = '53000000-0000-0000-0000-000000000001';
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select is(pg_temp.counts(), (select c from a_counts), 'reactivating A restores the same rows');
reset role;
update public.editor_profiles set access_status = 'revoked' where user_id = '53000000-0000-0000-0000-000000000001';
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select is(pg_temp.counts(), array[0,0,0,0,0,0,0,0,0,0,0,0], 'revoking A hides everything');
reset role;
update public.editor_profiles set access_status = 'active' where user_id = '53000000-0000-0000-0000-000000000001';

-- Review Focus 11 and 12.
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select ok('hold' = any (pg_temp.vis('select title from public.projects')), 'an on-hold project stays visible');
select ok(not ('arch' = any (pg_temp.vis('select title from public.projects'))),
  'an archived project is hidden even from its confirmed editor');
reset role;
update public.projects set archived_at = null where id = (select id from k where kind = 'arch');
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select is(private.editor_project_stage((select id from k where kind = 'arch')), 'assigned',
  'restoring the archived project makes it assigned again');
select ok('arch-late' = any (pg_temp.vis('select label from public.project_assets')),
  'the restored project''s full assets are visible again');
reset role;

-- Early-access toggle.
update public.project_assets set early_access = true where label = 'inv-late';
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select ok('inv-late' = any (pg_temp.vis('select label from public.project_assets')),
  'marking an asset as early access shows it to invited editors');
reset role;
update public.project_assets set early_access = false where label = 'inv-late';
select pg_temp.as_user('53000000-0000-0000-0000-000000000001');
select ok(not ('inv-late' = any (pg_temp.vis('select label from public.project_assets'))),
  'unmarking it hides it again');
reset role;

-- ---------------------------------------------------------------------------
-- Helper privileges and require_active_editor
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('authenticated', 'private.editor_project_stage(uuid)', 'execute')
      and not has_function_privilege('anon', 'private.editor_project_stage(uuid)', 'execute'),
  'editor_project_stage is executable by authenticated only');
select ok(not has_function_privilege('authenticated', 'private.require_active_editor()', 'execute')
      and not has_function_privilege('anon', 'private.require_active_editor()', 'execute'),
  'require_active_editor is executable by no API role');

create function pg_temp.rae(p_claims text)
returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims, true);
  return private.require_active_editor()::text;
exception
  when sqlstate 'ES401' then return 'ES401';
  when sqlstate 'ES403' then return 'ES403';
end;
$$;
select is(pg_temp.rae('{"role":"anon"}'), 'ES401', 'require_active_editor: signed out is ES401');
select is(pg_temp.rae('{"sub":"53000000-0000-0000-0000-000000000003","role":"authenticated"}'), 'ES403',
  'require_active_editor: an applicant is ES403');
select is(pg_temp.rae('{"sub":"53000000-0000-0000-0000-000000000004","role":"authenticated"}'), 'ES403',
  'require_active_editor: a suspended editor is ES403');
select is(pg_temp.rae('{"sub":"53000000-0000-0000-0000-00000000000a","role":"authenticated","aal":"aal2"}'), 'ES403',
  'require_active_editor: an admin is ES403');
select is(pg_temp.rae('{"sub":"53000000-0000-0000-0000-000000000001","role":"authenticated"}'),
  '53000000-0000-0000-0000-000000000001', 'require_active_editor returns an active editor''s id');

select * from finish();

rollback;
