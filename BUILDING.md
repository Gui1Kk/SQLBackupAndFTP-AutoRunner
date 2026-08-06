# Compilação

## Ambiente suportado

A aplicação e os artefatos finais são exclusivamente **Windows x64**.

### Requisitos para Setup e Portable

- Python 3.11 ou superior;
- arquivos nativos x64 já compilados em `native/`;
- PowerShell 5.1 para executar os testes nativos.

### Requisitos para recompilar os launchers nativos

- LLVM/Clang para Windows x64 ou Visual Studio Build Tools 2022;
- Windows SDK;
- os manifestos presentes em `native/`.

### Requisitos para MSI

- Windows x64;
- .NET SDK compatível;
- WiX Toolset v4 (`wix.exe`);
- Python 3;
- Windows PowerShell 5.1.

## 1. Executar QA estático

```powershell
python .\tests\Static-QA.py
python .\tests\Deep-Review.py
python .\tests\Adversarial-Review.py
python .\tests\V22-Regression-QA.py
python .\tests\V221-Regression-QA.py
python .\tests\Behavioral-Model.py
python .\tests\State-Machine-Fuzz.py --iterations 100000 --seed 20260806
```

## 2. Executar QA nativo

Abra Windows PowerShell 5.1 como administrador:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-QA.ps1 -Integration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action GuiSmoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action TutorialSmoke
```

## 3. Gerar Setup e Portable

```powershell
python .\build\Build-Release.py --root . --output .\dist
```

Artefatos esperados:

```text
dist\SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe
dist\SQLBackupAndFTP-AutoRunner-v2.2.1-Portable.zip
dist\RELEASE-MANIFEST.json
```

Cada artefato recebe um arquivo `.sha256.txt`.

## 4. Validar os pacotes

```powershell
python .\tests\Setup-Installer-QA.py .\dist\SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe
python .\tests\Release-Package-QA.py .\dist\SQLBackupAndFTP-AutoRunner-v2.2.1-Portable.zip .\dist\SQLBackupAndFTP-AutoRunner-v2.2.1-Portable.zip.sha256.txt
```

## 5. Gerar MSI x64

Com WiX v4 no PATH:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Build-MSI.ps1 -RunQA
```

Artefato esperado:

```text
dist\SQLBackupAndFTP-AutoRunner-v2.2.1-x64.msi
```

## 6. Assinar a release

A assinatura exige certificado de Code Signing da Alpha Software com chave privada:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Sign-Release.ps1 -Path .\dist\SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe -CertificateThumbprint SEU_THUMBPRINT
```

Nunca coloque certificado, PFX, senha ou chave privada no repositório.

## Critérios de publicação

Uma release só deve ser marcada como estável depois de parser AST sem erro, smoke test da GUI e tutorial, instalação/reparo/remoção em Windows x64, ACL NTFS e Agendador reais, detecção do SQLBackupAndFTP, backup confirmado no histórico e destino, reinicialização real, restauração, hashes e assinatura quando disponível.
