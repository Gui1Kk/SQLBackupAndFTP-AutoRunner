# Histórico de versões

## 3.0.1 — Stable

Primeira Stable da linha 3.x após homologação da 3.0.0-RC. Mantém o Control Plane, agente outbound e política FullControl da linha 3, corrigindo aplicação/validação de ACL, binder de `List<T>` no PowerShell, descoberta SQLite, layout responsivo e simplificação da configuração local.

## 3.0.0-RC

Release Candidate que introduziu o Control Plane com REST/OpenAPI/Better Auth, GraphQL/Webhooks, WebSocket, PostgreSQL, dashboard e Remote Agent. A homologação Windows encontrou defeitos de ACL, layout e salvamento de jobs que foram corrigidos na 3.0.1.

## 2.3.5 RC

Corrige os defeitos encontrados em Windows na 2.3.0: ACL excessivamente restritiva para execução/Shell, ícones e AppUserModelID, layout/DPI, falso `-1` na remoção. Adiciona detecção multi-origem do SQLBackupAndFTP, fluxo amigável quando o produto não está instalado e atualização integrada com confirmação e SHA-256.

## 2.3.0

Reestruturação de estabilidade que removeu o host .NET local e introduziu upgrade transacional. Testes reais encontraram problemas adicionais de ACL, abertura, identidade visual, DPI/layout e remoção; substituída pela 2.3.5 RC.

## 2.2.6

Tentou corrigir a atualização por renomeação atômica e melhorar o diagnóstico do Portable. Testes reais revelaram acesso negado ao mover a instalação e falha de inicialização do host .NET. Substituída pela linha 2.3.x.

## 2.2.5

Corrigiu manifesto do launcher, mutação do payload e barra lateral. Substituída após falhas reais de atualização.

## 2.2.4

Introduziu host .NET x64 e interface responsiva. Substituída após falhas de manifesto, integridade e layout.

## 2.2.3

Corrigiu falso positivo de ACL e reorganizou a interface.

## 2.2.2

Corrigiu ciclo de vida e primeira pintura da GUI.

## 2.2.1

Corrigiu sintaxe PowerShell 5.1 e navegação do tutorial.

## 2.2.0

Introduziu aplicativo instalado, Setup autoextraível e detecção multicamada.

## 2.1.0 RC

Primeira reestruturação ampla do runner.

## Política

Versões substituídas permanecem apenas para auditoria. Uma release só recebe status estável após os gates locais aplicáveis, Windows x64, instalação, atualização, ACL, tarefa, boot, backup e restauração reais. GitHub-hosted runners não são utilizados; o sentinel de workflow não possui gatilho autônomo e mantém todos os jobs desabilitados.
