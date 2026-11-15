-- Phase 10 (2/2): admin dashboard metrics (KB §14), computed live from stored data only.
-- Not computable yet: gross contribution, admin time per project, editor abandonment.

create function public.admin_dashboard_metrics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_inquiries jsonb;
  v_applications jsonb;
  v_editors jsonb;
  v_projects jsonb;
  v_assignments jsonb;
  v_delivery jsonb;
  v_revisions jsonb;
  v_payments jsonb;
begin
  select jsonb_build_object(
      'by_status', coalesce(jsonb_object_agg(status, n), '{}'),
      'total', coalesce(sum(n), 0),
      'conversion_rate', round(
        coalesce(sum(n) filter (where status = 'converted'), 0)::numeric
        / nullif(coalesce(sum(n) filter (where status <> 'spam'), 0), 0), 3))
  into v_inquiries
  from (select status::text as status, count(*) as n from public.client_inquiries group by 1) s;

  select jsonb_build_object('by_status', coalesce(jsonb_object_agg(status, n), '{}'), 'total', coalesce(sum(n), 0))
  into v_applications
  from (select status::text as status, count(*) as n from public.editor_applications group by 1) s;

  select jsonb_build_object(
      'active', count(*) filter (where access_status = 'active'),
      'suspended', count(*) filter (where access_status = 'suspended'))
  into v_editors
  from public.editor_profiles;

  select jsonb_build_object('by_status', coalesce(jsonb_object_agg(status, n), '{}'), 'total', coalesce(sum(n), 0))
  into v_projects
  from (select status::text as status, count(*) as n from public.projects where archived_at is null group by 1) s;

  select jsonb_build_object(
      'offers', (select count(*) from public.assignments),
      'acceptance_rate', round(
        (select count(*) filter (where agreed_amount is not null)::numeric
           / nullif(count(*) filter (where agreed_amount is not null or status = 'declined'), 0)
         from public.assignments), 3),
      'counteroffer_rate', round(
        (select count(*) filter (where exists (
             select 1 from public.negotiation_offers o
             where o.assignment_id = a.id and o.from_role = 'editor' and o.action = 'counter'))::numeric
           / nullif(count(*), 0)
         from public.assignments a), 3),
      'median_hours_to_assignment', (
        select round((percentile_cont(0.5) within group (order by hours))::numeric, 1)
        from (select extract(epoch from (min(a.confirmed_at) - p.created_at)) / 3600 as hours
              from public.assignments a join public.projects p on p.id = a.project_id
              where a.confirmed_at is not null group by p.id, p.created_at) t))
  into v_assignments;

  select jsonb_build_object(
      'submissions', (select count(*) from public.submissions),
      'on_time_rate', round((select avg((not is_late)::int) from public.submissions), 3),
      'first_submission_approval_rate', round(
        (select avg((outcome = 'approved')::int) from public.submissions where version = 1 and outcome is not null), 3),
      'median_hours_to_first_submission', (
        select round((percentile_cont(0.5) within group (order by hours))::numeric, 1)
        from (select extract(epoch from (min(s.submitted_at) - a.confirmed_at)) / 3600 as hours
              from public.submissions s join public.assignments a on a.id = s.assignment_id
              where a.confirmed_at is not null group by a.id, a.confirmed_at) t))
  into v_delivery;

  select jsonb_build_object(
      'average_client_rounds', (
        select round(avg(rounds), 2)
        from (select p.project_id, count(r.id) filter (where r.type = 'client_revision') as rounds
              from (select distinct project_id from public.submissions) p
              left join public.revision_requests r on r.project_id = p.project_id
              group by p.project_id) t),
      'editor_corrections', (select count(*) from public.revision_requests where type = 'editor_correction'),
      'scope_changes', (select count(*) from public.revision_requests where type = 'scope_change'))
  into v_revisions;

  select coalesce(jsonb_agg(jsonb_build_object(
      'currency', currency,
      'not_due', not_due, 'outstanding', outstanding, 'paid', paid,
      'outstanding_count', outstanding_count) order by currency), '[]')
  into v_payments
  from (
    select currency,
      coalesce(sum(amount) filter (where kind = 'assignment' and status = 'not_due'), 0) as not_due,
      coalesce(sum(amount) filter (where kind = 'assignment'
        and status in ('pending_approval', 'approved', 'processing', 'on_hold')), 0) as outstanding,
      count(*) filter (where kind = 'assignment'
        and status in ('pending_approval', 'approved', 'processing', 'on_hold')) as outstanding_count,
      -- Net of reversals (reversal rows carry negative amounts).
      coalesce(sum(amount) filter (where status = 'paid' or kind = 'reversal'), 0) as paid
    from public.payments group by currency) t;

  return jsonb_build_object(
    'inquiries', v_inquiries, 'applications', v_applications, 'editors', v_editors,
    'projects', v_projects, 'assignments', v_assignments, 'delivery', v_delivery,
    'revisions', v_revisions, 'payments', v_payments, 'generated_at', now());
end;
$$;

revoke all on function public.admin_dashboard_metrics() from public, anon, authenticated;
grant execute on function public.admin_dashboard_metrics() to anon, authenticated;
