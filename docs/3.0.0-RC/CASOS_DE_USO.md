# Casos de uso e fluxos — 3.0.0-RC

## UC-01 — Ver todos os clientes

**Ator:** suporte autorizado.

**Fluxo:** painel consulta MS-B GraphQL → retorna clientes visíveis ao ator com quantidade de máquinas, online/offline, jobs, últimas falhas e versões → operador abre um cliente → GraphQL carrega máquinas e resumo operacional.

**Resultado esperado:** visão central sem RDP e sem consultar manualmente cada servidor.

## UC-02 — Ver jobs de uma máquina

MS-B retorna inventário mais recente com timestamp e origem. O painel deve deixar claro quando o dado está desatualizado porque o agente está offline.

## UC-03 — Executar backup remotamente

1. Operador seleciona job.
2. UI mostra máquina, cliente, job, tipo de backup e impacto.
3. MS-A valida `jobs:execute` e capability.
4. Cria comando assíncrono.
5. MS-C entrega ao agente.
6. Agente executa `SqlBak.Job.Cli.exe` localmente.
7. Eventos de progresso/resultado retornam ao central.
8. UI atualiza em tempo real.
9. Webhook opcional informa AlphaExpress.

## UC-04 — Agente offline

MS-A aceita comando somente se política permitir fila offline. Comando recebe TTL. Quando o agente reconectar antes do TTL, MS-C despacha. Após expiração, o comando vira `expired` sem execução.

## UC-05 — Falha no backup

Agente envia exit code, saída sanitizada, categoria inferida e referências de log permitidas. MS-B mostra timeline e agrupa recorrência por assinatura do erro. O diagnóstico nunca deve enviar senha/token conhecido.

## UC-06 — SQLBackupAndFTP não instalado

Agente registra `sqlBackupAndFTP.present=false`. Painel mostra máquina sem produto e nenhuma operação de job é oferecida. A instalação automática do produto não faz parte do escopo inicial da API, salvo decisão futura explícita.

## UC-07 — Criar job remotamente

MS-A verifica `jobCreate`. Na primeira 3.0.0-RC a expectativa padrão é `false` para SQLBackupAndFTP moderno até existir mecanismo suportado. O painel deve mostrar “não suportado nesta versão do SQLBackupAndFTP” em vez de tentar escrever o banco interno.

## UC-08 — Atualizar AutoRunner remotamente

Operador solicita atualização para uma versão aprovada. O agente usa o mecanismo de atualização verificado existente, preserva identidade e reconecta. O central acompanha `requested → downloading → verified → installing → reconnecting → succeeded/failed`.

## UC-09 — Integração AlphaExpress

AlphaExpress usa API key organizacional com escopos específicos. Pode consultar o MS-A para ações e o MS-B/GraphQL para leitura. Eventos críticos podem chegar por webhook assinado, evitando polling contínuo.

## UC-10 — Revogar máquina

Administrador revoga agente. MS-C encerra a sessão. Novas conexões com a credencial revogada são recusadas. Histórico permanece para auditoria.
