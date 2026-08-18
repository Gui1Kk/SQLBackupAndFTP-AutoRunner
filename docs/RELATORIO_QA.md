# Relatório de QA 3.0.1

## Estado

Canal: **Stable**. Este relatório descreve os gates automatizados executados durante a construção da 3.0.1 após os defeitos encontrados na homologação real da 3.0.0-RC.

## Correções cobertas

- política FullControl 3.x e semântica inherit-only de CREATOR OWNER;
- erro PowerShell `Os tipos de argumento não correspondem`;
- descoberta SQLite;
- salvamento/reconfiguração dos jobs;
- modo simples/avançado;
- layout adaptativo/scroll;
- mapeamento de todos os parâmetros avançados;
- regressões locais 2.x;
- Control Plane e contratos;
- transação de upgrade e state machine.

## Gates automatizados da linha atual

| Gate | Resultado |
|---|---:|
| Static QA | 66/66 |
| Deep Review | 64/64 |
| Adversarial Review | 35/35 |
| V22 Regression | 58/58 |
| V221 Regression | 11/11 |
| V230 Regression | 39/39 |
| V235 Regression | 57/57 |
| V300 Regression | 10/10 |
| V301 Regression | 36/36 |
| Control Plane Syntax | 5/5 |
| Control Plane Contract | 56/56 |
| Behavioral Model | 9/9 |
| Upgrade directed | 18/18 |
| Upgrade fuzz | 100.000 cenários, 0 falhas |
| State machine directed | 6/6 |
| State machine fuzz | 100.000 cenários, 0 falhas |
| Setup mutation QA | 19/19 |
| Portable Package QA | PASS |
| Source Package QA | PASS |
| Build reprodutível | Setup/Portable/Source idênticos em duas gerações |

## O que o ambiente de build não comprova

- UAC real e ACL NTFS efetiva no computador do cliente;
- aparência WinForms em todos os DPI/resoluções;
- descoberta SQLite contra a instalação específica do SQLBackupAndFTP;
- execução real do job;
- criação do arquivo no destino;
- restauração do backup;
- comportamento após reboot real;
- Docker/PostgreSQL/WSS reais quando esses componentes não estão em execução no ambiente de QA.

Use `docs/HOMOLOGACAO_3_0_1.md` para fechar esses pontos.

## Dependências Node

`package-lock.json` permanece versionado e o CI usa Node 24 + `npm ci`. No ambiente de build desta auditoria, o mirror npm interno não possuía o tarball `zod@4.4.3`, portanto a instalação Node local não foi marcada como aprovada. O GitHub Actions deve ser o gate de resolução do lockfile antes do merge/release remoto.
