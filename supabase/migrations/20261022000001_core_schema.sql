-- Evolix.fit — migration 0001: esquema central, RLS e isolamento por organização.
-- STATUS: escrita mas NÃO executada contra um Postgres/Supabase real (ver PROJECT_STATUS.md).
-- Rode com: supabase db reset  (local)  e depois execute supabase/tests/rls_isolation.sql

-- ===== Tipos =====
create type public.org_role as enum ('owner','manager','trainer','student');
create type public.org_status as enum ('active','suspended');
create type public.plan_status as enum ('draft','published','archived');
create type public.session_status as enum ('in_progress','finished','discarded');

-- ===== Tabelas =====
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '' check (char_length(full_name) <= 120),
  is_superadmin boolean not null default false,  -- só alterável por SQL/service role
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  status public.org_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.org_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index on public.organization_members(user_id);

create table public.trainer_student_relationships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  trainer_id uuid not null,
  student_id uuid not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (org_id, trainer_id, student_id),
  check (trainer_id <> student_id),
  foreign key (org_id, trainer_id) references public.organization_members(org_id, user_id),
  foreign key (org_id, student_id) references public.organization_members(org_id, user_id)
);
create index on public.trainer_student_relationships(student_id);
create index on public.trainer_student_relationships(trainer_id);

-- org_id nulo = exercício global (gerido pelo superadmin)
create table public.exercise_library (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 120),
  muscle_group text not null,
  equipment text not null default '',
  instructions text not null default '',
  media_url text,
  media_source text,
  media_license text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (media_url is null or media_license is not null)  -- mídia exige licença registrada
);
create index on public.exercise_library(org_id, name);

create table public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  trainer_id uuid not null,
  student_id uuid not null,
  name text not null check (char_length(name) between 1 and 120),
  goal text not null default '',
  notes text not null default '',
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id),
  foreign key (org_id, trainer_id) references public.organization_members(org_id, user_id),
  foreign key (org_id, student_id) references public.organization_members(org_id, user_id)
);
create index on public.workout_plans(student_id);
create index on public.workout_plans(trainer_id);

create table public.workout_plan_versions (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null,
  org_id uuid not null,
  version int not null check (version >= 1),
  status public.plan_status not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (plan_id, version),
  unique (id, org_id),
  foreign key (plan_id, org_id) references public.workout_plans(id, org_id) on delete cascade
);
create unique index one_published_per_plan on public.workout_plan_versions(plan_id) where status = 'published';
create unique index one_draft_per_plan on public.workout_plan_versions(plan_id) where status = 'draft';

create table public.workout_plan_items (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null,
  org_id uuid not null,
  position int not null check (position >= 0),
  exercise_id uuid not null references public.exercise_library(id),
  sets int not null check (sets between 1 and 20),
  reps text not null check (char_length(reps) between 1 and 20),
  prescribed_load_kg numeric(6,2) check (prescribed_load_kg >= 0),
  rest_seconds int not null default 60 check (rest_seconds between 0 and 900),
  notes text not null default '',
  unique (id, org_id),
  unique (version_id, position) deferrable initially deferred,
  foreign key (version_id, org_id) references public.workout_plan_versions(id, org_id) on delete cascade
);

create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  student_id uuid not null,
  version_id uuid not null,
  status public.session_status not null default 'in_progress',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (id, org_id),
  check (status <> 'finished' or finished_at is not null),
  foreign key (org_id, student_id) references public.organization_members(org_id, user_id),
  foreign key (version_id, org_id) references public.workout_plan_versions(id, org_id)
);
create index on public.workout_sessions(student_id, started_at desc);
create unique index one_open_session_per_student on public.workout_sessions(student_id) where status = 'in_progress';

-- Desempenho realizado fica separado da prescrição (workout_plan_items não é alterado pelo aluno)
create table public.exercise_set_logs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null,
  org_id uuid not null,
  item_id uuid not null,
  set_number int not null check (set_number between 1 and 50),
  done boolean not null default false,
  performed_load_kg numeric(6,2) check (performed_load_kg >= 0),
  performed_reps int check (performed_reps between 0 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, item_id, set_number),
  foreign key (session_id, org_id) references public.workout_sessions(id, org_id) on delete cascade,
  foreign key (item_id, org_id) references public.workout_plan_items(id, org_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  org_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  meta jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index on public.audit_logs(org_id, created_at desc);

-- ===== Funções auxiliares (security definer evita recursão de RLS) =====
create function public.is_superadmin() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select p.is_superadmin from public.profiles p where p.id = auth.uid()), false) $$;

create function public.is_org_member(_org uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organization_members m where m.org_id = _org and m.user_id = auth.uid() and m.active) $$;

create function public.org_role_of(_org uuid) returns public.org_role language sql stable security definer set search_path = '' as $$
  select m.role from public.organization_members m where m.org_id = _org and m.user_id = auth.uid() and m.active $$;

create function public.is_org_staff(_org uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.org_role_of(_org) in ('owner','manager'), false) $$;

create function public.is_trainer_of(_org uuid, _student uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trainer_student_relationships r
    where r.org_id = _org and r.trainer_id = auth.uid() and r.student_id = _student and r.active)
    and public.is_org_member(_org) $$;

create function public.can_edit_plan(_plan uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workout_plans p where p.id = _plan and public.is_org_member(p.org_id)
    and (public.is_org_staff(p.org_id) or p.trainer_id = auth.uid())) $$;

create function public.can_manage_version(_v uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workout_plan_versions v where v.id = _v and public.can_edit_plan(v.plan_id)) $$;

create function public.student_can_read_version(_v uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workout_plan_versions v join public.workout_plans p on p.id = v.plan_id
    where v.id = _v and v.status = 'published' and p.student_id = auth.uid() and public.is_org_member(p.org_id)) $$;

create function public.plan_has_published(_plan uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workout_plan_versions v where v.plan_id = _plan and v.status = 'published') $$;

create function public.session_owner(_s uuid) returns uuid language sql stable security definer set search_path = '' as $$
  select s.student_id from public.workout_sessions s where s.id = _s $$;

create function public.session_in_progress(_s uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.workout_sessions s where s.id = _s and s.status = 'in_progress') $$;

create function public.can_see_profile(_uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select _uid = auth.uid() or public.is_superadmin()
    or exists (select 1 from public.organization_members m where m.user_id = _uid and m.active
         and (public.is_org_staff(m.org_id) or public.is_trainer_of(m.org_id, m.user_id)))
    or exists (select 1 from public.trainer_student_relationships r
         where r.student_id = auth.uid() and r.trainer_id = _uid and r.active) $$;

create function public.write_audit(_org uuid, _action text, _entity text, _entity_id text, _meta jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_logs(actor_id, org_id, action, entity, entity_id, meta)
  values (auth.uid(), _org, _action, _entity, _entity_id, coalesce(_meta, '{}')) $$;

-- ===== Triggers =====
create function public.trg_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger touch before update on public.profiles for each row execute function public.trg_touch();
create trigger touch before update on public.organizations for each row execute function public.trg_touch();
create trigger touch before update on public.workout_plans for each row execute function public.trg_touch();
create trigger touch before update on public.exercise_set_logs for each row execute function public.trg_touch();

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name', ''), 120));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.trg_versions_guard() returns trigger language plpgsql as $$
begin
  if new.plan_id <> old.plan_id or new.org_id <> old.org_id or new.version <> old.version then
    raise exception 'immutable_columns'; end if;
  if old.status = 'draft' and new.status not in ('draft','published') then raise exception 'invalid_transition'; end if;
  if old.status = 'published' and new.status not in ('published','archived') then raise exception 'invalid_transition'; end if;
  if old.status = 'archived' and new.status <> 'archived' then raise exception 'invalid_transition'; end if;
  if old.status = 'draft' and new.status = 'published' then new.published_at := now(); end if;
  return new;
end $$;
create trigger guard before update on public.workout_plan_versions for each row execute function public.trg_versions_guard();

create function public.trg_items_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare vstatus public.plan_status; eorg uuid;
begin
  select status into vstatus from public.workout_plan_versions where id = coalesce(new.version_id, old.version_id);
  if not found then
    if tg_op = 'DELETE' then return old; end if;  -- exclusão em cascata de versão rascunho
    raise exception 'version_not_found';
  end if;
  if vstatus <> 'draft' then raise exception 'version_not_editable'; end if;
  if tg_op in ('INSERT','UPDATE') then
    select org_id into eorg from public.exercise_library where id = new.exercise_id;
    if eorg is not null and eorg <> new.org_id then raise exception 'exercise_wrong_org'; end if;
  end if;
  return coalesce(new, old);
end $$;
create trigger guard before insert or update or delete on public.workout_plan_items for each row execute function public.trg_items_guard();

create function public.trg_sessions_guard() returns trigger language plpgsql as $$
begin
  if old.status <> 'in_progress' then raise exception 'session_closed'; end if;
  if new.status = 'finished' then new.finished_at := now(); end if;  -- duração vem do servidor
  return new;
end $$;
create trigger guard before update on public.workout_sessions for each row execute function public.trg_sessions_guard();

create function public.trg_logs_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.workout_sessions s join public.workout_plan_items i on i.version_id = s.version_id
                 where s.id = new.session_id and i.id = new.item_id and s.org_id = new.org_id) then
    raise exception 'item_not_in_session'; end if;
  return new;
end $$;
create trigger guard before insert or update on public.exercise_set_logs for each row execute function public.trg_logs_guard();

-- ===== Funções de negócio (RPC) =====
create function public.create_organization(_name text) returns uuid language plpgsql security definer set search_path = '' as $$
declare oid uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.organizations(name) values (trim(_name)) returning id into oid;
  insert into public.organization_members(org_id, user_id, role) values (oid, auth.uid(), 'owner');
  perform public.write_audit(oid, 'organization.create', 'organization', oid::text, '{}');
  return oid;
end $$;

create function public.admin_set_org_status(_org uuid, _status public.org_status) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_superadmin() then raise exception 'forbidden'; end if;
  update public.organizations set status = _status where id = _org;
  perform public.write_audit(_org, 'organization.set_status', 'organization', _org::text, jsonb_build_object('status', _status));
end $$;

create function public.create_workout_version(_plan uuid) returns uuid language plpgsql set search_path = '' as $$
declare p record; nv int; vid uuid; src uuid;
begin
  select * into p from public.workout_plans where id = _plan;
  if not found then raise exception 'plan_not_found'; end if;
  select coalesce(max(version), 0) + 1 into nv from public.workout_plan_versions where plan_id = _plan;
  select id into src from public.workout_plan_versions where plan_id = _plan order by version desc limit 1;
  insert into public.workout_plan_versions(plan_id, org_id, version) values (_plan, p.org_id, nv) returning id into vid;
  if src is not null then
    insert into public.workout_plan_items(version_id, org_id, position, exercise_id, sets, reps, prescribed_load_kg, rest_seconds, notes)
    select vid, org_id, position, exercise_id, sets, reps, prescribed_load_kg, rest_seconds, notes
    from public.workout_plan_items where version_id = src;
  end if;
  return vid;
end $$;

create function public.publish_workout_version(_version uuid) returns void language plpgsql set search_path = '' as $$
declare v record;
begin
  select * into v from public.workout_plan_versions where id = _version;
  if not found then raise exception 'version_not_found'; end if;
  if v.status <> 'draft' then raise exception 'version_not_draft'; end if;
  if not exists (select 1 from public.workout_plan_items i where i.version_id = _version) then raise exception 'version_empty'; end if;
  update public.workout_plan_versions set status = 'archived' where plan_id = v.plan_id and status = 'published';
  update public.workout_plan_versions set status = 'published' where id = _version;
end $$;

-- ===== Privilégios =====
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
revoke all on function public.write_audit(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.create_organization(text), public.admin_set_org_status(uuid, public.org_status),
  public.create_workout_version(uuid), public.publish_workout_version(uuid) from public, anon;
grant execute on function public.create_organization(text), public.admin_set_org_status(uuid, public.org_status),
  public.create_workout_version(uuid), public.publish_workout_version(uuid) to authenticated;

-- Colunas sensíveis não são atualizáveis pelo cliente
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;
revoke insert, update, delete on public.organizations from authenticated;
grant update (name) on public.organizations to authenticated;
revoke update on public.organization_members from authenticated;
grant update (role, active) on public.organization_members to authenticated;
revoke update on public.trainer_student_relationships from authenticated;
grant update (active) on public.trainer_student_relationships to authenticated;
revoke update on public.workout_plans from authenticated;
grant update (name, goal, notes, archived) on public.workout_plans to authenticated;
revoke update on public.workout_plan_versions from authenticated;
grant update (status) on public.workout_plan_versions to authenticated;
revoke update on public.workout_sessions from authenticated;
grant update (status) on public.workout_sessions to authenticated;
revoke update on public.exercise_set_logs from authenticated;
grant update (done, performed_load_kg, performed_reps) on public.exercise_set_logs to authenticated;
revoke insert, update, delete on public.audit_logs from authenticated;
revoke insert, delete on public.profiles from authenticated;

-- ===== RLS =====
alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.trainer_student_relationships enable row level security;
alter table public.exercise_library enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_plan_versions enable row level security;
alter table public.workout_plan_items enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.exercise_set_logs enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (public.can_see_profile(id));
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy orgs_select on public.organizations for select to authenticated using (public.is_org_member(id) or public.is_superadmin());
create policy orgs_update on public.organizations for update to authenticated using (public.is_org_staff(id)) with check (public.is_org_staff(id));

create policy members_select on public.organization_members for select to authenticated
  using (user_id = auth.uid() or public.is_org_staff(org_id) or public.is_trainer_of(org_id, user_id) or public.is_superadmin());
create policy members_insert on public.organization_members for insert to authenticated
  with check (public.is_org_staff(org_id) and role in ('manager','trainer','student'));
create policy members_update on public.organization_members for update to authenticated
  using (public.is_org_staff(org_id) and role <> 'owner') with check (public.is_org_staff(org_id) and role <> 'owner');

create policy rel_select on public.trainer_student_relationships for select to authenticated
  using (public.is_org_staff(org_id) or trainer_id = auth.uid() or student_id = auth.uid());
create policy rel_insert on public.trainer_student_relationships for insert to authenticated with check (public.is_org_staff(org_id));
create policy rel_update on public.trainer_student_relationships for update to authenticated
  using (public.is_org_staff(org_id)) with check (public.is_org_staff(org_id));

create policy ex_select on public.exercise_library for select to authenticated using (org_id is null or public.is_org_member(org_id));
create policy ex_insert on public.exercise_library for insert to authenticated
  with check ((org_id is null and public.is_superadmin())
    or (org_id is not null and public.org_role_of(org_id) in ('owner','manager','trainer') and created_by = auth.uid()));
create policy ex_update on public.exercise_library for update to authenticated
  using ((org_id is null and public.is_superadmin()) or (org_id is not null and public.org_role_of(org_id) in ('owner','manager','trainer')))
  with check ((org_id is null and public.is_superadmin()) or (org_id is not null and public.org_role_of(org_id) in ('owner','manager','trainer')));
create policy ex_delete on public.exercise_library for delete to authenticated
  using ((org_id is null and public.is_superadmin()) or (org_id is not null and public.org_role_of(org_id) in ('owner','manager','trainer')));

-- Superadmin NÃO tem acesso a planos, sessões e logs de treino (dados de saúde dos alunos).
create policy plans_select on public.workout_plans for select to authenticated
  using ((public.is_org_member(org_id) and (public.is_org_staff(org_id) or trainer_id = auth.uid()))
    or (student_id = auth.uid() and public.is_org_member(org_id) and public.plan_has_published(id)));
create policy plans_insert on public.workout_plans for insert to authenticated
  with check (trainer_id = auth.uid() and public.org_role_of(org_id) in ('owner','manager','trainer')
    and (public.is_org_staff(org_id) or public.is_trainer_of(org_id, student_id)));
create policy plans_update on public.workout_plans for update to authenticated
  using (public.can_edit_plan(id)) with check (public.can_edit_plan(id));

create policy versions_select on public.workout_plan_versions for select to authenticated
  using (public.can_edit_plan(plan_id) or public.student_can_read_version(id));
create policy versions_insert on public.workout_plan_versions for insert to authenticated
  with check (public.can_edit_plan(plan_id) and status = 'draft');
create policy versions_update on public.workout_plan_versions for update to authenticated
  using (public.can_edit_plan(plan_id)) with check (public.can_edit_plan(plan_id));
create policy versions_delete on public.workout_plan_versions for delete to authenticated
  using (public.can_edit_plan(plan_id) and status = 'draft');

create policy items_select on public.workout_plan_items for select to authenticated
  using (public.can_manage_version(version_id) or public.student_can_read_version(version_id));
create policy items_insert on public.workout_plan_items for insert to authenticated with check (public.can_manage_version(version_id));
create policy items_update on public.workout_plan_items for update to authenticated
  using (public.can_manage_version(version_id)) with check (public.can_manage_version(version_id));
create policy items_delete on public.workout_plan_items for delete to authenticated using (public.can_manage_version(version_id));

create policy sessions_select on public.workout_sessions for select to authenticated
  using (student_id = auth.uid() or public.is_org_staff(org_id) or public.is_trainer_of(org_id, student_id));
create policy sessions_insert on public.workout_sessions for insert to authenticated
  with check (student_id = auth.uid() and status = 'in_progress' and public.is_org_member(org_id)
    and public.student_can_read_version(version_id));
create policy sessions_update on public.workout_sessions for update to authenticated
  using (student_id = auth.uid() and status = 'in_progress') with check (student_id = auth.uid());

create policy logs_select on public.exercise_set_logs for select to authenticated
  using (public.session_owner(session_id) = auth.uid() or public.is_org_staff(org_id)
    or public.is_trainer_of(org_id, public.session_owner(session_id)));
create policy logs_insert on public.exercise_set_logs for insert to authenticated
  with check (public.session_owner(session_id) = auth.uid() and public.session_in_progress(session_id));
create policy logs_update on public.exercise_set_logs for update to authenticated
  using (public.session_owner(session_id) = auth.uid() and public.session_in_progress(session_id))
  with check (public.session_owner(session_id) = auth.uid());

create policy audit_select on public.audit_logs for select to authenticated
  using (public.is_superadmin() or (org_id is not null and public.is_org_staff(org_id)));
