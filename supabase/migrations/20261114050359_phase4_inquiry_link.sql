-- Phase 4 (2/6): link a converted inquiry to its project.
-- Spec §5 "Change to client_inquiries" and "Migration safety". Existing data is not assumed
-- empty: the migration refuses to run (changing nothing) if any inquiry is already marked
-- converted, because such a row could only come from direct SQL and has no project to point at.
-- Before applying to a hosted database, run the same count by hand first:
--   select count(*) from public.client_inquiries where status = 'converted';

-- 1. Column, nullable, no constraint yet.
alter table public.client_inquiries
  add column converted_project_id uuid references public.projects (id) on delete restrict;
create index client_inquiries_converted_project_idx on public.client_inquiries (converted_project_id);

-- 2. Pre-flight: abort with the count, change nothing.
do $$
declare
  n bigint;
begin
  select count(*) into n from public.client_inquiries where status = 'converted';
  if n <> 0 then
    raise exception 'Cannot add the conversion link: % inquiries are already marked converted. Review them first.', n;
  end if;
end;
$$;

-- 3. Constraint added NOT VALID then validated (short lock; fails loudly on any violating row).
alter table public.client_inquiries
  add constraint client_inquiries_converted_link_chk
  check ((status = 'converted') = (converted_project_id is not null)) not valid;
alter table public.client_inquiries validate constraint client_inquiries_converted_link_chk;
