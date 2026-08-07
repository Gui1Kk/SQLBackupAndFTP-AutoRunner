# Limitações conhecidas e gates de homologação — 3.0.0-RC

1. O ambiente de build desta candidata não possui Docker Engine nem PostgreSQL executável; a sintaxe/estrutura do Compose, contratos e código foram validados, mas o stack precisa ser iniciado na VM Windows de homologação.
2. O ambiente de build não executa Windows PowerShell 5.1, WinForms, UAC, ACL NTFS, Task Scheduler ou SQLBackupAndFTP real. Esses testes permanecem obrigatórios.
3. Não foi possível gerar `package-lock.json` neste ambiente porque o registry npm disponível para a sessão não resolveu os pacotes atuais. As dependências diretas estão fixadas em versões exatas, porém a primeira imagem Docker ainda resolve dependências transitivas. Após o primeiro `npm install` em ambiente com registry oficial, gerar e versionar `package-lock.json` e trocar o Dockerfile para `npm ci` é um gate recomendado antes de produção estável.
4. A criação/edição/exclusão remota de jobs do SQLBackupAndFTP não é implementada por escrita direta em `context.db`. A capacidade permanece indisponível até existir API/CLI oficial compatível ou adaptador suportado.
5. A política ACL 3.0.0-RC de `FullControl` amplo foi determinada explicitamente pelo produto e aumenta a superfície de alteração local, inclusive de componentes que podem rodar como `SYSTEM`. O risco é aceito e documentado no ADR-003.
6. A 2.3.5 RC não recebeu homologação real do usuário antes da 3.0.0-RC; portanto correções herdadas de ícone, DPI, ACL, update e uninstall precisam ser retestadas juntamente com a 3.0.


## Auditoria e retenção

A retenção automática da RC cobre outbox/event inbox, entregas de webhook terminalizadas e diagnósticos expirados. A trilha `ar_audit_events` é preservada indefinidamente nesta RC; a política formal de retenção/LGPD deve ser definida pela empresa antes da promoção a estável.
