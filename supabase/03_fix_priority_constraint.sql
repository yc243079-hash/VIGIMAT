-- =============================================================================
-- VIGIMAT - Correctif Contrainte de Priorité (Élevée / Haute)
-- =============================================================================
-- Permet d'accepter à la fois 'Haute', 'Élevée', 'Elevee' ainsi que 'Faible',
-- 'Moyenne' et 'Critique', évitant l'erreur 23514 (maintenance_reports_priority_check).

alter table public.maintenance_reports
  drop constraint if exists maintenance_reports_priority_check;

alter table public.maintenance_reports
  add constraint maintenance_reports_priority_check check (
    priority in ('Faible', 'Moyenne', 'Haute', 'Élevée', 'Elevee', 'Critique')
  );

-- Mise à jour de la fonction create_maintenance_report pour normaliser si besoin
create or replace function public.create_maintenance_report(p_report jsonb)
returns public.maintenance_reports
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_role text;
  v_user_id uuid;
  v_unit_id uuid;
  v_report public.maintenance_reports%rowtype;
  v_priority text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Non authentifié' using errcode = '42501';
  end if;

  v_role := public.current_vigimat_role();
  v_unit_id := public.current_vigimat_unit_id();

  -- Normalisation de la priorité
  v_priority := coalesce(p_report ->> 'priority', 'Moyenne');
  if lower(v_priority) in ('haute', 'élevée', 'elevee') then
    v_priority := 'Haute';
  elsif lower(v_priority) = 'critique' then
    v_priority := 'Critique';
  elsif lower(v_priority) = 'faible' then
    v_priority := 'Faible';
  else
    v_priority := 'Moyenne';
  end if;

  insert into public.maintenance_reports (
    id,
    reference,
    equipment_name,
    description,
    fault_category,
    priority,
    created_at,
    updated_at,
    status,
    reporter_name,
    location,
    vehicle_registration,
    vehicle_details,
    latitude,
    longitude,
    location_accuracy_m,
    reporter_id,
    unit_id,
    sync_state
  )
  values (
    (p_report ->> 'id')::uuid,
    coalesce(p_report ->> 'reference', 'SIG-' || upper(replace((p_report ->> 'id'), '-', ''))),
    coalesce(p_report ->> 'equipment_name', 'Matériel non spécifié'),
    coalesce(p_report ->> 'description', ''),
    coalesce(p_report ->> 'fault_category', 'Autre'),
    v_priority,
    coalesce((p_report ->> 'created_at')::timestamptz, now()),
    now(),
    'new',
    coalesce(p_report ->> 'reporter_name', (select raw_user_meta_data ->> 'display_name' from auth.users where id = v_user_id), 'Opérateur'),
    coalesce(p_report ->> 'location', ''),
    coalesce(p_report ->> 'vehicle_registration', ''),
    coalesce(p_report ->> 'vehicle_details', ''),
    (p_report ->> 'latitude')::double precision,
    (p_report ->> 'longitude')::double precision,
    (p_report ->> 'location_accuracy_m')::double precision,
    v_user_id,
    v_unit_id,
    'sent'
  )
  on conflict (id) do update
  set
    updated_at = now(),
    priority = excluded.priority
  returning * into v_report;

  -- Historisation initiale
  insert into public.maintenance_report_history (
    report_id,
    event_type,
    status,
    observation,
    actor_id,
    changed_at
  )
  values (
    v_report.id,
    'created',
    'new',
    coalesce(v_report.description, 'Création du signalement'),
    v_user_id,
    now()
  );

  return v_report;
end;
$$;
