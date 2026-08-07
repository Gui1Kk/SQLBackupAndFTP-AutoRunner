# ADR-002 — Não escrever diretamente no context.db do SQLBackupAndFTP

**Status:** Aceito

## Decisão

A 3.0.0-RC pode ler snapshot do banco de configuração em modo read-only quando o esquema é reconhecido, mas não cria/edita/exclui jobs escrevendo diretamente no SQLite interno.

## Justificativa

O schema é implementação interna do fornecedor, pode mudar sem aviso, pode possuir invariantes fora do banco e não constitui API pública. Escrita direta pode corromper jobs, credenciais ou estado do serviço.

## Consequência

As capabilities de mutação permanecem falsas até existir mecanismo oficialmente suportado ou tecnicamente validado com contrato estável.
