-- =============================================================================
-- VIGIMAT MVP — SCHÉMA UNIFIÉ, CONSOLIDÉ ET AUTO-SUFFISANT (SQL EDITOR)
-- =============================================================================
-- À copier-coller directement dans le SQL Editor de Supabase (Dashboard > SQL Editor)
-- Ce script :
-- 1. Nettoie les anciennes tables et fonctions
-- 2. Crée la table des unités (avec l'unité par défaut UNITE-01)
-- 3. Crée les signalements, historiques et reçus d'action sans contraintes bloquantes
-- 4. Active les règles de sécurité RLS strictes pour Soldat, Chef et Technicien
-- 5. Crée les RPC sécurisées (create_maintenance_report, apply_maintenance_report_action, etc.)
-- 6. Configure le bucket privé report-attachments
-- 7. Met à jour les métadonnées (rôles et unités) des comptes de test
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. NETTOYAGE PROPRE
-- -----------------------------------------------------------------------------
drop trigger if exists maintenance_report_audit on public.maintenance_reports cascade;
drop trigger if exists maintenance_report_notifications on public.maintenance_reports cascade;

drop table if exists public.maintenance_report_action_receipts cascade;
drop table if exists public.maintenance_report_history cascade;
drop table if exists public.maintenance_reports cascade;
drop table if exists public.preventive_maintenance_schedules cascade;
drop table if exists public.equipment_inventory cascade;
drop table if exists public.maintenance_units cascade;
drop table if exists public.user_notifications cascade;
drop table if exists public.user_push_tokens cascade;

drop function if exists public.current_vigimat_role() cascade;
drop function if exists public.current_vigimat_unit_id() cascade;
drop function if exists public.get_my_app_profile() cascade;
drop function if exists public.get_assignable_technicians() cascade;
drop function if exists public.create_maintenance_report(jsonb) cascade;
drop function if exists public.set_maintenance_report_attachments(uuid, text[], text) cascade;
drop function if exists public.apply_maintenance_report_action(uuid, uuid, text, jsonb) cascade;

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- 2. TABLE DES UNITÉS DE MAINTENANCE (maintenance_units)
-- -----------------------------------------------------------------------------
create table public.maintenance_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.maintenance_units enable row level security;
revoke all on public.maintenance_units from anon, authenticated;
grant select on public.maintenance_units to authenticated;

-- Unité de test principale
insert into public.maintenance_units (id, code, name, active)
values (
  '00000000-0000-0000-0000-000000000001',
  'UNITE-01',
  '1ère Compagnie de Maintenance du Matériel',
  true
)
on conflict (code) do update set name = excluded.name, active = true;

-- -----------------------------------------------------------------------------
-- 3. FONCTIONS D'EXTRACTION DU RÔLE ET DE L'UNITÉ
-- -----------------------------------------------------------------------------
create or replace function public.current_vigimat_role()
returns text
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select nullif(u.raw_app_meta_data ->> 'role', '')
  from auth.users u
  where u.id = auth.uid()
$$;

create or replace function public.current_vigimat_unit_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select nullif(u.raw_app_meta_data ->> 'unit_id', '')::uuid
  from auth.users u
  where u.id = auth.uid()
$$;

revoke all on function public.current_vigimat_role() from public, anon;
revoke all on function public.current_vigimat_unit_id() from public, anon;
grant execute on function public.current_vigimat_role() to authenticated;
grant execute on function public.current_vigimat_unit_id() to authenticated;

-- -----------------------------------------------------------------------------
-- 4. TABLE DES SIGNALEMENTS (maintenance_reports)
-- -----------------------------------------------------------------------------
create table public.maintenance_reports (
  id uuid primary key,
  reference text not null,
  equipment_name text not null,
  description text not null default '',
  fault_category text not null default 'Autre',
  priority text not null default 'Moyenne',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  status text not null default 'new',
  observation text not null default '',
  repair_note text not null default '',
  waiting_reason text not null default '',
  reporter_name text not null default '',
  location text not null default '',
  vehicle_registration text not null default '',
  vehicle_details text not null default '',
  latitude double precision,
  longitude double precision,
  location_accuracy_m double precision,
  technician_id uuid references auth.users(id) on delete restrict,
  reporter_id uuid references auth.users(id) on delete restrict,
  unit_id uuid references public.maintenance_units(id) on delete restrict,
  equipment_id text,
  assigned_technician_id uuid references auth.users(id) on delete restrict,
  intervention_due_at timestamptz,
  photo_object_path text,
  photo_object_paths text[] not null default '{}',
  audio_object_path text,
  constraint maintenance_reports_priority_check check (
    priority in ('Faible', 'Moyenne', 'Haute', 'Élevée', 'Elevee', 'Critique')
  ),
  constraint maintenance_reports_status_check check (
    status in (
      'new', 'assigned', 'waiting', 'repaired_pending_validation', 'closed',
      'pending', 'in_progress', 'waiting_parts', 'resolved'
    )
  )
);

create index maintenance_reports_reporter_created_idx
  on public.maintenance_reports (reporter_id, created_at desc);
create index maintenance_reports_unit_created_idx
  on public.maintenance_reports (unit_id, created_at desc);
create index maintenance_reports_assignee_created_idx
  on public.maintenance_reports (assigned_technician_id, created_at desc);

alter table public.maintenance_reports enable row level security;
revoke insert, update, delete on public.maintenance_reports from anon, authenticated;
grant select on public.maintenance_reports to authenticated;

create policy "vigimat_reports_select_policy"
  on public.maintenance_reports for select to authenticated
  using (
    (
      public.current_vigimat_role() = 'soldier'
      and reporter_id = (select auth.uid())
    )
    or (
      public.current_vigimat_role() = 'technician'
      and assigned_technician_id = (select auth.uid())
      and unit_id = public.current_vigimat_unit_id()
    )
    or (
      public.current_vigimat_role() = 'unit_head'
      and unit_id = public.current_vigimat_unit_id()
    )
  );

-- -----------------------------------------------------------------------------
-- 5. HISTORIQUE D'AUDIT ET REÇUS D'ACTIONS
-- -----------------------------------------------------------------------------
create table public.maintenance_report_history (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.maintenance_reports(id) on delete cascade,
  event_type text not null,
  status text not null,
  observation text not null default '',
  actor_id uuid references auth.users(id) on delete set null,
  action_id uuid,
  changed_at timestamptz not null default now()
);

create unique index maintenance_report_history_action_unique_idx
  on public.maintenance_report_history (action_id)
  where action_id is not null;

alter table public.maintenance_report_history enable row level security;
revoke insert, update, delete on public.maintenance_report_history from anon, authenticated;
grant select on public.maintenance_report_history to authenticated;

create policy "vigimat_history_select_policy"
  on public.maintenance_report_history for select to authenticated
  using (
    exists (
      select 1 from public.maintenance_reports r
      where r.id = report_id
        and (
          (public.current_vigimat_role() = 'soldier' and r.reporter_id = (select auth.uid()))
          or (public.current_vigimat_role() = 'technician' and r.assigned_technician_id = (select auth.uid()) and r.unit_id = public.current_vigimat_unit_id())
          or (public.current_vigimat_role() = 'unit_head' and r.unit_id = public.current_vigimat_unit_id())
        )
    )
  );

create table public.maintenance_report_action_receipts (
  action_id uuid primary key,
  report_id uuid not null references public.maintenance_reports(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  status text not null,
  updated_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.maintenance_report_action_receipts enable row level security;
revoke all on public.maintenance_report_action_receipts from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6. RPC : RÉCUPÉRATION DU PROFIL ET TECHNICIENS DE L'UNITÉ
-- -----------------------------------------------------------------------------
create or replace function public.get_my_app_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  profile_user auth.users%rowtype;
  role_name text;
  unit_key uuid;
  unit_label text;
begin
  select * into profile_user from auth.users where id = auth.uid();
  if not found then
    raise exception 'Compte introuvable';
  end if;

  role_name := nullif(profile_user.raw_app_meta_data ->> 'role', '');
  if role_name is null then
    role_name := nullif(profile_user.raw_user_meta_data ->> 'role', '');
  end if;

  unit_key := nullif(profile_user.raw_app_meta_data ->> 'unit_id', '')::uuid;
  if unit_key is null then
    unit_key := nullif(profile_user.raw_user_meta_data ->> 'unit_id', '')::uuid;
  end if;

  if unit_key is not null then
    select name into unit_label from public.maintenance_units where id = unit_key and active = true;
  end if;

  return jsonb_build_object(
    'user_id', profile_user.id,
    'role', coalesce(role_name, ''),
    'unit_id', coalesce(unit_key::text, ''),
    'unit_name', coalesce(unit_label, ''),
    'full_name', coalesce(
      nullif(btrim(profile_user.raw_app_meta_data ->> 'full_name'), ''),
      nullif(btrim(profile_user.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(profile_user.raw_user_meta_data ->> 'name'), ''),
      profile_user.email
    ),
    'personnel_number', coalesce(
      profile_user.raw_app_meta_data ->> 'personnel_number',
      profile_user.raw_user_meta_data ->> 'personnel_number',
      ''
    )
  );
end;
$$;

create or replace function public.get_assignable_technicians()
returns table (
  technician_id uuid,
  display_name text,
  personnel_number text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  actor_role text := public.current_vigimat_role();
  actor_unit uuid := public.current_vigimat_unit_id();
begin
  if actor_role is distinct from 'unit_head' or actor_unit is null then
    return;
  end if;

  return query
  select
    u.id as technician_id,
    coalesce(
      nullif(btrim(u.raw_app_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
      u.email
    ) as display_name,
    coalesce(
      u.raw_app_meta_data ->> 'personnel_number',
      u.raw_user_meta_data ->> 'personnel_number',
      ''
    ) as personnel_number
  from auth.users u
  where u.raw_app_meta_data ->> 'role' = 'technician'
    and u.raw_app_meta_data ->> 'unit_id' = actor_unit::text
  order by 2;
end;
$$;

revoke all on function public.get_my_app_profile() from public, anon;
revoke all on function public.get_assignable_technicians() from public, anon;
grant execute on function public.get_my_app_profile() to authenticated;
grant execute on function public.get_assignable_technicians() to authenticated;

-- -----------------------------------------------------------------------------
-- 7. RPC : CRÉATION D'UN SIGNALEMENT (Soldat)
-- -----------------------------------------------------------------------------
create or replace function public.create_maintenance_report(p_report jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  actor_role text := public.current_vigimat_role();
  unit_key uuid := public.current_vigimat_unit_id();
  report_id uuid := nullif(p_report ->> 'id', '')::uuid;
  actor_name text;
begin
  if actor_id is null or actor_role is distinct from 'soldier' then
    raise exception 'Seul un soldat authentifié peut créer un signalement';
  end if;
  if unit_key is null or report_id is null then
    raise exception 'Identifiant du signalement et unité requis';
  end if;
  if nullif(btrim(p_report ->> 'equipment_name'), '') is null then
    raise exception 'Le nom du véhicule ou équipement est requis';
  end if;

  select coalesce(
    nullif(btrim(u.raw_app_meta_data ->> 'full_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
    u.email
  ) into actor_name
  from auth.users u where u.id = actor_id;

  insert into public.maintenance_reports (
    id, reference, equipment_name, description, fault_category, priority,
    created_at, updated_at, status, observation, technician_id, reporter_id, unit_id,
    reporter_name, location, vehicle_registration, vehicle_details, latitude,
    longitude, location_accuracy_m
  )
  values (
    report_id,
    coalesce(nullif(p_report ->> 'reference', ''), 'SIG-' || upper(replace(report_id::text, '-', ''))),
    p_report ->> 'equipment_name',
    coalesce(p_report ->> 'description', ''),
    coalesce(nullif(p_report ->> 'fault_category', ''), 'Autre'),
    coalesce(nullif(p_report ->> 'priority', ''), 'Moyenne'),
    coalesce(nullif(p_report ->> 'created_at', '')::timestamptz, now()),
    now(),
    'new',
    '',
    actor_id,
    actor_id,
    unit_key,
    coalesce(nullif(actor_name, ''), 'Soldat déclarant'),
    coalesce(p_report ->> 'location', ''),
    coalesce(p_report ->> 'vehicle_registration', ''),
    coalesce(p_report ->> 'vehicle_details', ''),
    nullif(p_report ->> 'latitude', '')::double precision,
    nullif(p_report ->> 'longitude', '')::double precision,
    nullif(p_report ->> 'location_accuracy_m', '')::double precision
  )
  on conflict (id) do nothing;

  insert into public.maintenance_report_history (
    report_id, event_type, status, observation, actor_id
  )
  values (
    report_id, 'created', 'new', 'Création du signalement', actor_id
  )
  on conflict do nothing;

  return report_id;
end;
$$;

create or replace function public.set_maintenance_report_attachments(
  p_report_id uuid,
  p_photo_object_paths text[],
  p_audio_object_path text
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  actor_role text := public.current_vigimat_role();
begin
  if actor_id is null or actor_role is distinct from 'soldier' then
    raise exception 'Seul le soldat déclarant peut joindre des médias au signalement';
  end if;

  update public.maintenance_reports
  set photo_object_paths = coalesce(p_photo_object_paths, '{}'),
      photo_object_path = case
        when cardinality(coalesce(p_photo_object_paths, '{}')) > 0 then p_photo_object_paths[1]
        else null
      end,
      audio_object_path = p_audio_object_path,
      updated_at = now()
  where id = p_report_id
    and reporter_id = actor_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. RPC : ACTIONS DE WORKFLOW (Chef, Technicien)
-- -----------------------------------------------------------------------------
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

  -- 1. Idempotence
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

revoke all on function public.create_maintenance_report(jsonb) from public, anon;
revoke all on function public.set_maintenance_report_attachments(uuid, text[], text) from public, anon;
revoke all on function public.apply_maintenance_report_action(uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.create_maintenance_report(jsonb) to authenticated;
grant execute on function public.set_maintenance_report_attachments(uuid, text[], text) to authenticated;
grant execute on function public.apply_maintenance_report_action(uuid, uuid, text, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. CONFIGURATION DU STORAGE (report-attachments)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('report-attachments', 'report-attachments', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

do $$
declare policy_name text;
begin
  for policy_name in
    select p.policyname from pg_policies p
    where p.schemaname = 'storage' and p.tablename = 'objects'
      and p.policyname like '%report-attachments%'
  loop
    execute format('drop policy if exists %I on storage.objects', policy_name);
  end loop;
end;
$$;

create policy "report_attachments_insert_policy"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (public.current_vigimat_role() = 'soldier' and r.reporter_id = (select auth.uid()))
          or (public.current_vigimat_role() = 'unit_head' and r.unit_id = public.current_vigimat_unit_id())
          or (public.current_vigimat_role() = 'technician' and r.assigned_technician_id = (select auth.uid()) and r.unit_id = public.current_vigimat_unit_id())
        )
    )
  );

create policy "report_attachments_select_policy"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (public.current_vigimat_role() = 'soldier' and r.reporter_id = (select auth.uid()))
          or (public.current_vigimat_role() = 'unit_head' and r.unit_id = public.current_vigimat_unit_id())
          or (public.current_vigimat_role() = 'technician' and r.assigned_technician_id = (select auth.uid()) and r.unit_id = public.current_vigimat_unit_id())
        )
    )
  );

-- -----------------------------------------------------------------------------
-- 10. ATTRIBUTION AUTOMATIQUE DES RÔLES ET UNITÉS DANS AUTH.USERS
-- -----------------------------------------------------------------------------
-- Si les utilisateurs soldat@test.com, chef@test.com, technicien@test.com
-- existent déjà dans auth.users, cette commande met à jour leurs métadonnées
-- avec les rôles protégés et l'unité UNITE-01 :
update auth.users
set raw_app_meta_data = raw_app_meta_data || jsonb_build_object(
  'role', 'soldier',
  'unit_id', '00000000-0000-0000-0000-000000000001',
  'full_name', 'Soldat Moussa Traoré',
  'personnel_number', 'ML-SOL-042'
)
where email = 'soldat@test.com';

update auth.users
set raw_app_meta_data = raw_app_meta_data || jsonb_build_object(
  'role', 'unit_head',
  'unit_id', '00000000-0000-0000-0000-000000000001',
  'full_name', 'Capitaine Amadou Diallo',
  'personnel_number', 'ML-OFF-012'
)
where email = 'chef@test.com';

update auth.users
set raw_app_meta_data = raw_app_meta_data || jsonb_build_object(
  'role', 'technician',
  'unit_id', '00000000-0000-0000-0000-000000000001',
  'full_name', 'Sergent Bakary Koné',
  'personnel_number', 'ML-TEC-088'
)
where email = 'technicien@test.com';
