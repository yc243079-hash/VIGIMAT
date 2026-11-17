create table if not exists public.maintenance_reports (
  id uuid primary key,
  reference text not null,
  equipment_name text not null,
  description text not null default '',
  fault_category text not null default 'Autre',
  priority text not null default 'Moyenne',
  created_at timestamptz not null default now(),
  status text not null default 'new',
  observation text not null default '',
  technician_id uuid not null references auth.users(id) on delete restrict,
  reporter_name text not null default '',
  location text not null default '',
  assigned_technician_id uuid references auth.users(id) on delete restrict,
  intervention_due_at timestamptz,
  updated_at timestamptz not null default now(),
  photo_object_path text,
  photo_object_paths text[] not null default '{}',
  audio_object_path text
);

alter table public.maintenance_reports
  add column if not exists reference text;
alter table public.maintenance_reports
  add column if not exists fault_category text not null default 'Autre';
alter table public.maintenance_reports
  add column if not exists reporter_name text not null default '';
alter table public.maintenance_reports
  add column if not exists location text not null default '';
alter table public.maintenance_reports
  add column if not exists photo_object_paths text[] not null default '{}';
alter table public.maintenance_reports
  add column if not exists assigned_technician_id uuid
  references auth.users(id) on delete restrict;
alter table public.maintenance_reports
  add column if not exists intervention_due_at timestamptz;
alter table public.maintenance_reports
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.maintenance_reports'::regclass
      and conname = 'maintenance_reports_assignment_deadline_check'
  ) then
    alter table public.maintenance_reports
      add constraint maintenance_reports_assignment_deadline_check
      check (
        assigned_technician_id is null
        or intervention_due_at is not null
      );
  end if;
end;
$$;

do $$
declare
  report_constraint record;
begin
  for report_constraint in
    select conname, pg_get_constraintdef(oid) as definition
    from pg_constraint
    where conrelid = 'public.maintenance_reports'::regclass
      and contype = 'c'
      and (
        pg_get_constraintdef(oid) ilike '%priority%'
        or pg_get_constraintdef(oid) ilike '%status%'
      )
  loop
    execute format(
      'alter table public.maintenance_reports drop constraint %I',
      report_constraint.conname
    );
  end loop;
end;
$$;

update public.maintenance_reports
set status = case status
  when 'accepted' then 'assigned'
  when 'completed' then 'resolved'
  else status
end;

update public.maintenance_reports
set reference = 'SIG-' || upper(replace(id::text, '-', ''))
where reference is null or btrim(reference) = '';

update public.maintenance_reports
set photo_object_paths = array[photo_object_path]
where photo_object_path is not null
  and cardinality(photo_object_paths) = 0;

alter table public.maintenance_reports
  alter column reference set not null;

alter table public.maintenance_reports
  add constraint maintenance_reports_priority_check
  check (priority in ('Faible', 'Moyenne', 'Élevée', 'Critique'));
alter table public.maintenance_reports
  add constraint maintenance_reports_status_check
  check (
    status in (
      'new',
      'pending',
      'assigned',
      'in_progress',
      'waiting_parts',
      'resolved',
      'closed'
    )
  );

create unique index if not exists maintenance_reports_reference_unique_idx
  on public.maintenance_reports (reference);

create or replace function public.set_maintenance_report_reference()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.reference is null or btrim(new.reference) = '' then
    new.reference := 'SIG-' || upper(replace(new.id::text, '-', ''));
  end if;
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists maintenance_report_reference_before_insert
  on public.maintenance_reports;
create trigger maintenance_report_reference_before_insert
  before insert or update on public.maintenance_reports
  for each row execute function public.set_maintenance_report_reference();

alter table public.maintenance_reports enable row level security;

drop policy if exists "report readers" on public.maintenance_reports;
create policy "report readers"
  on public.maintenance_reports for select
  to authenticated
  using (
    technician_id = (select auth.uid())
    or assigned_technician_id = (select auth.uid())
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  );

drop policy if exists "technicians create reports" on public.maintenance_reports;
create policy "technicians create reports"
  on public.maintenance_reports for insert
  to authenticated
  with check (
    technician_id = (select auth.uid())
    and (auth.jwt() -> 'app_metadata' ->> 'role') = 'technician'
  );

drop policy if exists "authorized report updates" on public.maintenance_reports;
create policy "authorized report updates"
  on public.maintenance_reports for update
  to authenticated
  using (
    technician_id = (select auth.uid())
    or assigned_technician_id = (select auth.uid())
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  )
  with check (
    technician_id = (select auth.uid())
    or assigned_technician_id = (select auth.uid())
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  );

grant select, insert, update on public.maintenance_reports to authenticated;

create table if not exists public.maintenance_report_history (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.maintenance_reports(id) on delete cascade,
  event_type text not null,
  status text not null,
  observation text not null default '',
  actor_id uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

update public.maintenance_report_history
set status = case status
  when 'accepted' then 'assigned'
  when 'completed' then 'resolved'
  else status
end
where status in ('accepted', 'completed');

grant select on public.maintenance_report_history to authenticated;

alter table public.maintenance_report_history enable row level security;

drop policy if exists "report history readers" on public.maintenance_report_history;
create policy "report history readers"
  on public.maintenance_report_history for select
  to authenticated
  using (
    exists (
      select 1
      from public.maintenance_reports r
      where r.id = report_id
        and (
          r.technician_id = (select auth.uid())
          or r.assigned_technician_id = (select auth.uid())
          or (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
        )
    )
  );

create table if not exists public.equipment_inventory (
  id uuid primary key default gen_random_uuid(),
  reference text,
  name text not null,
  category text not null default '',
  description text not null default '',
  brand text not null default '',
  model text not null default '',
  serial_number text not null default '',
  photo_object_path text,
  location text not null default '',
  acquired_on date,
  status text not null
    check (status in ('operational', 'broken', 'maintenance')),
  responsible_service text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.equipment_inventory
  add column if not exists reference text;
alter table public.equipment_inventory
  add column if not exists description text not null default '';
alter table public.equipment_inventory
  add column if not exists brand text not null default '';
alter table public.equipment_inventory
  add column if not exists model text not null default '';
alter table public.equipment_inventory
  add column if not exists serial_number text not null default '';
alter table public.equipment_inventory
  add column if not exists photo_object_path text;
alter table public.equipment_inventory
  add column if not exists location text not null default '';
alter table public.equipment_inventory
  add column if not exists acquired_on date;
alter table public.equipment_inventory
  add column if not exists responsible_service text not null default '';

update public.equipment_inventory
set reference = 'EQ-' || upper(replace(id::text, '-', ''))
where reference is null or btrim(reference) = '';

alter table public.equipment_inventory
  alter column reference set not null;

create unique index if not exists equipment_inventory_reference_unique_idx
  on public.equipment_inventory (reference);

alter table public.maintenance_reports
  add column if not exists equipment_id uuid
  references public.equipment_inventory(id) on delete set null;

update public.maintenance_reports r
set equipment_id = e.id
from (
  select lower(btrim(name)) as name_key, (array_agg(id))[1] as id
  from public.equipment_inventory
  group by lower(btrim(name))
  having count(*) = 1
) e
where r.equipment_id is null
  and lower(btrim(r.equipment_name)) = e.name_key;

create or replace function public.set_equipment_reference()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.reference is null or btrim(new.reference) = '' then
    new.reference := 'EQ-' || upper(replace(new.id::text, '-', ''));
  end if;
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists equipment_reference_before_insert
  on public.equipment_inventory;
drop trigger if exists equipment_reference_before_write
  on public.equipment_inventory;
create trigger equipment_reference_before_write
  before insert or update on public.equipment_inventory
  for each row execute function public.set_equipment_reference();

alter table public.equipment_inventory enable row level security;

drop policy if exists "authorized users read equipment inventory"
  on public.equipment_inventory;
create policy "authorized users read equipment inventory"
  on public.equipment_inventory for select
  to authenticated
  using (true);

drop policy if exists "unit heads manage equipment inventory"
  on public.equipment_inventory;
create policy "unit heads manage equipment inventory"
  on public.equipment_inventory for all
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head');

grant select, insert, update, delete on public.equipment_inventory
  to authenticated;

create index if not exists equipment_inventory_status_idx
  on public.equipment_inventory (status);

create table if not exists public.preventive_maintenance_schedules (
  id uuid primary key default gen_random_uuid(),
  equipment_id uuid not null
    references public.equipment_inventory(id) on delete cascade,
  title text not null,
  due_at timestamptz not null,
  status text not null default 'planned'
    check (status in ('planned', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

alter table public.preventive_maintenance_schedules enable row level security;

drop policy if exists "authorized users read preventive schedules"
  on public.preventive_maintenance_schedules;
create policy "authorized users read preventive schedules"
  on public.preventive_maintenance_schedules for select
  to authenticated
  using (true);

drop policy if exists "unit heads manage preventive schedules"
  on public.preventive_maintenance_schedules;
create policy "unit heads manage preventive schedules"
  on public.preventive_maintenance_schedules for all
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head');

grant select, insert, update, delete
  on public.preventive_maintenance_schedules to authenticated;

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'new_report',
      'critical_failure',
      'intervention_assigned',
      'status_changed',
      'intervention_overdue',
      'maintenance_upcoming',
      'maintenance_overdue',
      'intervention_completed',
      'parts_needed'
    )
  ),
  priority text not null check (priority in ('low', 'normal', 'high', 'critical')),
  title text not null,
  body text not null,
  report_id uuid references public.maintenance_reports(id) on delete cascade,
  schedule_id uuid references public.preventive_maintenance_schedules(id)
    on delete cascade,
  dedupe_key text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  push_sent_at timestamptz,
  push_error text
);

create unique index if not exists user_notifications_recipient_dedupe_idx
  on public.user_notifications (recipient_id, dedupe_key);
create index if not exists user_notifications_unread_idx
  on public.user_notifications (recipient_id, created_at desc)
  where read_at is null;

alter table public.user_notifications enable row level security;

drop policy if exists "users read own notifications"
  on public.user_notifications;
create policy "users read own notifications"
  on public.user_notifications for select
  to authenticated
  using (recipient_id = (select auth.uid()));

drop policy if exists "users mark own notifications read"
  on public.user_notifications;
create policy "users mark own notifications read"
  on public.user_notifications for update
  to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

grant select on public.user_notifications to authenticated;
grant update (read_at) on public.user_notifications to authenticated;
grant select, update (push_sent_at, push_error)
  on public.user_notifications to service_role;

create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

alter table public.user_push_tokens enable row level security;

drop policy if exists "users manage own push tokens"
  on public.user_push_tokens;
create policy "users manage own push tokens"
  on public.user_push_tokens for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.user_push_tokens to authenticated;
grant select, delete on public.user_push_tokens to service_role;

create or replace function public.get_assignable_technicians()
returns table (technician_id uuid, display_name text)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'unit_head' then
    raise exception 'Only a unit head may list assignable technicians';
  end if;

  return query
  select
    u.id,
    coalesce(
      nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
      u.email,
      'Technicien ' || left(u.id::text, 8)
    )
  from auth.users u
  where u.raw_app_meta_data ->> 'role' = 'technician'
  order by 2;
end;
$$;

revoke all on function public.get_assignable_technicians() from public;
grant execute on function public.get_assignable_technicians() to authenticated;

create index if not exists preventive_schedules_due_status_idx
  on public.preventive_maintenance_schedules (status, due_at);

create index if not exists preventive_schedules_equipment_due_idx
  on public.preventive_maintenance_schedules (equipment_id, due_at);

create index if not exists maintenance_reports_equipment_created_idx
  on public.maintenance_reports (equipment_id, created_at desc);

create index if not exists maintenance_reports_created_at_idx
  on public.maintenance_reports (created_at);
create index if not exists maintenance_reports_assigned_due_idx
  on public.maintenance_reports (assigned_technician_id, intervention_due_at)
  where assigned_technician_id is not null
    and status in ('assigned', 'in_progress', 'waiting_parts');

drop index if exists public.report_history_completed_at_idx;
create index report_history_completed_at_idx
  on public.maintenance_report_history (changed_at)
  where event_type = 'updated' and status in ('resolved', 'closed');

create or replace function public.audit_maintenance_report()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  is_unit_head boolean :=
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head';
  assigned_name text;
  assigned_role text;
begin
  if tg_op = 'INSERT' then
    insert into public.maintenance_report_history
      (report_id, event_type, status, observation, actor_id)
    values
      (new.id, 'created', new.status, new.observation, auth.uid());
    return new;
  end if;

  if new.status is distinct from old.status
     or new.observation is distinct from old.observation
     or new.assigned_technician_id is distinct from old.assigned_technician_id
     or new.intervention_due_at is distinct from old.intervention_due_at then
    if not is_unit_head then
      if old.assigned_technician_id is distinct from auth.uid()
         or new.assigned_technician_id is distinct from old.assigned_technician_id
         or new.intervention_due_at is distinct from old.intervention_due_at
         or new.status not in (
           'assigned',
           'in_progress',
           'waiting_parts',
           'resolved'
         )
         or (
           new.id,
           new.equipment_id,
           new.equipment_name,
           new.description,
           new.fault_category,
           new.priority,
           new.created_at,
           new.technician_id,
           new.reporter_name,
           new.location,
           new.reference,
           new.photo_object_path,
           new.photo_object_paths,
           new.audio_object_path
         ) is distinct from (
           old.id,
           old.equipment_id,
           old.equipment_name,
           old.description,
           old.fault_category,
           old.priority,
           old.created_at,
           old.technician_id,
           old.reporter_name,
           old.location,
           old.reference,
           old.photo_object_path,
           old.photo_object_paths,
           old.audio_object_path
         ) then
        raise exception 'Only the assigned technician or a unit head may update report workflow';
      end if;
    end if;

    if new.assigned_technician_id is distinct from old.assigned_technician_id then
      select u.raw_app_meta_data ->> 'role'
      into assigned_role
      from auth.users u
      where u.id = new.assigned_technician_id;
      if new.assigned_technician_id is not null
         and assigned_role is distinct from 'technician' then
        raise exception 'An intervention may only be assigned to a technician';
      end if;

      select coalesce(
        nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
        nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
        u.email,
        'Technicien ' || left(u.id::text, 8)
      )
      into assigned_name
      from auth.users u
      where u.id = new.assigned_technician_id;

      insert into public.maintenance_report_history
        (report_id, event_type, status, observation, actor_id)
      values (
        new.id,
        'assigned',
        new.status,
        case
          when new.assigned_technician_id is null then 'Affectation retirée'
          else 'Intervention affectée à ' || assigned_name
        end,
        auth.uid()
      );
    elsif new.intervention_due_at is distinct from old.intervention_due_at
       and new.assigned_technician_id is not null then
      insert into public.maintenance_report_history
        (report_id, event_type, status, observation, actor_id)
      values (
        new.id,
        'deadline_set',
        new.status,
        'Échéance : ' || to_char(new.intervention_due_at, 'DD/MM/YYYY HH24:MI'),
        auth.uid()
      );
    end if;

  end if;

  if new.status is distinct from old.status
     or new.observation is distinct from old.observation then
    insert into public.maintenance_report_history
      (report_id, event_type, status, observation, actor_id)
    values
      (new.id, 'updated', new.status, new.observation, auth.uid());
  end if;
  return new;
end;
$$;

create or replace function public.notify_maintenance_report()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  target_user_id uuid;
  report_priority text;
  status_body text;
begin
  report_priority := case new.priority
    when 'Critique' then 'critical'
    when 'Élevée' then 'high'
    when 'Moyenne' then 'normal'
    else 'low'
  end;

  if tg_op = 'INSERT' then
    insert into public.user_notifications (
      recipient_id, event_type, priority, title, body, report_id,
      dedupe_key, payload
    )
    select
      u.id,
      'new_report',
      report_priority,
      'Nouveau signalement',
      new.reference || ' · ' || new.equipment_name || ' · '
        || new.fault_category || ' · ' || new.location,
      new.id,
      'report:' || new.id::text || ':new',
      jsonb_build_object('report_id', new.id)
    from auth.users u
    where u.raw_app_meta_data ->> 'role' = 'unit_head'
    on conflict (recipient_id, dedupe_key) do nothing;

    if new.priority = 'Critique' then
      insert into public.user_notifications (
        recipient_id, event_type, priority, title, body, report_id,
        dedupe_key, payload
      )
      select
        u.id,
        'critical_failure',
        'critical',
        'Nouvelle panne critique',
        new.reference || ' · ' || new.equipment_name || ' · ' || new.location,
        new.id,
        'report:' || new.id::text || ':critical',
        jsonb_build_object('report_id', new.id)
      from auth.users u
      where u.raw_app_meta_data ->> 'role' = 'unit_head'
      on conflict (recipient_id, dedupe_key) do nothing;
    end if;

    return new;
  end if;

  if new.priority = 'Critique'
     and old.priority is distinct from new.priority then
    insert into public.user_notifications (
      recipient_id, event_type, priority, title, body, report_id,
      dedupe_key, payload
    )
    select
      u.id,
      'critical_failure',
      'critical',
      'Nouvelle panne critique',
      new.reference || ' · ' || new.equipment_name || ' · ' || new.location,
      new.id,
      'report:' || new.id::text || ':critical:' || new.updated_at::text,
      jsonb_build_object('report_id', new.id)
    from auth.users u
    where u.raw_app_meta_data ->> 'role' = 'unit_head'
      and u.id is distinct from auth.uid()
    on conflict (recipient_id, dedupe_key) do nothing;
  end if;

  if new.assigned_technician_id is distinct from old.assigned_technician_id
     or new.intervention_due_at is distinct from old.intervention_due_at then
    if new.assigned_technician_id is not null then
      insert into public.user_notifications (
        recipient_id, event_type, priority, title, body, report_id,
        dedupe_key, payload
      )
      values (
        new.assigned_technician_id,
        'intervention_assigned',
        report_priority,
        'Intervention affectée',
        new.reference || ' · ' || new.equipment_name
          || case
            when new.intervention_due_at is null then ''
            else ' · Échéance : '
              || to_char(new.intervention_due_at, 'DD/MM/YYYY HH24:MI')
          end,
        new.id,
        'report:' || new.id::text || ':assignment:'
          || new.assigned_technician_id::text || ':' || new.updated_at::text,
        jsonb_build_object('report_id', new.id)
      )
      on conflict (recipient_id, dedupe_key) do nothing;
    end if;
  end if;

  if new.status is distinct from old.status then
    status_body := new.reference || ' · ' || new.equipment_name
      || ' · ' || case new.status
        when 'new' then 'Nouveau'
        when 'pending' then 'En attente'
        when 'assigned' then 'Assigné'
        when 'in_progress' then 'En cours d’intervention'
        when 'waiting_parts' then 'En attente de pièces'
        when 'resolved' then 'Résolu'
        when 'closed' then 'Clôturé'
        else new.status
      end
      || case
        when btrim(new.observation) = '' then ''
        else ' · ' || btrim(new.observation)
      end;

    for target_user_id in
      select distinct recipients.user_id
      from (
        select new.technician_id as user_id
        union all
        select new.assigned_technician_id
        union all
        select u.id
        from auth.users u
        where u.raw_app_meta_data ->> 'role' = 'unit_head'
      ) recipients
      where recipients.user_id is not null
        and recipients.user_id is distinct from auth.uid()
    loop
      insert into public.user_notifications (
        recipient_id, event_type, priority, title, body, report_id,
        dedupe_key, payload
      )
      values (
        target_user_id,
        'status_changed',
        report_priority,
        'Statut de l’intervention modifié',
        status_body,
        new.id,
        'report:' || new.id::text || ':status:' || new.status || ':'
          || new.updated_at::text,
        jsonb_build_object('report_id', new.id)
      )
      on conflict (recipient_id, dedupe_key) do nothing;

      if new.status = 'waiting_parts' then
        insert into public.user_notifications (
          recipient_id, event_type, priority, title, body, report_id,
          dedupe_key, payload
        )
        values (
          target_user_id,
          'parts_needed',
          'high',
          'Pièces de rechange nécessaires',
          new.reference || ' · ' || new.equipment_name
            || case
              when btrim(new.observation) = '' then ''
              else ' · ' || btrim(new.observation)
            end,
          new.id,
          'report:' || new.id::text || ':parts:' || new.updated_at::text,
          jsonb_build_object('report_id', new.id)
        )
        on conflict (recipient_id, dedupe_key) do nothing;
      end if;

      if new.status in ('resolved', 'closed') then
        insert into public.user_notifications (
          recipient_id, event_type, priority, title, body, report_id,
          dedupe_key, payload
        )
        values (
          target_user_id,
          'intervention_completed',
          'normal',
          'Intervention terminée',
          new.reference || ' · ' || new.equipment_name,
          new.id,
          'report:' || new.id::text || ':completed:' || new.status || ':'
            || new.updated_at::text,
          jsonb_build_object('report_id', new.id)
        )
        on conflict (recipient_id, dedupe_key) do nothing;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists maintenance_report_notifications
  on public.maintenance_reports;
create trigger maintenance_report_notifications
  after insert or update on public.maintenance_reports
  for each row execute function public.notify_maintenance_report();

create or replace function public.refresh_maintenance_notifications()
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  insert into public.user_notifications (
    recipient_id, event_type, priority, title, body, report_id,
    dedupe_key, payload
  )
  select
    recipients.user_id,
    'intervention_overdue',
    'high',
    'Intervention en retard',
    r.reference || ' · ' || r.equipment_name || ' · Échéance dépassée',
    r.id,
    'report:' || r.id::text || ':overdue:'
      || to_char(r.intervention_due_at at time zone 'UTC', 'YYYYMMDDHH24MISS'),
    jsonb_build_object('report_id', r.id)
  from public.maintenance_reports r
  cross join lateral (
    select r.assigned_technician_id as user_id
    union
    select r.technician_id
    union
    select u.id
    from auth.users u
    where u.raw_app_meta_data ->> 'role' = 'unit_head'
  ) recipients
  where r.intervention_due_at < now()
    and r.status in ('assigned', 'in_progress', 'waiting_parts')
    and recipients.user_id is not null
  on conflict (recipient_id, dedupe_key) do nothing;

  insert into public.user_notifications (
    recipient_id, event_type, priority, title, body, schedule_id,
    dedupe_key, payload
  )
  select
    recipients.user_id,
    case when s.due_at < now()
      then 'maintenance_overdue'
      else 'maintenance_upcoming'
    end,
    case when s.due_at < now() then 'high' else 'normal' end,
    case when s.due_at < now()
      then 'Entretien préventif dépassé'
      else 'Entretien préventif imminent'
    end,
    e.reference || ' · ' || e.name || ' · ' || s.title
      || ' · Échéance : ' || to_char(s.due_at, 'DD/MM/YYYY HH24:MI'),
    s.id,
    'schedule:' || s.id::text || ':'
      || case when s.due_at < now() then 'overdue:' else 'upcoming:' end
      || to_char(s.due_at at time zone 'UTC', 'YYYYMMDDHH24MISS'),
    jsonb_build_object('schedule_id', s.id, 'equipment_id', e.id)
  from public.preventive_maintenance_schedules s
  join public.equipment_inventory e on e.id = s.equipment_id
  cross join lateral (
    select u.id as user_id
    from auth.users u
    where u.raw_app_meta_data ->> 'role' = 'unit_head'
    union
    select s.created_by
    where s.created_by is not null
  ) recipients
  where s.status = 'planned'
    and s.due_at <= now() + interval '3 days'
  on conflict (recipient_id, dedupe_key) do nothing;
end;
$$;

revoke all on function public.refresh_maintenance_notifications() from public;
grant execute on function public.refresh_maintenance_notifications()
  to authenticated;

create or replace function public.get_unread_notification_count()
returns integer
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select count(*)::integer
  from public.user_notifications
  where recipient_id = (select auth.uid())
    and read_at is null;
$$;

revoke all on function public.get_unread_notification_count() from public;
grant execute on function public.get_unread_notification_count()
  to authenticated;

drop trigger if exists maintenance_report_audit on public.maintenance_reports;
create trigger maintenance_report_audit
  after insert or update on public.maintenance_reports
  for each row execute function public.audit_maintenance_report();

create or replace function public.get_maintenance_dashboard_metrics()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with
  equipment_summary as (
    select
      count(*)::integer as total,
      count(*) filter (where status = 'operational')::integer as operational,
      count(*) filter (where status = 'broken')::integer as broken,
      count(*) filter (where status = 'maintenance')::integer as maintenance
    from public.equipment_inventory
  ),
  report_summary as (
    select
      count(*)::integer as total,
      count(*) filter (where status in ('new', 'pending'))::integer as pending,
      count(*) filter (
        where status in ('assigned', 'in_progress', 'waiting_parts')
      )::integer
        as in_progress,
      count(*) filter (where status in ('resolved', 'closed'))::integer
        as completed
    from public.maintenance_reports
  ),
  completion_events as (
    select report_id, min(changed_at) as completed_at
    from public.maintenance_report_history
    where event_type = 'updated' and status in ('resolved', 'closed')
    group by report_id
  ),
  performance_summary as (
    select
      case
        when count(r.id) = 0 then null
        else count(*) filter (where r.status in ('resolved', 'closed'))
          * 100.0 / count(r.id)
      end as completion_rate,
      avg(extract(epoch from (c.completed_at - r.created_at)) / 86400.0)
        filter (where c.completed_at >= r.created_at)
        as average_resolution_days
    from public.maintenance_reports r
    left join completion_events c on c.report_id = r.id
  ),
  months as (
    select month_start
    from generate_series(
      date_trunc('month', now()) - interval '5 months',
      date_trunc('month', now()),
      interval '1 month'
    ) as month_rows(month_start)
  ),
  monthly_summary as (
    select
      m.month_start,
      (
        select count(*)::integer
        from public.maintenance_reports r
        where r.created_at >= m.month_start
          and r.created_at < m.month_start + interval '1 month'
      ) as opened,
      (
        select count(*)::integer
        from public.maintenance_reports r
        where r.created_at >= m.month_start
          and r.created_at < m.month_start + interval '1 month'
          and r.status in ('resolved', 'closed')
      ) as cohort_completed,
      (
        select count(distinct h.report_id)::integer
        from public.maintenance_report_history h
        where h.changed_at >= m.month_start
          and h.changed_at < m.month_start + interval '1 month'
          and h.event_type = 'updated'
          and h.status in ('resolved', 'closed')
      ) as completed_events
    from months m
  )
  select jsonb_build_object(
    'equipment', (
      select jsonb_build_object(
        'total', total,
        'operational', operational,
        'broken', broken,
        'maintenance', maintenance
      )
      from equipment_summary
    ),
    'reports', (
      select jsonb_build_object(
        'pending', pending,
        'in_progress', in_progress,
        'completed', completed
      )
      from report_summary
    ),
    'maintenance', jsonb_build_object(
      'upcoming',
      (
        select count(*)::integer
        from public.preventive_maintenance_schedules
        where status = 'planned' and due_at >= now()
      )
    ),
    'performance', (
      select jsonb_build_object(
        'completion_rate', completion_rate,
        'average_resolution_days', average_resolution_days
      )
      from performance_summary
    ),
    'months', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'month', to_char(month_start, 'YYYY-MM-DD'),
            'failures', opened,
            'completed', completed_events,
            'opened', opened,
            'completion_rate',
              case
                when opened = 0 then null
                else cohort_completed * 100.0 / opened
              end
          )
          order by month_start
        )
        from monthly_summary
      ),
      '[]'::jsonb
    )
  );
$$;

revoke all on function public.get_maintenance_dashboard_metrics() from public;
grant execute on function public.get_maintenance_dashboard_metrics()
  to authenticated;

insert into storage.buckets (id, name, public)
values ('report-attachments', 'report-attachments', false)
on conflict (id) do update set public = false;

insert into storage.buckets (id, name, public)
values ('equipment-photos', 'equipment-photos', false)
on conflict (id) do update set public = false;

drop policy if exists "authorized users read equipment photos" on storage.objects;
create policy "authorized users read equipment photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'equipment-photos');

drop policy if exists "unit heads upload equipment photos" on storage.objects;
create policy "unit heads upload equipment photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'equipment-photos'
    and (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  );

drop policy if exists "unit heads update equipment photos" on storage.objects;
create policy "unit heads update equipment photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'equipment-photos'
    and (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  )
  with check (
    bucket_id = 'equipment-photos'
    and (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  );

drop policy if exists "unit heads delete equipment photos" on storage.objects;
create policy "unit heads delete equipment photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'equipment-photos'
    and (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
  );

drop policy if exists "report attachment uploads" on storage.objects;
create policy "report attachment uploads"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-attachments'
    and exists (
      select 1
      from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and r.technician_id = (select auth.uid())
    )
  );

drop policy if exists "report attachment updates" on storage.objects;
create policy "report attachment updates"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'report-attachments'
    and exists (
      select 1
      from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and r.technician_id = (select auth.uid())
    )
  )
  with check (
    bucket_id = 'report-attachments'
    and exists (
      select 1
      from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and r.technician_id = (select auth.uid())
    )
  );

drop policy if exists "authorized report attachment reads" on storage.objects;
create policy "authorized report attachment reads"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'report-attachments'
    and exists (
      select 1
      from public.maintenance_reports r
      where r.id::text = (storage.foldername(name))[1]
        and (
          r.technician_id = (select auth.uid())
        or r.assigned_technician_id = (select auth.uid())
          or (auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_head'
        )
    )
  );

do $$
begin
  if exists (
    select 1
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pg_cron'
      and n.nspname = 'cron'
  ) then
    execute $schedule$
      select cron.unschedule(jobid)
      from cron.job
      where jobname = 'vigimat_maintenance_notification_refresh'
    $schedule$;
    execute $schedule$
      select cron.schedule(
        'vigimat_maintenance_notification_refresh',
        '*/15 * * * *',
        'select public.refresh_maintenance_notifications()'
      )
    $schedule$;
  end if;
end;
$$;
