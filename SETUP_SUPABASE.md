# Como ligar o Evolix.fit ao Supabase (passo a passo)

O site (GitHub Pages) só mostra a tela. Quem guarda os dados e faz o login é o Supabase, um serviço separado e gratuito para começar.
**Aviso:** o SQL abaixo foi escrito mas nunca foi executado. Use um projeto NOVO de teste e, se algum passo der erro, copie a mensagem e me envie.

1. Crie uma conta em supabase.com e clique em **New project**. Guarde a senha do banco num local seguro (não no GitHub).
2. No menu esquerdo abra **SQL Editor > New query**. Para cada arquivo abaixo, abra no Bloco de Notas, copie tudo, cole e clique **Run**, nesta ordem:
   1. `supabase/migrations/20261022000001_core_schema.sql`
   2. `supabase/migrations/20261022000002_security_hardening.sql`
   3. `supabase/seed.sql`
   Cada um deve terminar com "Success". Se aparecer erro vermelho, pare e me envie a mensagem.
3. (Opcional, recomendado) Rode `supabase/tests/rls_isolation.sql` na mesma tela. Ele faz testes de segurança e desfaz tudo no final. Sucesso = a mensagem `Testes de isolamento/permissões: OK` aparece em Messages.
4. Vá em **Authentication > URL Configuration**: em **Site URL** coloque o endereço do seu site (`https://SEU-USUARIO.github.io/evolix-fit/`). Salve.
   Para testar sem e-mail de confirmação: **Authentication > Providers > Email** e desligue "Confirm email" (ligue de novo antes de usar com pessoas reais).
5. Vá em **Project Settings > API**. Copie a **Project URL** e a chave **anon public**.
   **NUNCA copie a `service_role`.** A anon é pública por natureza: quem protege os dados são as regras (RLS) do banco.
6. No GitHub, abra `index.html`, clique no lápis (editar) e preencha as duas linhas no começo do script:
   `const SUPABASE_URL = "https://xxxx.supabase.co";`
   `const SUPABASE_ANON_KEY = "sua-chave-anon";`
   Clique em **Commit changes**. Espere 1 a 2 minutos e abra o site.
   (Alternativa sem editar o arquivo: abra o site, ele mostra uma tela para colar a URL e a chave. Isso fica salvo só naquele navegador.)

## Primeiro uso
1. Crie uma conta (aba Conta > criar organização) com o futuro dono da academia ou o personal.
2. Peça a cada aluno que crie conta e envie o **ID** que aparece na aba Conta.
3. Em **Equipe e alunos**, cole o ID, escolha Aluno e clique Adicionar. Se for personal separado do dono, vincule o aluno a ele.
4. Em **Treinos**, crie o treino, adicione exercícios e publique. O aluno vê em **Meu treino**.

Use somente dados fictícios até a validação de segurança.
