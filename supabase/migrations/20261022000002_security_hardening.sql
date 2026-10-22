-- Evolix.fit — migration 0002: correções da revisão de segurança (ver EVOLIX_AUDIT.md, achados S1–S8).
-- STATUS: escrita, NÃO executada contra Postgres/Supabase real.

-- S1: um item podia ser movido para fora de uma versão publicada (UPDATE de version_id), alterando a
--     prescrição publicada. O guard agora verifica a versão ANTIGA e a NOVA, com ramos explícitos por TG_OP
--     (evita depender de NEW/OLD nulos em DELETE).
create or replace function public.trg_items_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare vstatus public.plan_status; eorg uuid;
begin
  if tg_op in ('UPDATE','DELETE') then
    select status into vstatus from public.workout_plan_versions where id = old.version_id;
    if found and vstatus <> 'draft' then raise exception 'version_not_editable'; end if;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    select status into vstatus from public.workout_plan_versions where id = new.version_id;
    if not found then raise exception 'version_not_found'; end if;
    if vstatus <> 'draft' then raise exception 'version_not_editable'; end if;
    select org_id into eorg from public.exercise_library where id = new.exercise_id;
    if eorg is not null and eorg <> new.org_id then raise exception 'exercise_wrong_org'; end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

-- S2: publicar por UPDATE direto de status ignorava a checagem de "versão vazia" que só existia no RPC.
create or replace function public.trg_versions_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.plan_id <> old.plan_id or new.org_id <> old.org_id or new.version <> old.version then
    raise exception 'immutable_columns'; end if;
  if old.status = 'draft' and new.status not in ('draft','published') then raise exception 'invalid_transition'; end if;
  if old.status = 'published' and new.status not in ('published','archived') then raise exception 'invalid_transition'; end if;
  if old.status = 'archived' and new.status <> 'archived' then raise exception 'invalid_transition'; end if;
  if old.status = 'draft' and new.status = 'published' then
    if not exists (select 1 from public.workout_plan_items i where i.version_id = new.id) then
      raise exception 'version_empty'; end if;
    new.published_at := now();
  end if;
  return new;
end $$;

-- S3: vínculo personal-aluno não validava os papéis (um "aluno" podia ser registrado como personal).
create function public.trg_rel_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.organization_members m
                 where m.org_id = new.org_id and m.user_id = new.trainer_id and m.role in ('trainer','manager','owner')) then
    raise exception 'invalid_trainer_role'; end if;
  if not exists (select 1 from public.organization_members m
                 where m.org_id = new.org_id and m.user_id = new.student_id and m.role = 'student') then
    raise exception 'invalid_student_role'; end if;
  return new;
end $$;
create trigger guard before insert on public.trainer_student_relationships for each row execute function public.trg_rel_guard();

-- S4: privilégios por coluna. O cliente não pode escolher started_at/finished_at/status ao criar sessão
--     (a duração registrada viria do cliente), nem mover itens entre versões, nem trocar org/autor.
revoke insert on public.workout_sessions from authenticated;
grant insert (id, org_id, student_id, version_id) on public.workout_sessions to authenticated;
revoke insert on public.exercise_set_logs from authenticated;
grant insert (id, session_id, org_id, item_id, set_number, done, performed_load_kg, performed_reps) on public.exercise_set_logs to authenticated;
revoke update on public.workout_plan_items from authenticated;
grant update (position, exercise_id, sets, reps, prescribed_load_kg, rest_seconds, notes) on public.workout_plan_items to authenticated;
revoke update on public.exercise_library from authenticated;
grant update (name, muscle_group, equipment, instructions, media_url, media_source, media_license) on public.exercise_library to authenticated;
revoke insert on public.workout_plans from authenticated;
grant insert (id, org_id, trainer_id, student_id, name, goal, notes) on public.workout_plans to authenticated;
revoke insert on public.workout_plan_versions from authenticated;
grant insert (id, plan_id, org_id, version) on public.workout_plan_versions to authenticated;

-- S5: funções auxiliares ficavam executáveis por anon/public (e viram endpoints RPC no PostgREST).
revoke execute on function public.is_superadmin(), public.is_org_member(uuid), public.org_role_of(uuid),
  public.is_org_staff(uuid), public.is_trainer_of(uuid, uuid), public.can_edit_plan(uuid), public.can_manage_version(uuid),
  public.student_can_read_version(uuid), public.plan_has_published(uuid), public.session_owner(uuid),
  public.session_in_progress(uuid), public.can_see_profile(uuid) from public, anon;
grant execute on function public.is_superadmin(), public.is_org_member(uuid), public.org_role_of(uuid),
  public.is_org_staff(uuid), public.is_trainer_of(uuid, uuid), public.can_edit_plan(uuid), public.can_manage_version(uuid),
  public.student_can_read_version(uuid), public.plan_has_published(uuid), public.session_owner(uuid),
  public.session_in_progress(uuid), public.can_see_profile(uuid) to authenticated;

-- S6: qualquer usuário autenticado podia criar organizações sem limite. Trava PROVISÓRIA (anti-abuso)
--     até existirem planos/entitlements administráveis (o valor não deve ficar fixo no código definitivo).
create or replace function public.create_organization(_name text) returns uuid language plpgsql security definer set search_path = '' as $$
declare oid uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if (select count(*) from public.organization_members m where m.user_id = auth.uid() and m.role = 'owner') >= 5 then
    raise exception 'organization_limit_reached'; end if;
  insert into public.organizations(name) values (trim(_name)) returning id into oid;
  insert into public.organization_members(org_id, user_id, role) values (oid, auth.uid(), 'owner');
  perform public.write_audit(oid, 'organization.create', 'organization', oid::text, '{}');
  return oid;
end $$;
