-- ======================================================================
-- VIGIMAT : Correction d'idempotence pour apply_maintenance_report_action
-- ======================================================================

create or replace function public.apply_maintenance_report_action(
  p_action_id uuid,
  p_report_id uuid,
  p_action text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  actor_role text := public.current_vigimat_role();
  actor_unit uuid := public.current_vigimat_unit_id();
  report_row public.maintenance_reports%rowtype;
  assigned_id uuid;
  due_at timestamptz;
  next_status text;
  note text;
  receipt public.maintenance_report_action_receipts%rowtype;
begin
  if actor_id is null or p_action_id is null or p_report_id is null then
    raise exception 'Identité de l''action requise';
  end if;

  -- 1. Idempotence par action_id
  select * into receipt
  from public.maintenance_report_action_receipts
  where action_id = p_action_id;
  if found then
    if receipt.actor_id is distinct from actor_id
       or receipt.report_id is distinct from p_report_id then
      raise exception 'Identifiant d''action déjà utilisé';
    end if;
    return jsonb_build_object(
      'status', receipt.status,
      'updated_at', receipt.updated_at
    );
  end if;

  -- 2. Verrou de ligne transactionnel
  select * into report_row
  from public.maintenance_reports
  where id = p_report_id
  for update;
  if not found then
    raise exception 'Signalement introuvable';
  end if;

  if actor_unit is null or report_row.unit_id is distinct from actor_unit then
    raise exception 'Le signalement appartient à une autre unité';
  end if;

  if not (
    actor_role = 'unit_head'
    or (actor_role = 'technician' and report_row.assigned_technician_id = actor_id)
  ) then
    raise exception 'Ce compte n''a pas les droits pour modifier ce signalement';
  end if;

  -- 3. Extraction des paramètres
  assigned_id := report_row.assigned_technician_id;
  if p_payload ? 'assigned_technician_id' then
    assigned_id := nullif(p_payload ->> 'assigned_technician_id', '')::uuid;
  end if;

  due_at := report_row.intervention_due_at;
  if p_payload ? 'intervention_due_at' then
    due_at := nullif(p_payload ->> 'intervention_due_at', '')::timestamptz;
  end if;

  note := coalesce(
    nullif(btrim(p_payload ->> 'observation'), ''),
    nullif(btrim(p_payload ->> 'repair_note'), ''),
    nullif(btrim(p_payload ->> 'waiting_reason'), ''),
    ''
  );

  -- Vérification technicien
  if assigned_id is not null and p_action in ('assign', 'chief_update') then
    if not exists (
      select 1 from auth.users u
      where u.id = assigned_id
        and u.raw_app_meta_data ->> 'role' = 'technician'
        and u.raw_app_meta_data ->> 'unit_id' = actor_unit::text
    ) then
      raise exception 'Le technicien sélectionné n''appartient pas à votre unité';
    end if;
  end if;

  -- 4. Exécution par action
  if p_action in ('assign', 'chief_update') then
    if actor_role is distinct from 'unit_head' then
      raise exception 'Seul le chef d''unité peut affecter ou modifier le statut';
    end if;

    next_status := coalesce(
      nullif(p_payload ->> 'status', ''),
      case when assigned_id is null then report_row.status else 'assigned' end
    );

    if next_status not in ('new', 'assigned', 'waiting', 'repaired_pending_validation', 'closed') then
      raise exception 'Statut invalide pour le chef d''unité';
    end if;

    if next_status = 'assigned' and assigned_id is null then
      raise exception 'Veuillez sélectionner un technicien pour affecter le dossier';
    end if;

    update public.maintenance_reports
    set assigned_technician_id = coalesce(assigned_id, assigned_technician_id),
        intervention_due_at = due_at,
        status = next_status,
        observation = case when note <> '' then note else observation end,
        waiting_reason = case when next_status = 'waiting' and note <> '' then note else waiting_reason end,
        updated_at = now()
    where id = p_report_id;

  elsif p_action = 'repair' then
    if actor_role is distinct from 'technician'
       or report_row.assigned_technician_id is distinct from actor_id then
      raise exception 'Seul le technicien affecté peut déclarer la fin de réparation';
    end if;
    note := nullif(btrim(p_payload ->> 'repair_note'), '');
    if note is null and report_row.repair_note is null then
      raise exception 'Un compte rendu de réparation est obligatoire';
    end if;
    next_status := 'repaired_pending_validation';

    update public.maintenance_reports
    set status = next_status,
        repair_note = coalesce(note, repair_note),
        observation = coalesce(note, observation),
        waiting_reason = '',
        updated_at = now()
    where id = p_report_id;

  elsif p_action = 'waiting' then
    if actor_role = 'technician' and report_row.assigned_technician_id is distinct from actor_id then
      raise exception 'Seul le technicien affecté peut signaler un blocage';
    end if;
    note := nullif(btrim(p_payload ->> 'waiting_reason'), '');
    if note is null then
      raise exception 'La raison du blocage ou de l''attente est obligatoire';
    end if;
    next_status := 'waiting';

    update public.maintenance_reports
    set status = next_status,
        waiting_reason = note,
        observation = note,
        updated_at = now()
    where id = p_report_id;

  elsif p_action = 'validate' then
    if actor_role is distinct from 'unit_head' then
      raise exception 'Seul le chef d''unité peut valider une réparation terminée';
    end if;

    -- Idempotence : si le dossier est déjà validé/clôturé, on accepte et met à jour l'observation si fournie
    if report_row.status is distinct from 'repaired_pending_validation' and report_row.status is distinct from 'closed' then
      raise exception 'Seul un dossier réparé en attente de validation peut être validé';
    end if;
    next_status := 'closed';

    update public.maintenance_reports
    set status = next_status,
        observation = case when note <> '' then note else observation end,
        updated_at = now()
    where id = p_report_id;

  else
    raise exception 'Action non prise en charge : %', p_action;
  end if;

  select * into report_row from public.maintenance_reports where id = p_report_id;

  insert into public.maintenance_report_history
    (report_id, event_type, status, observation, actor_id, action_id, changed_at)
  values
    (p_report_id, p_action, report_row.status, note, actor_id, p_action_id, report_row.updated_at);

  insert into public.maintenance_report_action_receipts
    (action_id, report_id, actor_id, status, updated_at, created_at)
  values
    (p_action_id, p_report_id, actor_id, report_row.status, report_row.updated_at, now())
  on conflict (action_id) do nothing;

  return jsonb_build_object(
    'status', report_row.status,
    'updated_at', report_row.updated_at
  );
end;
$$;
