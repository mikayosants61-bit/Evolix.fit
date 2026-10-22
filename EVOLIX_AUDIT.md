# EVOLIX_AUDIT — Auditoria de 22/10/2026

Escopo: arquivos que existem de fato no ambiente onde esta auditoria foi feita. Não é o seu repositório local:
confirme no seu computador se há outros arquivos (`git status`, `ls -R`).

## 1. Estado real dos arquivos

| Arquivo | Existe | Observação |
|---|---|---|
| `index.html` (204 linhas) | sim | Protótipo estático, dados em `localStorage`. Não usa Supabase. |
| `README.md` | sim | Descreve corretamente o protótipo (8 linhas, mínimo). |
| `PROJECT_STATUS.md` | sim | Coerente com o estado real; atualizado nesta etapa. |
| `supabase/migrations/20261022000001_core_schema.sql` | sim | Completa em relação ao que promete; tinha falhas (seção 3). |
| `supabase/migrations/20261022000002_security_hardening.sql` | sim (nova) | Corrige S1–S6. |
| `supabase/tests/rls_isolation.sql` | sim | Impersona usuários (`request.jwt.claims` + `set local role authenticated`). 12 cenários. |
| `supabase/config.toml` | **não** | Falta `supabase init`. |
| `package.json`, Vite, React, Next.js | **não** | O frontend atual é só HTML/CSS/JS. |
| `.env.example` | **não** | |

Ferramentas no ambiente da auditoria: `supabase` AUSENTE, `docker` AUSENTE, `psql`/`postgres` AUSENTES, `node`/`npm` presentes,
sem validador de SQL em Python. Sem rede.

## 2. Execução de testes

| Item | Resultado |
|---|---|
| `supabase start` / `supabase db reset` | **BLOQUEADO** (CLI e Docker ausentes). Não executado. |
| `rls_isolation.sql` | **BLOQUEADO** (sem Postgres). Não executado. |
| Validação de sintaxe SQL | **NÃO REALIZADA** (sem parser disponível). A revisão abaixo foi manual. |
| Lint, tipos, build | Não se aplica (não há projeto de build). |

Nenhum resultado de teste é declarado. Para executar no seu computador:
instale Docker Desktop e o Supabase CLI, rode `supabase init` (cria `config.toml`; não sobrescreve as migrations),
`supabase start`, confira que o destino é local, e então `supabase db reset` (local, descartável).
Execute o teste: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/rls_isolation.sql`
(porta padrão do Supabase local; confirme em `supabase status`). Sucesso = mensagem `Testes de isolamento/permissões: OK`.
Não use `--linked`, `db push` nem nada remoto nesta etapa.

## 3. Achados da revisão de segurança (revisão manual do SQL)

| ID | Gravidade | Achado | Estado |
|---|---|---|---|
| S1 | Alta | `UPDATE workout_plan_items SET version_id=...` permitia tirar/mover item de uma versão **publicada** (o guard só olhava a versão nova). Quebrava a imutabilidade da prescrição. | Corrigido na 0002 (guard checa OLD e NEW; coluna `version_id` sem privilégio de UPDATE). Teste T9. Não executado. |
| S2 | Média | Publicar por `UPDATE status` direto ignorava a regra "versão vazia" (só o RPC checava). | Corrigido na 0002 (regra no trigger). Teste T11. Não executado. |
| S3 | Média | Vínculo personal-aluno não validava papéis (aluno poderia ser registrado como personal e ganhar leitura de sessões). | Corrigido na 0002 (trigger). Teste T12. Não executado. |
| S4 | Média | Cliente podia definir `started_at`/`finished_at` ao inserir sessão (duração falsificável) e colunas internas em outras tabelas. | Corrigido na 0002 (privilégios por coluna). Teste T10. Não executado. |
| S5 | Baixa | Funções auxiliares executáveis por `anon`/`public` (viram RPC no PostgREST). | Mitigado na 0002 (execute só para `authenticated`). **Aberto:** autenticados ainda podem chamar `session_owner(id)` etc. como RPC (precisam do UUID). Correção ideal: mover helpers para um schema `private` não exposto. |
| S6 | Média | `create_organization` sem limite (abuso de criação). | Trava provisória de 5 organizações por dono na 0002. Substituir por entitlements administráveis. |
| S7 | Média | Exclusão em cascata e o uso de `NEW` em gatilhos de DELETE dependiam de comportamento do PL/pgSQL. | Reescrito com ramos explícitos por `TG_OP` (parte do S1). |
| S8 | Info | Gestor/owner (`organization_members` INSERT) pode adicionar à sua organização qualquer usuário existente, se souber o UUID; passa a ver nome dele. Não há convite com aceite. | **Aberto.** Resolver com fluxo de convite (função de servidor + aceite do usuário). |

Pontos conferidos e considerados corretos na leitura: RLS habilitada em todas as 11 tabelas; chaves compostas `(org_id, …)`
impedem referência cruzada entre organizações; Superadmin sem política em planos/versões/itens/sessões/logs; `is_superadmin`
sem UPDATE para o cliente; `audit_logs` sem escrita direta; sessão encerrada é imutável; mídia exige licença.

Limitações conhecidas (não são bugs, mas pendências): organização `suspended` ainda não bloqueia escrita; sem avaliações,
consentimentos, assinaturas, convites; staff (owner/manager) lê sessões dos alunos da organização (decisão de produto a confirmar);
exercícios da organização podem ser editados por qualquer personal da organização, e isso afeta o texto mostrado em treinos já publicados
(a prescrição numérica não muda).

## 4. Arquitetura compatível com GitHub Pages (recomendação, nada foi substituído)

GitHub Pages serve apenas arquivos estáticos; o Supabase é um serviço separado (Auth, Postgres, Storage, RLS).
Next.js com renderização no servidor **não** roda no Pages.

Opção A — manter HTML/JS e ligar ao Supabase via `supabase-js` (CDN com versão fixa).
Vantagem: menor mudança, nenhum build. Custo: difícil de testar, escalar e manter com 3 áreas e muitas telas.

Opção B (recomendada para o produto completo) — Vite + React + TypeScript, build estático.
Vantagens: componentes reutilizáveis, tipos, Vitest/Playwright, rotas. Impactos: passa a existir build (GitHub Actions publica `dist/`),
é preciso configurar `base: '/NOME-DO-REPOSITORIO/'` no Vite, e rotas exigem `HashRouter` ou um `404.html` de fallback,
senão recarregar a página em `/aluno/treino` dá 404 no Pages. O `index.html` atual seria preservado como `legacy/` até a migração.

Segurança no frontend estático: tudo no JavaScript é público. A chave **anon** do Supabase é feita para ser pública; quem protege os dados é a RLS.
A `service_role` nunca vai ao navegador nem ao repositório. Operações que precisam dela (convites, administração) exigem Edge Functions do Supabase
com o segredo guardado no Supabase, não no GitHub Pages. Variáveis `VITE_*` embutidas no build são públicas: só coloque nelas URL e chave anon.

Decisão pendente sua: A ou B. Nada foi migrado.

## 5. Próximo passo

1. No seu computador: instalar Docker + Supabase CLI, `supabase init`, `supabase start`, `supabase db reset` (local), rodar `rls_isolation.sql`, e trazer a saída real.
2. Com os testes verdes: fase 1 do plano (estrutura do frontend + publicação estática), depois autenticação, na ordem do seu documento.
