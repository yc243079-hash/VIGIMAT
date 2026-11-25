-- Additive VIGIMAT MVP migration. It preserves existing rows and files.
-- Run after supabase/schema.sql on a new project, or by itself on an existing
-- project that already has the original VIGIMAT schema.

create table if not exists public.maintenance_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.maintenance_units enable row level security;
revoke all on public.maintenance_units from anon, authenticated;

alter table public.maintenance_reports
  add column if not exists reporter_id uuid references auth.users(id) on delete restrict,
  add column if not exists unit_id uuid references public.maintenance_units(id) on delete restrict,
  add column if not exists vehicle_registration text not null default '',
  add column if not exists vehicle_details text not null default '',
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy_m double precision,
  add column if not exists repair_note text not null default '',
  add column if not exists waiting_reason text not null default '';

alter table public.maintenance_reports
  alter column technician_id drop not null;

update public.maintenance_reports
set reporter_id = technician_id
where reporter_id is null and technician_id is not null;

update public.maintenance_reports
set status = case status
  when 'accepted' then 'assigned'
  when 'completed' then 'resolved'
  else status
end
where status in ('accepted', 'completed');

update public.maintenance_report_history
set status = case status
  when 'accepted' then 'assigned'
  when 'completed' then 'resolved'
  else status
end
where status in ('accepted', 'completed');

do $$
declare
  status_constraint record;
begin
  for status_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.maintenance_reports'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format(
      'alter table public.maintenance_reports drop constraint %I',
      status_constraint.conname
    );
  end loop;
end;
$$;

alter table public.maintenance_reports
  add constraint maintenance_reports_status_check
  check (
    status in (
      'new', 'assigned', 'waiting', 'repaired_pending_validation', 'closed',
      'pending', 'in_progress', 'waiting_parts', 'resolved'
    )
  );

create index if not exists maintenance_reports_reporter_created_idx
  on public.maintenance_reports (reporter_id, created_at desc);
create index if not exists maintenance_reports_unit_created_idx
  on public.maintenance_reports (unit_id, created_at desc);
create index if not exists maintenance_reports_assignee_created_idx
  on public.maintenance_reports (assigned_technician_id, created_at desc);

alter table public.maintenance_report_history
  add column if not exists action_id uuid;
create unique index if not exists maintenance_report_history_action_unique_idx
  on public.maintenance_report_history (action_id)
  where action_id is not null;

create table if not exists public.maintenance_report_action_receipts (
  action_id uuid primary key,
  report_id uuid not null references public.maintenance_reports(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  status text not null,
  updated_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.maintenance_report_action_receipts enable row level security;
revoke all on public.maintenance_report_action_receipts from anon, authenticated;

create or replace function public.current_vigimat_role()
returns text
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select u.raw_app_meta_data ->> 'role'
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
  if not found then raise exception 'User profile is unavailable'; end if;

  role_name := profile_user.raw_app_meta_data ->> 'role';
  unit_key := nullif(profile_user.raw_app_meta_data ->> 'unit_id', '')::uuid;
  if role_name not in ('soldier', 'technician', 'unit_head') or unit_key is null then
    raise exception 'VIGIMAT role and unit must be assigned by an administrator';
  end if;

  select name into unit_label
  from public.maintenance_units
  where id = unit_key and active;
  if unit_label is null then raise exception 'VIGIMAT unit is unavailable'; end if;

  return jsonb_build_object(
    'user_id', profile_user.id,
    'role', role_name,
    'unit_id', unit_key,
    'unit_name', unit_label,
    'display_name', coalesce(
      nullif(btrim(profile_user.raw_app_meta_data ->> 'full_name'), ''),
      nullif(btrim(profile_user.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(profile_user.raw_user_meta_data ->> 'name'), ''),
      profile_user.email
    ),
    'personnel_number', coalesce(
      profile_user.raw_app_meta_data ->> 'personnel_number', ''
    )
  );
end;
$$;

revoke all on function public.get_my_app_profile() from public, anon;
grant execute on function public.get_my_app_profile() to authenticated;

create or replace function public.get_assignable_technicians()
returns table (technician_id uuid, display_name text)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if public.current_vigimat_role() is distinct from 'unit_head' then
    raise exception 'Only a unit head may list assignable technicians';
  end if;

  return query
  select
    u.id,
    coalesce(
      nullif(btrim(u.raw_app_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
      u.email,
      'Technicien ' || left(u.id::text, 8)
    )
  from auth.users u
  where u.raw_app_meta_data ->> 'role' = 'technician'
    and u.raw_app_meta_data ->> 'unit_id' = public.current_vigimat_unit_id()::text
  order by 2;
end;
$$;

revoke all on function public.get_assignable_technicians() from public, anon;
grant execute on function public.get_assignable_technicians() to authenticated;

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
  inserted_rows integer;
begin
  if actor_id is null or actor_role is distinct from 'soldier' then
    raise exception 'Only a soldier may create a maintenance report';
  end if;
  if unit_key is null or report_id is null then
    raise exception 'A report id and assigned unit are required';
  end if;
  if nullif(btrim(p_report ->> 'equipment_name'), '') is null then
    raise exception 'Vehicle or equipment name is required';
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
    created_at, status, observation, technician_id, reporter_id, unit_id,
    reporter_name, location, vehicle_registration, vehicle_details, latitude,
    longitude, location_accuracy_m
  ) values (
    report_id,
    coalesce(nullif(btrim(p_report ->> 'reference'), ''),
      'SIG-' || upper(replace(report_id::text, '-', ''))),
    btrim(p_report ->> 'equipment_name'),
    coalesce(p_report ->> 'description', ''),
    coalesce(nullif(p_report ->> 'fault_category', ''), 'Autre'),
    coalesce(nullif(p_report ->> 'priority', ''), 'Moyenne'),
    coalesce(nullif(p_report ->> 'created_at', '')::timestamptz, now()),
    'new', '', actor_id, actor_id, unit_key, coalesce(actor_name, ''),
    coalesce(p_report ->> 'location', ''),
    coalesce(p_report ->> 'vehicle_registration', ''),
    coalesce(p_report ->> 'vehicle_details', ''),
    nullif(p_report ->> 'latitude', '')::double precision,
    nullif(p_report ->> 'longitude', '')::double precision,
    nullif(p_report ->> 'location_accuracy_m', '')::double precision
  ) on conflict (id) do nothing;

  get diagnostics inserted_rows = row_count;
  if inserted_rows = 0 then
    if not exists (
      select 1 from public.maintenance_reports r
      where r.id = report_id and r.reporter_id = actor_id
    ) then
      raise exception 'Report id is already in use';
    end if;
  else
    insert into public.maintenance_report_history
      (report_id, event_type, status, observation, actor_id)
    values (report_id, 'created', 'new', '', actor_id);
  end if;
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
  report_row public.maintenance_reports%rowtype;
  photo_paths text[] := coalesce(p_photo_object_paths, '{}');
  path text;
begin
  select * into report_row
  from public.maintenance_reports
  where id = p_report_id
  for update;
  if not found then raise exception 'Report not found'; end if;
  if public.current_vigimat_role() is distinct from 'soldier'
     or report_row.reporter_id is distinct from auth.uid() then
    raise exception 'Only the reporting soldier may upload report attachments';
  end if;
  if cardinality(photo_paths) > 5 then
    raise exception 'A report may contain at most five photos';
  end if;
  foreach path in array photo_paths loop
    if path not like p_report_id::text || '/%' then
      raise exception 'Invalid report attachment path';
    end if;
  end loop;
  if p_audio_object_path is not null
     and p_audio_object_path not like p_report_id::text || '/%' then
    raise exception 'Invalid report audio path';
  end if;
  if cardinality(report_row.photo_object_paths) > 0
     and report_row.photo_object_paths is distinct from photo_paths then
    raise exception 'Report photos cannot be replaced after upload';
  end if;
  if report_row.audio_object_path is not null
     and report_row.audio_object_path is distinct from p_audio_object_path then
    raise exception 'Report audio cannot be replaced after upload';
  end if;
  if btrim(report_row.description) = ''
     and cardinality(photo_paths) = 0
     and p_audio_object_path is null then
    raise exception 'Add a written description, voice message, or photo';
  end if;

  update public.maintenance_reports
  set photo_object_paths = photo_paths,
      photo_object_path = photo_paths[1],
      audio_object_path = p_audio_object_path
  where id = p_report_id;
end;
$$;

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
  next_status text;
  note text;
  expected_updated_at timestamptz;
  receipt public.maintenance_report_action_receipts%rowtype;
begin
  if actor_id is null or p_action_id is null or p_report_id is null then
    raise exception 'Action identity is required';
  end if;
  perform pg_advisory_lock(hashtextextended(p_action_id::text, 0));

  select * into receipt
  from public.maintenance_report_action_receipts
  where action_id = p_action_id;
  if found then
    if receipt.actor_id is distinct from actor_id
       or receipt.report_id is distinct from p_report_id then
      raise exception 'Action id is already in use';
    end if;
    return jsonb_build_object(
      'status', receipt.status,
      'updated_at', receipt.updated_at
    );
  end if;

  select * into report_row
  from public.maintenance_reports
  where id = p_report_id
  for update;
  if not found then raise exception 'Report not found'; end if;
  if actor_unit is null or report_row.unit_id is distinct from actor_unit then
    raise exception 'Report belongs to another unit';
  end if;
  if not (
    actor_role = 'unit_head'
    or (actor_role = 'technician'
        and report_row.assigned_technician_id = actor_id)
  ) then
    raise exception 'This account cannot update this report';
  end if;

  expected_updated_at := nullif(p_payload ->> 'expected_updated_at', '')::timestamptz;
  if expected_updated_at is not null
     and expected_updated_at is distinct from report_row.updated_at then
    raise exception 'CONFLICT: the report changed on another device; refresh before retrying';
  end if;

  assigned_id := report_row.assigned_technician_id;
  if p_payload ? 'assigned_technician_id' then
    assigned_id := nullif(p_payload ->> 'assigned_technician_id', '')::uuid;
  end if;
  note := coalesce(
    nullif(btrim(p_payload ->> 'observation'), ''),
    nullif(btrim(p_payload ->> 'repair_note'), ''),
    nullif(btrim(p_payload ->> 'waiting_reason'), ''),
    ''
  );

  if assigned_id is not null and p_action in ('assign', 'chief_update') then
    if not exists (
      select 1 from auth.users u
      where u.id = assigned_id
        and u.raw_app_meta_data ->> 'role' = 'technician'
        and u.raw_app_meta_data ->> 'unit_id' = actor_unit::text
    ) then
      raise exception 'Choose an active technician from this unit';
    end if;
  end if;

  if p_action in ('assign', 'chief_update') then
    if actor_role is distinct from 'unit_head' then
      raise exception 'Only a unit head may assign or change report status';
    end if;
    next_status := coalesce(nullif(p_payload ->> 'status', ''),
      case when assigned_id is null then 'new' else 'assigned' end);
    if next_status not in (
      'new', 'assigned', 'waiting', 'repaired_pending_validation'
    ) then
      raise exception 'Invalid report status';
    end if;
    if next_status = 'assigned' and assigned_id is null then
      raise exception 'Assign a technician before setting this status';
    end if;
    update public.maintenance_reports
    set assigned_technician_id = assigned_id,
        status = next_status,
        observation = coalesce(p_payload ->> 'observation', observation),
        waiting_reason = coalesce(p_payload ->> 'waiting_reason', waiting_reason),
        repair_note = coalesce(p_payload ->> 'repair_note', repair_note)
    where id = p_report_id;
  elsif p_action = 'repair' then
    if actor_role is distinct from 'technician'
       or report_row.assigned_technician_id is distinct from actor_id then
      raise exception 'Only the assigned technician may report a repair';
    end if;
    if report_row.status not in ('assigned', 'waiting', 'in_progress', 'waiting_parts') then
      raise exception 'This report is not open for technician updates';
    end if;
    note := nullif(btrim(p_payload ->> 'repair_note'), '');
    if note is null then raise exception 'Enter a short repair report'; end if;
    next_status := 'repaired_pending_validation';
    update public.maintenance_reports
    set status = next_status,
        repair_note = note,
        observation = note,
        waiting_reason = ''
    where id = p_report_id;
  elsif p_action = 'waiting' then
    if actor_role = 'technician'
       and report_row.assigned_technician_id is distinct from actor_id then
      raise exception 'Only the assigned technician may report a blocked repair';
    end if;
    if actor_role not in ('technician', 'unit_head') then
      raise exception 'This account cannot report a blocked repair';
    end if;
    if report_row.status = 'closed' then
      raise exception 'A closed report can only be reopened by a unit head';
    end if;
    note := nullif(btrim(p_payload ->> 'waiting_reason'), '');
    if note is null then raise exception 'Enter the reason for the delay'; end if;
    next_status := 'waiting';
    update public.maintenance_reports
    set status = next_status,
        waiting_reason = note,
        observation = note
    where id = p_report_id;
  elsif p_action = 'validate' then
    if actor_role is distinct from 'unit_head'
       or report_row.status is distinct from 'repaired_pending_validation' then
      raise exception 'Only a unit head may validate a completed repair';
    end if;
    next_status := 'closed';
    note := nullif(btrim(p_payload ->> 'observation'), '');
    update public.maintenance_reports
    set status = next_status,
        observation = coalesce(note, observation)
    where id = p_report_id;
  else
    raise exception 'Unsupported report action';
  end if;

  select * into report_row
  from public.maintenance_reports
  where id = p_report_id;

  insert into public.maintenance_report_history
    (report_id, event_type, status, observation, actor_id, action_id)
  values
    (p_report_id, p_action, report_row.status, note, actor_id, p_action_id);

  insert into public.maintenance_report_action_receipts
    (action_id, report_id, actor_id, status, updated_at)
  values
    (p_action_id, p_report_id, actor_id, report_row.status, report_row.updated_at);

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

-- Replace old owner-based policies with the approved three-role access model.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('maintenance_reports', 'maintenance_report_history')
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      policy_row.policyname,
      policy_row.tablename
    );
  end loop;
end;
$$;

create policy "mvp report readers"
  on public.maintenance_reports for select to authenticated
  using (
    (
      public.current_vigimat_role() = 'soldier'
      and reporter_id = (select auth.uid())
    )
    or (
      public.current_vigimat_role() = 'technician'
      and
      assigned_technician_id = (select auth.uid())
      and unit_id = public.current_vigimat_unit_id()
    )
    or (
      public.current_vigimat_role() = 'unit_head'
      and unit_id = public.current_vigimat_unit_id()
    )
  );

revoke insert, update, delete on public.maintenance_reports from anon, authenticated;
grant select on public.maintenance_reports to authenticated;

create policy "mvp report history readers"
  on public.maintenance_report_history for select to authenticated
  using (
    exists (
      select 1 from public.maintenance_reports r
      where r.id = report_id
        and (
          (
            public.current_vigimat_role() = 'soldier'
            and r.reporter_id = (select auth.uid())
          )
          or (
            public.current_vigimat_role() = 'technician'
            and
            r.assigned_technician_id = (select auth.uid())
            and r.unit_id = public.current_vigimat_unit_id()
          )
          or (
            public.current_vigimat_role() = 'unit_head'
            and r.unit_id = public.current_vigimat_unit_id()
          )
        )
    )
  );
revoke insert, update, delete on public.maintenance_report_history from anon, authenticated;
grant select on public.maintenance_report_history to authenticated;

drop trigger if exists maintenance_report_audit on public.maintenance_reports;
drop trigger if exists maintenance_report_notifications on public.maintenance_reports;

insert into storage.buckets as existing_bucket (id, name, public, file_size_limit)
values ('report-attachments', 'report-attachments', false, 20971520)
on conflict (id) do update
set public = false,
    file_size_limit = least(
      coalesce(existing_bucket.file_size_limit, 20971520),
      excluded.file_size_limit
    );

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (
        coalesce(qual, '') ilike '%report-attachments%'
        or coalesce(with_check, '') ilike '%report-attachments%'
      )
  loop
    execute format('drop policy if exists %I on storage.objects', policy_row.policyname);
  end loop;
end;
$$;

create policy "mvp report attachment uploads"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (
            public.current_vigimat_role() = 'soldier'
            and r.reporter_id = (select auth.uid())
          )
          or (
            public.current_vigimat_role() = 'technician'
            and
            r.assigned_technician_id = (select auth.uid())
            and r.unit_id = public.current_vigimat_unit_id()
          )
          or (
            public.current_vigimat_role() = 'unit_head'
            and r.unit_id = public.current_vigimat_unit_id()
          )
        )
    )
  );

create policy "mvp report attachment updates"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (
            public.current_vigimat_role() = 'soldier'
            and r.reporter_id = (select auth.uid())
          )
          or (
            public.current_vigimat_role() = 'technician'
            and
            r.assigned_technician_id = (select auth.uid())
            and r.unit_id = public.current_vigimat_unit_id()
          )
          or (
            public.current_vigimat_role() = 'unit_head'
            and r.unit_id = public.current_vigimat_unit_id()
          )
        )
    )
  )
  with check (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (
            public.current_vigimat_role() = 'soldier'
            and r.reporter_id = (select auth.uid())
          )
          or (
            public.current_vigimat_role() = 'technician'
            and r.assigned_technician_id = (select auth.uid())
            and r.unit_id = public.current_vigimat_unit_id()
          )
          or (
            public.current_vigimat_role() = 'unit_head'
            and r.unit_id = public.current_vigimat_unit_id()
          )
        )
    )
  );

create policy "mvp report attachment readers"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'report-attachments'
    and exists (
      select 1 from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          (
            public.current_vigimat_role() = 'soldier'
            and r.reporter_id = (select auth.uid())
          )
          or (
            public.current_vigimat_role() = 'technician'
            and r.assigned_technician_id = (select auth.uid())
            and r.unit_id = public.current_vigimat_unit_id()
          )
          or (
            public.current_vigimat_role() = 'unit_head'
            and r.unit_id = public.current_vigimat_unit_id()
          )
        )
    )
  );
