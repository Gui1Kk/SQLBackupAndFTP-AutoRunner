# Compilação da versão 2.3.5 RC

## Plataformas

Os artefatos finais são exclusivamente Windows x64. A geração dos PE nativos e dos ZIPs pode ser feita em Windows ou Linux com LLVM. Os testes de PowerShell, WinForms, ACL, Agendador e SQLBackupAndFTP exigem Windows x64.

## Dependências

- Python 3.11 ou superior;
- `clang-cl` e `lld-link` no `PATH`;
- Windows PowerShell 5.1 para QA nativo;
- WiX Toolset v4 somente para MSI;
- certificado de Code Signing somente para assinatura.

Nenhum host é compilado na máquina do cliente. Os executáveis nativos são gerados durante o build oficial.

## Build completo

```powershell
python .\build\Build-Native.py --root .
python .\build\Build-Release.py --root . --output .\dist
```

Artefatos:

```text
dist\SQLBackupAndFTP-AutoRunner-Setup-v2.3.5-RC.exe
dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Portable.zip
dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Source.zip
dist\RELEASE-MANIFEST.json
dist\SHA256SUMS.txt
```

Cada artefato possui um `.sha256.txt` próprio.

## QA portátil

```powershell
python .\tests\Static-QA.py
python .\tests\Deep-Review.py
python .\tests\Adversarial-Review.py
python .\tests\V22-Regression-QA.py
python .\tests\V221-Regression-QA.py
python .\tests\V235-Regression-QA.py
python .\tests\Behavioral-Model.py
python .\tests\Upgrade-Transaction-Model.py
python .\tests\State-Machine-Fuzz.py --iterations 100000 --seed 20260806
```

## QA dos pacotes

```powershell
python .\tests\Setup-Installer-QA.py .\dist\SQLBackupAndFTP-AutoRunner-Setup-v2.3.5-RC.exe
python .\tests\Release-Package-QA.py .\dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Portable.zip .\dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Portable.zip.sha256.txt
python .\tests\Source-Package-QA.py .\dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Source.zip .\dist\SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Source.zip.sha256.txt
```

## QA no Windows

Execute em Windows PowerShell 5.1 como administrador:

```powershell
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\Invoke-QA.ps1 -Integration
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action GuiSmoke
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action TutorialSmoke
```

## Reprodutibilidade

`Build-Native.py` fixa o timestamp PE e usa `/Brepro`. `Build-Release.py` ordena entradas, fixa timestamps ZIP e usa uma allowlist de produção. Duas execuções sobre a mesma árvore devem produzir bytes idênticos para Setup, Portable e Source.

## MSI

```powershell
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\build\Build-MSI.ps1 -RunQA
```

O build MSI recompila os três executáveis nativos antes de montar o payload.

## Assinatura

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Sign-Release.ps1 -Path .\dist\SQLBackupAndFTP-AutoRunner-Setup-v2.3.5-RC.exe -CertificateThumbprint SEU_THUMBPRINT
```

Nunca versione PFX, senha, certificado privado ou chave privada.

## Gate de publicação

A release só pode ser promovida após CI verde, instalação limpa, upgrade de versões anteriores, reparo, desinstalação, ACL, Agendador, reinicialização, backup no destino e restauração real.
