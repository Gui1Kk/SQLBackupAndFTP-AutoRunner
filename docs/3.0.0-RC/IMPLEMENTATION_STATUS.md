# Estado da implementação 3.0.0-RC

A implementação funcional foi concluída e empacotada a partir da árvore canônica local da 2.3.5 RC + Control Plane 3.0.0-RC.

## Artefatos finais

- Setup: `SQLBackupAndFTP-AutoRunner-Setup-v3.0.0-RC.exe`
  - SHA-256: `96C3358B45267458143D7A2A106525D9010A692B99E98673FDAF1886513B7EDE`
- Portable: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-Portable.zip`
  - SHA-256: `BC83BF582DABF50CD92857EA62EFD94702DD7F8D676305C1EF5D2CBDFEC921C8`
- Source: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-Source.zip`
  - SHA-256: `7B8D153F6177CF3D63F6A6C4AA7C2F5DDC9EABFD40EA4421C3783A00E782E6D4`
- Control Plane: `SQLBackupAndFTP-AutoRunner-v3.0.0-RC-ControlPlane.zip`
  - SHA-256: `35210D05F8A268796290D5FBA3FF1F7B4D0C1AEACD8EC006678F3747A0B29ED3`

## QA executado no ambiente de build

- 465 verificações automatizadas reportadas aprovadas, 0 falhas;
- 100.000 cenários aleatórios do upgrade transacional;
- 100.000 cenários aleatórios da máquina de estados do runner;
- Setup, Portable, Source e Control Plane gerados de forma reproduzível;
- 19 mutações/ataques estruturais contra o Setup rejeitados.

## Estado da árvore Git

A árvore funcional da 3.0.0-RC foi importada para a branch de desenvolvimento. Antes do merge em `main`, o gate exige:

- build scripts presentes em `build/`;
- schema PostgreSQL presente em `deploy/postgres/init/`;
- `package-lock.json` versionado e Docker usando `npm ci`;
- QA 3.0.0-RC verde no GitHub Actions;
- ausência de `.env`, segredos, `node_modules`, `dist` e artefatos transitórios.

A homologação real em Windows/Docker/SQLBackupAndFTP continua sendo requisito para promoção da RC a estável, mas não impede que a implementação RC seja integrada à `main` após os gates de código/CI.

## Homologação ainda obrigatória

O ambiente de build não executou Docker Engine, Windows PowerShell 5.1, UAC/ACL NTFS reais, Task Scheduler nem SQLBackupAndFTP real. Além disso, a 2.3.5 RC não foi homologada pelo usuário final; as correções herdadas de ícone/taskbar, DPI/layout, updater, detecção, ACL e uninstall continuam no checklist da 3.0.0-RC.
