# PROJECT_STATUS — Evolix.fit

Atualizado em 22/10/2026. Estados: **pendente**, **executado com sucesso**, **falhou**, **bloqueado**. Só o que está comprovado entra como "executado com sucesso".
Detalhes e achados: `EVOLIX_AUDIT.md`.

## Arquivos que existem

| Arquivo | Estado |
|---|---|
| `index.html` (protótipo, `localStorage`) | existe; **não testado em navegador** |
| `supabase/migrations/20261022000001_core_schema.sql` | escrita; execução **bloqueada** (sem Docker/Supabase CLI no ambiente) |
| `supabase/migrations/20261022000002_security_hardening.sql` | escrita nesta etapa; execução **bloqueada** |
| `supabase/tests/rls_isolation.sql` (12 cenários T1–T12) | escrito; execução **bloqueada** |
| `EVOLIX_AUDIT.md` | criado nesta etapa |
| `supabase/config.toml`, `package.json`, `.env.example` | **não existem** (pendente) |

## Etapas

| Etapa | Estado |
|---|---|
| 1. Auditoria dos arquivos | executada (leitura manual) |
| 2. Revisão de segurança | executada (leitura manual). 8 achados; S1–S4, S6, S7 corrigidos na 0002; S5 mitigado; S8 aberto |
| 3. Validação local (`supabase start`, `db reset`, testes RLS) | **bloqueada**: `supabase`, `docker`, `psql` ausentes; nenhum comando foi executado |
| 4. Arquitetura GitHub Pages | recomendação registrada (Vite + React estático); **aguarda sua decisão**, nada migrado |
| 5. Plano incremental | fases abaixo, nenhuma iniciada |

Nenhum teste foi executado. Nenhum resultado de teste é declarado. A sintaxe do SQL não foi validada por ferramenta.

## Próxima ação (no seu computador)

1. Instalar Docker Desktop e Supabase CLI. `supabase init` (cria `config.toml`) e `supabase start`.
2. Confirmar que o destino é **local** (`supabase status`) e rodar `supabase db reset`.
3. Executar `supabase/tests/rls_isolation.sql` e registrar aqui a saída real (esperado: `Testes de isolamento/permissões: OK`).
4. Corrigir falhas e repetir. Só então iniciar a fase 1.

Proibido nesta etapa: `supabase db reset --linked`, `supabase db push`, qualquer comando contra o projeto remoto.

## Plano incremental (nenhuma fase iniciada)

1. Estrutura do frontend e publicação estática (decidir A ou B do audit)
2. Autenticação, perfis e permissões
3. Organizações, academias e vínculos
4. Biblioteca de exercícios e montagem de treinos
5. Publicação e versionamento de treinos
6. Registro de sessões dos alunos
7. Avaliações físicas e gráficos (dados protegidos, consentimento LGPD)
8. Gestão de academias, portfólio e planos
9. Sugestões de IA com revisão do profissional
10. Testes finais, acessibilidade, responsividade, documentação

## Pendências e riscos conhecidos

- Convites de usuários com aceite (S8) e Edge Functions para operações com `service_role`.
- Organização suspensa ainda não bloqueia escrita; limites por plano (trava provisória de 5 organizações por dono).
- Helpers de RLS expostos como RPC para autenticados (S5): mover para schema `private`.
- Decisão de produto: gestores leem sessões de treino dos alunos da organização.
- Textos legais e consentimentos exigem revisão jurídica. Use apenas dados fictícios nos testes.
- Segredos: nunca versionar `service_role`; no frontend estático só URL e chave anon (públicas por natureza).

## Atualização: frontend ligado ao Supabase (22/10/2026)
- `index.html` reescrito: login/cadastro, organização, equipe, vínculos, montador com versões, publicação, sessões do aluno, histórico.
  Estado: escrito; **sintaxe JavaScript verificada com `node --check`**; **não testado em navegador nem contra um Supabase real**.
- `supabase/seed.sql` e `SETUP_SUPABASE.md` criados. Protótipo antigo preservado em `legacy/`.
- Fora do escopo desta versão: avaliações físicas, planos/assinaturas, portfólio, IA, convites com aceite (hoje: colar o ID), gestor/personal vendo sessões dos alunos na interface, recuperação de senha, PWA.
