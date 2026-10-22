# Evolix.fit

Plataforma de gestão de treinos para academias, personais e alunos.

- **Frontend:** `index.html`, arquivo estático publicado pelo GitHub Pages. Usa `supabase-js` (CDN, versão fixa).
- **Backend:** Supabase (login, PostgreSQL, regras de segurança RLS). Migrations em `supabase/migrations/`.
- **Configuração:** siga `SETUP_SUPABASE.md`. Sem isso, o site só pede a URL e a chave do Supabase.
- **Estado do projeto:** `PROJECT_STATUS.md` e `EVOLIX_AUDIT.md`.
- `legacy/prototipo-local.html`: protótipo antigo, só com dados locais no navegador.

Nunca coloque a chave `service_role` no repositório ou no site. Use apenas dados fictícios até a validação de segurança.
