-- Remove the PUBLIC EXECUTE grant from functions created before Phase 4 (db-security review
-- follow-up). Every role that needs a function is granted it explicitly FIRST, then PUBLIC is
-- revoked: a missing privilege raises a permission error, which crashes this Postgres image.
--
-- The four invoker functions (private.require_user, private.limit_portfolio_links,
-- private.set_updated_at, private.prevent_activity_log_changes) stay security invoker on
-- purpose: three are trigger functions and require_user only reads auth.uid(); none touches a
-- table the caller cannot already reach, so security definer would only widen their privileges.

-- ---------------------------------------------------------------------------
-- Phase 2-3 public workflow functions: executable by anon and authenticated (they authorise in
-- their bodies), not by PUBLIC.
-- ---------------------------------------------------------------------------
grant execute on function
  public.admin_approve_application(uuid, public.editor_level, text),
  public.admin_create_application_request(uuid, public.application_request_kind, text),
  public.admin_record_assessment_result(uuid, public.assessment_result, text),
  public.admin_reject_application(uuid, text),
  public.admin_reopen_application(uuid),
  public.admin_set_editor_access(uuid, public.editor_access_status, text),
  public.admin_set_inquiry_status(uuid, public.inquiry_status, text),
  public.admin_start_application_review(uuid),
  public.respond_to_application_request(uuid, text, text),
  public.save_editor_profile(text, text, text, smallint, text, text, text, text, text, text[], text[], jsonb),
  public.submit_client_inquiry(text, text, text, text, text, text, text, uuid, date, text, jsonb, text, text),
  public.submit_editor_application(text, text),
  public.withdraw_editor_application()
to anon, authenticated;

revoke execute on function
  public.admin_approve_application(uuid, public.editor_level, text),
  public.admin_create_application_request(uuid, public.application_request_kind, text),
  public.admin_record_assessment_result(uuid, public.assessment_result, text),
  public.admin_reject_application(uuid, text),
  public.admin_reopen_application(uuid),
  public.admin_set_editor_access(uuid, public.editor_access_status, text),
  public.admin_set_inquiry_status(uuid, public.inquiry_status, text),
  public.admin_start_application_review(uuid),
  public.respond_to_application_request(uuid, text, text),
  public.save_editor_profile(text, text, text, smallint, text, text, text, text, text, text[], text[], jsonb),
  public.submit_client_inquiry(text, text, text, text, text, text, text, uuid, date, text, jsonb, text, text),
  public.submit_editor_application(text, text),
  public.withdraw_editor_application()
from public;

-- ---------------------------------------------------------------------------
-- RLS helpers: exactly the roles whose policies call them.
-- private.is_admin(): authenticated policies on most tables, and the anon-visible select
--   policies on public.service_types and public.budget_ranges (`active or is_admin()`), so anon
--   needs it too. Stored policy expressions do not check schema USAGE, only function EXECUTE.
-- private.is_admin_account(), private.is_active_editor(): no anon policy calls them; their other
--   callers are security definer functions, which run as postgres.
-- ---------------------------------------------------------------------------
grant execute on function private.is_admin() to anon, authenticated;
grant execute on function private.is_admin_account(), private.is_active_editor() to authenticated;

revoke execute on function private.is_admin(), private.is_admin_account(), private.is_active_editor()
from public;

-- ---------------------------------------------------------------------------
-- Trigger functions: no role needs EXECUTE (it is checked only at CREATE TRIGGER, not when the
-- trigger fires).
-- ---------------------------------------------------------------------------
revoke execute on function private.set_updated_at(), private.prevent_activity_log_changes()
from public, anon, authenticated;
