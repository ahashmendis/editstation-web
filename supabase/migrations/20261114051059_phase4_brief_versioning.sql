-- Phase 4 (4/6): admin_save_brief with immutable versioning. Spec §8, §14.
-- Before the first opening (projects.first_opened_at is null) version 1 is edited in place.
-- From the first opening on, any content change creates version n+1 with a full snapshot and a
-- required change summary; no version is ever overwritten (brief_versions_guard trigger).
-- Input keys: brief{...}, deliverables[], references[], change_summary, requires_reacknowledgement.
-- A key that is absent keeps the current value; a key given as null or [] replaces it.

create function public.admin_save_brief(p_project_id uuid, p_input jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := private.require_admin();
  v_project public.projects%rowtype;
  v_current public.brief_versions%rowtype;
  v_brief jsonb;
  v_deliverables jsonb;
  v_references jsonb;
  v_summary text;
  v_reack boolean;
  v_before jsonb;
  v_after jsonb;
  v_rows_changed boolean;
  v_text_changed boolean;
  v_deliverables_changed boolean;
  v_next int;
begin
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'The brief details are not valid.' using errcode = 'ES422';
  end if;

  select * into v_project from public.projects where id = p_project_id for update;
  if v_project.id is null then
    raise exception 'Project not found.' using errcode = 'ES422';
  end if;
  if v_project.status = 'cancelled' or v_project.archived_at is not null then
    raise exception 'This project is cancelled or archived and cannot be edited.' using errcode = 'ES409';
  end if;

  select * into v_current from public.brief_versions
  where project_id = p_project_id and version = v_project.current_brief_version;
  v_before := private.brief_snapshot(p_project_id);

  if p_input ? 'brief' then
    v_brief := private.parse_brief(p_input -> 'brief');
  else
    v_brief := jsonb_build_object(
      'instructions', v_current.instructions, 'desired_outcome', v_current.desired_outcome,
      'audience', v_current.audience, 'core_message', v_current.core_message,
      'brand_constraints', v_current.brand_constraints, 'mandatory_content', v_current.mandatory_content,
      'prohibited_content', v_current.prohibited_content);
  end if;
  v_deliverables := case when p_input ? 'deliverables'
    then private.parse_deliverables(p_input -> 'deliverables') else v_before -> 'deliverables' end;
  v_references := case when p_input ? 'references'
    then private.parse_references(p_input -> 'references') else v_before -> 'references' end;
  v_summary := private.jsonb_text(p_input, 'change_summary', 'change summary');
  v_reack := private.jsonb_bool(p_input, 'requires_reacknowledgement', 'needs re-confirmation');

  begin
    v_rows_changed := private.sync_brief_rows(p_project_id, v_deliverables, v_references);
    v_after := private.brief_snapshot(p_project_id);

    v_text_changed :=
      (v_current.instructions, v_current.desired_outcome, v_current.audience, v_current.core_message,
       v_current.brand_constraints, v_current.mandatory_content, v_current.prohibited_content)
      is distinct from
      (v_brief ->> 'instructions', v_brief ->> 'desired_outcome', v_brief ->> 'audience',
       v_brief ->> 'core_message', v_brief ->> 'brand_constraints', v_brief ->> 'mandatory_content',
       v_brief ->> 'prohibited_content');

    -- Deliverables compared as a set of items without sort_order (reordering is not a change).
    v_deliverables_changed :=
      (select coalesce(jsonb_agg(e - 'sort_order' order by e ->> 'id'), '[]'::jsonb)
       from jsonb_array_elements(v_before -> 'deliverables') e)
      is distinct from
      (select coalesce(jsonb_agg(e - 'sort_order' order by e ->> 'id'), '[]'::jsonb)
       from jsonb_array_elements(v_after -> 'deliverables') e);

    if v_project.first_opened_at is null then
      -- Never opened: no editor can have seen it, so version 1 is rewritten in place.
      update public.brief_versions
      set instructions = v_brief ->> 'instructions',
          desired_outcome = v_brief ->> 'desired_outcome',
          audience = v_brief ->> 'audience',
          core_message = v_brief ->> 'core_message',
          brand_constraints = v_brief ->> 'brand_constraints',
          mandatory_content = v_brief ->> 'mandatory_content',
          prohibited_content = v_brief ->> 'prohibited_content',
          deliverables = v_after -> 'deliverables',
          "references" = v_after -> 'references'
      where id = v_current.id
        and (v_text_changed or deliverables is distinct from v_after -> 'deliverables'
             or "references" is distinct from v_after -> 'references');
      return v_project.current_brief_version;
    end if;

    if not (v_rows_changed or v_text_changed) then
      return v_project.current_brief_version;
    end if;

    if v_summary is null then
      raise exception 'Please describe what changed in this brief version.' using errcode = 'ES422';
    end if;

    v_next := v_project.current_brief_version + 1;
    insert into public.brief_versions (project_id, version, change_summary, created_by, instructions,
      desired_outcome, audience, core_message, brand_constraints, mandatory_content,
      prohibited_content, requires_reacknowledgement, deliverables, "references")
    values (
      p_project_id, v_next, v_summary, v_admin,
      v_brief ->> 'instructions', v_brief ->> 'desired_outcome', v_brief ->> 'audience',
      v_brief ->> 'core_message', v_brief ->> 'brand_constraints', v_brief ->> 'mandatory_content',
      v_brief ->> 'prohibited_content',
      case when v_deliverables_changed then true else coalesce(v_reack, true) end,
      v_after -> 'deliverables', v_after -> 'references');

    update public.projects set current_brief_version = v_next where id = p_project_id;
  exception
    when check_violation then
      raise exception 'Please check your entries: some values are invalid or too long.'
        using errcode = 'ES422';
  end;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'project.brief_version', 'project', p_project_id::text,
          jsonb_build_object('project_id', p_project_id, 'version', v_next));

  return v_next;
end;
$$;

revoke all on function public.admin_save_brief(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_save_brief(uuid, jsonb) to anon, authenticated;
