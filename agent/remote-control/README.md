# AutoRunner Remote Agent 3.0.0-RC

Agente outbound-only que conecta o AutoRunner instalado ao Control Plane por WSS. Não abre porta de entrada no cliente.

## Enrollment

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutoRunner.RemoteAgent.ps1 -Enroll -BaseUrl https://autorunner.exemplo.local -Token arenr_...
```

O enrollment grava a identidade em HKLM, protege o segredo via DPAPI LocalMachine e instala uma tarefa SYSTEM no boot. O agente anuncia inventário, mantém heartbeat e executa somente comandos tipados e autorizados pelo Control Plane.

Na 3.0.0-RC, `jobRun`, refresh de inventário, diagnóstico resumido e cancelamento cooperativo são suportados. Criação/edição/exclusão de job e auto-update remoto permanecem capability-gated/desabilitados até existir mecanismo suportado e homologado.
