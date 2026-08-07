# ADR-003 — ACL de Controle Total obrigatória na 3.0.0-RC

**Status:** Aceito por decisão explícita de produto  
**Versão-alvo:** 3.0.0-RC

## Decisão

A instalação 3.0.0-RC deverá aplicar **Controle Total (`FullControl`)**, com herança para arquivos e subdiretórios, a todas as identidades abaixo. Não será suficiente `Read`, `ReadAndExecute`, `Write` ou `Modify`.

| Identidade | SID / referência | Direito obrigatório |
|---|---|---|
| `SYSTEM` | `S-1-5-18` | Controle Total |
| `Administradores` / `BUILTIN\Administrators` | `S-1-5-32-544` | Controle Total |
| usuário proprietário/instalador efetivo | SID resolvido em runtime | Controle Total |
| `Users` / `BUILTIN\Users` | `S-1-5-32-545` | Controle Total |
| `Authenticated Users` | `S-1-5-11` | Controle Total |
| `Everyone` / `Todos` | `S-1-1-0` | Controle Total |
| `ALL APPLICATION PACKAGES` / `Todos os Pacotes de Aplicativos` | `S-1-15-2-1` | Controle Total |
| `ALL RESTRICTED APPLICATION PACKAGES` / `Todos os Pacotes de Aplicativos Restritos` | `S-1-15-2-2` | Controle Total |
| `CREATOR OWNER` / `PROPRIETÁRIO CRIADOR` | `S-1-3-0` | Controle Total herdável |
| `OWNER RIGHTS` / `DIREITOS DO PROPRIETÁRIO` | `S-1-3-4` | Controle Total |

A política deverá ser aplicada à pasta de instalação e aos recursos gerenciados pelo AutoRunner que precisem manter o mesmo modelo de acesso. O instalador, reparo e atualizador deverão **revalidar a ACL efetiva** e considerar a operação incompleta caso qualquer ACE obrigatória não possua Controle Total.

A implementação deverá usar SIDs conhecidos sempre que possível, evitando dependência dos nomes localizados do Windows.

## Consequência de segurança aceita

Essa política permite que identidades muito amplas modifiquem arquivos que podem participar de execução privilegiada, inclusive componentes posteriormente executados como `SYSTEM`. Portanto:

1. a árvore de instalação **não é uma trust boundary**;
2. essa ACL **não deverá ser descrita como hardening**;
3. existe risco de alteração local de binários/scripts e, dependendo do fluxo privilegiado, de elevação local de privilégio;
4. o risco deve permanecer visível no threat model, QA e documentação da release;
5. mecanismos de integridade, assinatura e validação de payload continuam úteis, mas **não anulam** o direito local de modificação concedido por esta decisão.

## Razão

A decisão de produto prioriza compatibilidade operacional e acesso irrestrito aos recursos locais do AutoRunner na linha 3.0.0-RC. Ela é intencional e não deverá ser silenciosamente revertida para permissões somente de leitura, execução, escrita ou modificação.
