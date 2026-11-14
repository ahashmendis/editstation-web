-- Phase 4: client_inquiries.converted_project_id and the converted-link check.
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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('41000000-0000-0000-0000-00000000000a', 'p4l-admin@test.local', '{}', '{}');
select private.grant_admin_by_email('p4l-admin@test.local', 'test');

insert into public.client_inquiries (id, contact_name, email, service_type_code, service_type_label,
  description, budget_label, privacy_notice_version)
values ('41000000-0000-0000-0000-0000000000e1', 'Link Test', 'link@example.com', 'long_form',
  'Long-form video', 'A test inquiry.', 'Prefer to discuss', 'v');
insert into public.projects (id, title, brief_type)
values ('41000000-0000-0000-0000-0000000000f1', 'Linked project', 'creative_led');

select has_column('public', 'client_inquiries', 'converted_project_id', 'client_inquiries has converted_project_id');
select col_is_fk('public', 'client_inquiries', 'converted_project_id', 'converted_project_id references projects');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'client_inquiries'
  and indexdef like '%(converted_project_id)%'), 'converted_project_id is indexed');

select throws_ok($$ update public.client_inquiries set status = 'converted'
  where id = '41000000-0000-0000-0000-0000000000e1' $$,
  '23514', null, 'converted without a project link is refused');
select throws_ok($$ update public.client_inquiries set converted_project_id = '41000000-0000-0000-0000-0000000000f1'
  where id = '41000000-0000-0000-0000-0000000000e1' $$,
  '23514', null, 'a project link on a non-converted inquiry is refused');
select lives_ok($$ update public.client_inquiries
  set status = 'converted', converted_project_id = '41000000-0000-0000-0000-0000000000f1'
  where id = '41000000-0000-0000-0000-0000000000e1' $$,
  'converted with a project link is accepted');
reset role;

-- Reset the row for the function check.
insert into public.client_inquiries (id, contact_name, email, service_type_code, service_type_label,
  description, budget_label, privacy_notice_version)
values ('41000000-0000-0000-0000-0000000000e2', 'Link Test 2', 'link2@example.com', 'long_form',
  'Long-form video', 'Another test inquiry.', 'Prefer to discuss', 'v');

select pg_temp.as_user('41000000-0000-0000-0000-00000000000a', 'aal2');
select throws_ok($$ select public.admin_set_inquiry_status('41000000-0000-0000-0000-0000000000e2', 'converted') $$,
  'ES409', null, 'admin_set_inquiry_status still refuses converted');
reset role;

select * from finish();

rollback;
