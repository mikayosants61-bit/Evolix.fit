-- Testes de isolamento/permissões. Executa tudo em uma transação e desfaz no final (rollback).
-- STATUS: escrito, NÃO executado ainda. Rode no SQL Editor do Supabase local ou via: psql -f
-- Falha com "FALHOU: ..." se alguma regra de segurança não valer.
begin;

-- Setup (como postgres): 2 organizações, usuários, vínculos, exercícios, planos
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000a1','trainer.a@teste.local'),
 ('00000000-0000-0000-0000-0000000000a2','student.a@teste.local'),
 ('00000000-0000-0000-0000-0000000000a3','manager.a@teste.local'),
 ('00000000-0000-0000-0000-0000000000b1','trainer.b@teste.local'),
 ('00000000-0000-0000-0000-0000000000b2','student.b@teste.local');
insert into public.organizations(id, name) values
 ('00000000-0000-0000-0000-00000000aaaa','Academia A (teste)'),
 ('00000000-0000-0000-0000-00000000bbbb','Academia B (teste)');
insert into public.organization_members(org_id, user_id, role) values
 ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a1','trainer'),
 ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a2','student'),
 ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a3','manager'),
 ('00000000-0000-0000-0000-00000000bbbb','00000000-0000-0000-0000-0000000000b1','trainer'),
 ('00000000-0000-0000-0000-00000000bbbb','00000000-0000-0000-0000-0000000000b2','student');
insert into public.trainer_student_relationships(org_id, trainer_id, student_id) values
 ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2'),
 ('00000000-0000-0000-0000-00000000bbbb','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b2');
insert into public.exercise_library(id, org_id, name, muscle_group) values
 ('00000000-0000-0000-0000-0000000000e0', null, 'Exercício global (teste)', 'Peito'),
 ('00000000-0000-0000-0000-0000000000eb', '00000000-0000-0000-0000-00000000bbbb', 'Exercício da org B (teste)', 'Costas');
insert into public.workout_plans(id, org_id, trainer_id, student_id, name) values
 ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2','Plano A');
insert into public.workout_plan_versions(id, plan_id, org_id, version) values
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-00000000aaaa',1);
insert into public.workout_plan_items(id, version_id, org_id, position, exercise_id, sets, reps, prescribed_load_kg) values
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-00000000aaaa',0,'00000000-0000-0000-0000-0000000000e0',3,'10',40);

-- T1: personal da org B não enxerga plano da org A
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.workout_plans) <> 0 then raise exception 'FALHOU T1: org B viu plano da org A'; end if;
  if (select count(*) from public.organization_members where org_id = '00000000-0000-0000-0000-00000000aaaa') <> 0 then raise exception 'FALHOU T1b: org B viu membros da org A'; end if;
end $$;
reset role;

-- T2: aluno A não vê o plano enquanto só existe rascunho
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.workout_plans) <> 0 then raise exception 'FALHOU T2: aluno viu plano em rascunho'; end if;
end $$;
reset role;

-- T3: personal A publica; aluno A passa a ver; aluno B continua sem ver
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
set local role authenticated;
select public.publish_workout_version('00000000-0000-0000-0000-0000000000c1');
reset role;

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.workout_plans) <> 1 then raise exception 'FALHOU T3: aluno A não viu o plano publicado'; end if;
  if (select count(*) from public.workout_plan_items) <> 1 then raise exception 'FALHOU T3b: aluno A não viu os itens'; end if;
  if (select count(*) from public.organization_members) <> 1 then raise exception 'FALHOU T3c: aluno viu outros membros'; end if;
end $$;
reset role;

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.workout_plans) <> 0 then raise exception 'FALHOU T3d: aluno B viu plano da org A'; end if;
  -- T4: aluno B não consegue abrir sessão em versão da org A
  begin
    insert into public.workout_sessions(org_id, student_id, version_id)
    values ('00000000-0000-0000-0000-00000000bbbb','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000c1');
    raise exception 'FALHOU T4: aluno B abriu sessão em versão de outra org';
  exception when insufficient_privilege or foreign_key_violation or raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;
end $$;
reset role;

-- T5: versão publicada é imutável (nem o personal consegue editar itens)
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin
    update public.workout_plan_items set sets = 99 where id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'FALHOU T5: item de versão publicada foi editado';
  exception when raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;
end $$;
reset role;

-- T6: aluno A registra sessão; prescrição permanece intacta; duração vem do servidor
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
set local role authenticated;
insert into public.workout_sessions(id, org_id, student_id, version_id) values
 ('00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000c1');
insert into public.exercise_set_logs(session_id, org_id, item_id, set_number, done, performed_load_kg, performed_reps) values
 ('00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000d1',1,true,42.5,9);
do $$ begin
  -- aluno não pode alterar a prescrição (RLS bloqueia: 0 linhas afetadas, ou privilégio negado)
  begin
    update public.workout_plan_items set prescribed_load_kg = 100 where id = '00000000-0000-0000-0000-0000000000d1';
  exception when others then null;
  end;
  -- aluno não pode se promover a superadmin
  begin
    update public.profiles set is_superadmin = true where id = auth.uid();
    raise exception 'FALHOU T6: aluno alterou is_superadmin';
  exception when insufficient_privilege then null;
  end;
end $$;
update public.workout_sessions set status = 'finished' where id = '00000000-0000-0000-0000-0000000000a5';
reset role;
do $$ begin
  if (select prescribed_load_kg from public.workout_plan_items where id = '00000000-0000-0000-0000-0000000000d1') <> 40 then
    raise exception 'FALHOU T6b: prescrição original foi alterada'; end if;
  if (select performed_load_kg from public.exercise_set_logs limit 1) <> 42.5 then
    raise exception 'FALHOU T6c: carga realizada não foi gravada'; end if;
  if (select finished_at from public.workout_sessions where id = '00000000-0000-0000-0000-0000000000a5') is null then
    raise exception 'FALHOU T6d: finished_at não foi definido pelo servidor'; end if;
end $$;

-- T7: personal A não pode usar exercício da org B em um rascunho
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
set local role authenticated;
do $$ declare v uuid; begin
  v := public.create_workout_version('00000000-0000-0000-0000-0000000000f1');
  begin
    insert into public.workout_plan_items(version_id, org_id, position, exercise_id, sets, reps)
    values (v, '00000000-0000-0000-0000-00000000aaaa', 5, '00000000-0000-0000-0000-0000000000eb', 3, '10');
    raise exception 'FALHOU T7: exercício de outra org aceito';
  exception when raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;
end $$;
reset role;

-- T8: gestor A vê só a própria org; trilha de auditoria recusa escrita direta
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.organizations) <> 1 then raise exception 'FALHOU T8: gestor viu outra organização'; end if;
  if (select count(*) from public.organization_members) <> 3 then raise exception 'FALHOU T8b: gestor não viu os 3 membros da própria org'; end if;
  begin
    insert into public.audit_logs(action, entity) values ('x','y');
    raise exception 'FALHOU T8c: escrita direta em audit_logs permitida';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ===== Testes da migration 0002 (T9–T12) =====

-- T9: personal A não consegue mover item para fora de versão publicada (S1/S4)
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
set local role authenticated;
do $$ declare draft uuid; begin
  select id into draft from public.workout_plan_versions where plan_id = '00000000-0000-0000-0000-0000000000f1' and status = 'draft';
  if draft is null then raise exception 'FALHOU T9: pré-condição (rascunho do T7) não encontrada'; end if;
  begin
    update public.workout_plan_items set version_id = draft where id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'FALHOU T9: item saiu da versão publicada';
  exception when insufficient_privilege or raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;

  -- T11: publicar versão vazia é recusado, inclusive por UPDATE direto (S2)
  delete from public.workout_plan_items where version_id = draft;
  begin
    update public.workout_plan_versions set status = 'published' where id = draft;
    raise exception 'FALHOU T11: versão vazia foi publicada';
  exception when raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;
end $$;
reset role;

-- T10: aluno A não consegue fixar started_at/finished_at ao criar sessão (S4)
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin
    insert into public.workout_sessions(org_id, student_id, version_id, started_at)
    values ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000c1', now() - interval '3 hours');
    raise exception 'FALHOU T10: cliente definiu started_at';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- T12: gestor A não consegue registrar um aluno como personal em um vínculo (S3)
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin
    insert into public.trainer_student_relationships(org_id, trainer_id, student_id)
    values ('00000000-0000-0000-0000-00000000aaaa','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000a1');
    raise exception 'FALHOU T12: aluno aceito como personal no vínculo';
  exception when raise_exception then
    if sqlerrm like 'FALHOU%' then raise; end if;
  end;
end $$;
reset role;

do $$ begin raise notice 'Testes de isolamento/permissões: OK'; end $$;
rollback;
