# Matriz de rastreabilidade 2.3.5 RC

| Requisito | Implementação | Teste |
|---|---|---|
| Corrigir `DisplayName` ausente | acesso por `Get-AutoRunnerPropertyValue` | `V22-Regression-QA.py` |
| Detectar instalação personalizada | detector multicamada e seleção manual | regressão + QA Windows |
| Abrir sem CMD | launcher PE GUI | PE QA + GUI smoke |
| Instalar com arquivo único | Setup autoextraível | `Setup-Installer-QA.py` |
| Menu Iniciar e Desktop opcional | `Setup-Wizard.ps1` | QA Windows |
| Reparar e desinstalar | Setup local + ARP | ciclo nativo Windows |
| Tutorial e ajuda | `Show-AutoRunnerTutorial` | GUI smoke/manual |
| Seleção segura dos jobs | Manager + confirmação técnica | Static/Deep/Behavioral |
| Execução única | Task IgnoreNew + mutex | QA nativo/behavioral |
| Segurança SYSTEM | ACL, manifesto e CLI | Adversarial + QA Windows |
| Integridade da release | checksums internos/externos | Package/Setup QA |
| Preservar SQLBackupAndFTP | escopo de remoção restrito | Deep/Adversarial |
