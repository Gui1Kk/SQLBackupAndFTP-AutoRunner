# SQLBackupAndFTP AutoRunner 3.0.1

## Canal

**Stable**. A 3.0.1 substitui a 3.0.0-RC depois da primeira homologação real da linha 3.x.

## Correções após a 3.0.0-RC

### Política FullControl

A RC validava incorretamente `CREATOR OWNER` como se `S-1-3-0` precisasse aparecer como ACE efetiva em cada arquivo. Na 3.0.1:

- SIDs numéricos são aplicados via `icacls` com o prefixo `*`;
- cada identidade é concedida separadamente para gerar falha/diagnóstico por SID;
- `SYSTEM`, Administrators, owner/installer, Users, Authenticated Users, Everyone, ALL APPLICATION PACKAGES, ALL RESTRICTED APPLICATION PACKAGES e OWNER RIGHTS continuam obrigatoriamente com FullControl efetivo;
- `CREATOR OWNER` usa FullControl `OI/CI/IO` na raiz, ou seja, uma ACE de herança;
- ACLs dos filhos do staging são resetadas para herdar a política normalizada;
- o gate Windows cria subpastas/arquivos reais e valida a política antes de liberar o build.

A política continua sendo um risco deliberadamente aceito de produto porque concede escrita ampla em recursos locais. Scratch de elevação continua restrito a SYSTEM/Administradores.

### Erro “Os tipos de argumento não correspondem”

O defeito vinha de uma interação do PowerShell com `System.Collections.Generic.List<T>` criado por `New-Object` e posteriormente convertido com `@(...)`. A 3.0.1 remove esse padrão de todos os scripts, usa construtores `.new()` e conversões `.ToArray()` onde necessário. Isso corrige tanto o salvamento dos jobs quanto a descoberta SQLite que estava caindo para o fallback CLI.

### Interface e escala

- painel principal usa host rolável e altura mínima para a área de ações;
- janelas continuam DPI-aware;
- configuração usa conteúdo vertical rolável;
- redimensionar ou maximizar não deve reduzir os controles abaixo da altura mínima;
- a tela de configuração foi simplificada.

### Configuração simples

Por padrão aparecem somente os jobs e a situação de cada item. O operador marca o que deve rodar e salva.

A caixa **Usar configurações avançadas** revela:

- tipo de backup;
- atraso e intervalo;
- retentativas;
- espera por serviços;
- limite/reinício da tarefa;
- comportamento após falha;
- rotação/retenção dos logs;
- adição manual por nome.

Quando o modo avançado está desabilitado, o tipo de backup é `Default`, o intervalo mínimo entre boots é zero, retentativas automáticas ficam desligadas e os demais parâmetros internos validados são usados sem exigir conhecimento técnico. Jobs cuja classificação/agendamento não pôde ser confirmada geram apenas uma confirmação agregada antes de salvar.

## Control Plane

A arquitetura da 3.0.0-RC é preservada: MS-A REST/OpenAPI/Better Auth, MS-B GraphQL/Webhooks, MS-C WebSocket, PostgreSQL, dashboard central e Remote Agent outbound-only. Contratos e identificadores de versão passam a informar `3.0.1`.

## Validação necessária

Os gates automatizados não substituem o Windows/SQLBackupAndFTP real. Para fechar a homologação desta Stable, execute `docs/HOMOLOGACAO_3_0_1.md`.
