# Suítes de QA

Execute na raiz do projeto:

```bash
python tests/Static-QA.py
python tests/Deep-Review.py
python tests/Adversarial-Review.py
python tests/Behavioral-Model.py
python tests/State-Machine-Fuzz.py --iterations 50000 --seed 20260805
python tests/V22-Regression-QA.py
python build/Build-Release.py
python tests/Setup-Installer-QA.py dist/SQLBackupAndFTP-AutoRunner-Setup-v2.3.5-RC.exe
python tests/Release-Package-QA.py \
  dist/SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Portable.zip \
  dist/SQLBackupAndFTP-AutoRunner-v2.3.5-RC-Portable.zip.sha256.txt
```

Em Windows, como administrador:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-QA.ps1 -Integration
```

As suítes portáveis não substituem testes de Windows Forms, UAC, Registro, ACL NTFS, Agendador, SQLBackupAndFTP, backup ou restauração reais.
