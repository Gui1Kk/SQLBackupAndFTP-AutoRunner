# Estado da implementação 3.0.0-RC

A implementação funcional foi concluída e empacotada a partir da árvore canônica local da 2.3.5 RC + Control Plane 3.0.0-RC.

## Artefatos finais

- Setup: `SQLBackupAndFTP-AutoRunner-Setup-v3.0.0-RC.exe`
  - SHA-256: `96C3358B45267458143D7A2A106525D9010A692B99E98673FDAF1886513B7EDE`
- Portable: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-Portable.zip`
  - SHA-256: `BC83BF582DABF50CD92857EA62EFD94702DD7F8D676305C1EF5D2CBDFEC921C8`
- Source: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-Source.zip`
  - SHA-256: `D736D77F9B89914C4873E6EBFA3346F3B14E0BDE525245EB050FD19AE3C34D48`
- Control Plane: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-ControlPlane.zip`
  - SHA-256: `7F78BC2D56C2E4EC76AB8C2B3E1530261CCB27FF6B3EF8427BD16C559A36AC7C`

## QA executado no ambiente de build

- 464 verificações automatizadas reportadas aprovadas, 0 falhas;
- 100.000 cenários aleatórios do upgrade transacional;
- 100.000 cenários aleatórios da máquina de estados do runner;
- Setup, Portable, Source e Control Plane gerados de forma reproduzível;
- 19 mutações/ataques estruturais contra o Setup rejeitados.

## Limite do conector GitHub usado nesta execução

O conector autenticado disponível nesta sessão permite criar/editar arquivos de texto e objetos Git, mas não oferece importação em massa de uma árvore local ou upload direto de um ZIP local para expandi-lo no repositório. Portanto, este PR NÃO deve ser mergeado enquanto os arquivos vazios do skeleton não forem substituídos pela árvore contida no Source final.

### Importação manual segura

1. Baixe e confira o SHA-256 do Source acima.
2. Extraia `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-Source.zip`.
3. Copie o conteúdo da pasta raiz extraída sobre um checkout da branch `feature/3.0.0-rc-control-plane`.
4. Não copie `dist`, `test-results`, `.env`, segredos ou binários gerados fora da allowlist do Source.
5. Execute os gates descritos no README.
6. Commit/push na mesma branch.
7. Só então marque o PR #3 como pronto e faça merge para `main`.

## Homologação ainda obrigatória

O ambiente de build não executou Docker Engine, Windows PowerShell 5.1, UAC/ACL NTFS reais, Task Scheduler nem SQLBackupAndFTP real. Além disso, a 2.3.5 RC não foi homologada pelo usuário final; as correções herdadas de ícone/taskbar, DPI/layout, updater, detecção, ACL e uninstall continuam no checklist da 3.0.0-RC.
