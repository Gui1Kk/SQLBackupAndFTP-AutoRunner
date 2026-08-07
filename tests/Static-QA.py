#!/usr/bin/env python3
"""Static, non-Windows QA for SQLBackupAndFTP AutoRunner.
Does not replace native PowerShell AST or Windows integration tests.
"""
from __future__ import annotations
import hashlib
import json
import re
import sys
from pathlib import Path
from pygments import lex
from pygments.lexers.shell import PowerShellLexer
from pygments.token import Token

ROOT = Path(__file__).resolve().parents[1]
RESULTS: list[dict[str, object]] = []

def add(name: str, passed: bool, detail: str) -> None:
    RESULTS.append({"name": name, "passed": passed, "detail": detail})
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")

def check_brackets(path: Path) -> list[str]:
    stack: list[tuple[str, int]] = []
    errors: list[str] = []
    line = 1
    pairs = {')': '(', ']': '[', '}': '{'}
    for token, value in lex(read(path), PowerShellLexer()):
        if token in Token.Comment or token in Token.Literal.String:
            line += value.count("\n")
            continue
        for char in value:
            if char == "\n":
                line += 1
            elif char in "([{":
                stack.append((char, line))
            elif char in ")]}":
                if not stack or stack[-1][0] != pairs[char]:
                    errors.append(f"linha {line}: fechamento {char} incompatível")
                else:
                    stack.pop()
    errors.extend(f"linha {ln}: {ch} não fechado" for ch, ln in stack)
    return errors

required = [
    "SQLBackupAndFTP-AutoRunner.exe", "README.md", "CHANGELOG.md",
    "assets/AutoRunner.ico", "modules/AutoRunner.Core.psm1",
    "scripts/Manager.ps1", "scripts/Install-SQLBackupAndFTP-Auto.ps1",
    "scripts/Run-SQLBackupAndFTPJob.ps1", "scripts/Uninstall-SQLBackupAndFTP-Auto.ps1",
    "scripts/Export-Diagnostics.ps1", "scripts/Invoke-QA.ps1", "scripts/Setup-Wizard.ps1", "scripts/Msi-Cleanup.ps1",
    "docs/GUIA_DE_USO.md", "docs/DOCUMENTACAO_TECNICA.md", "docs/SEGURANCA.md",
    "docs/PLANO_DE_TESTES.md", "docs/PLANO_DE_USO_E_NEGOCIO.md", "docs/CHECKLIST_PRINTS_PDF.md",
    "docs/MATRIZ_RASTREABILIDADE.md", "docs/NOTAS_DA_VERSAO.md",
    "tests/Deep-Review.py", "tests/Behavioral-Model.py",
    "tests/Adversarial-Review.py", "tests/State-Machine-Fuzz.py", "tests/Release-Package-QA.py",
    "tests/V22-Regression-QA.py", "tests/Setup-Installer-QA.py", "build/Build-Release.py",
    "native/setup.c", "native/launcher.c", "native/msi-bridge.c", "native/setup-base.exe",
    "native/SQLBackupAndFTP-AutoRunner-MsiBridge.exe",
]
missing = [item for item in required if not (ROOT / item).is_file()]
add("Arquivos obrigatórios", not missing, "todos presentes" if not missing else ", ".join(missing))

scripts = sorted([*ROOT.rglob("*.ps1"), *ROOT.rglob("*.psm1")])
all_errors: list[str] = []
for script in scripts:
    for error in check_brackets(script):
        all_errors.append(f"{script.relative_to(ROOT)}: {error}")
add("Balanceamento lexical PowerShell", not all_errors, "sem divergências" if not all_errors else "; ".join(all_errors[:20]))

bad_encoding: list[str] = []
for path in [*scripts, *ROOT.rglob("*.md"), *ROOT.rglob("*.cmd"), *ROOT.rglob("*.bat")]:
    try:
        text = read(path)
        if "\x00" in text:
            bad_encoding.append(f"{path.relative_to(ROOT)} contém NUL")
    except Exception as exc:
        bad_encoding.append(f"{path.relative_to(ROOT)}: {exc}")
add("UTF-8 e ausência de NUL", not bad_encoding, "arquivos textuais legíveis" if not bad_encoding else "; ".join(bad_encoding))

missing_bom = [str(path.relative_to(ROOT)) for path in scripts if not path.read_bytes().startswith(b"\xef\xbb\xbf")]
add("PowerShell com UTF-8 BOM", not missing_bom, "compatível com Windows PowerShell 5.1" if not missing_bom else ", ".join(missing_bom))

corpus = "\n".join(read(p) for p in scripts)
for label, pattern in {
    "Sem serviço legado fixo": r"SQLBackupAndFTP Client Service",
    "Sem seleção silenciosa NoPrompt": r"\-NoPrompt",
    "Sem validação StartsWith insegura antiga": r"StartsWith\(\$programDataDir",
    "Sem filtro rígido JobType=1": r"WHERE\s+JobType\s*=\s*1",
    "Sem TODO/FIXME pendente": r"(?im)\b(?:TODO|FIXME|HACK)\b",
    "Sem conversão booleana insegura do manifesto": r"\[bool\]\$config\.Security\.EnforceManifest",
    "Sem retry não condicionado por código da CLI": r"(?s)CLI retornou código.*?continue\s*$",
}.items():
    found = re.findall(pattern, corpus)
    add(label, not found, "padrão ausente" if not found else f"{len(found)} ocorrência(s)")

module = read(ROOT / "modules/AutoRunner.Core.psm1")
runner = read(ROOT / "scripts/Run-SQLBackupAndFTPJob.ps1")
installer = read(ROOT / "scripts/Install-SQLBackupAndFTP-Auto.ps1")
uninstaller = read(ROOT / "scripts/Uninstall-SQLBackupAndFTP-Auto.ps1")
manager = read(ROOT / "scripts/Manager.ps1")
setup_wizard = read(ROOT / "scripts/Setup-Wizard.ps1")
msi_builder = read(ROOT / "build/Build-MSI.ps1")
version_parts = tuple(int(x) for x in read(ROOT / "VERSION").strip().split("."))
is_v3 = version_parts[0] >= 3

requirements = {
    "Tarefa recebe SupportDir": "Join-AutoRunnerProcessArguments" in module and "'-SupportDir',$SupportDir" in module,
    "Tarefa usa SYSTEM": "-UserId 'SYSTEM'" in module,
    "Tarefa ignora instância simultânea": "MultipleInstances = 'IgnoreNew'" in module,
    "ACL de produto segue política da versão": ((is_v3 and "Set-AutoRunnerProductFullControlAcl" in module and "S-1-1-0" in module and "S-1-15-2-1" in module and "S-1-15-2-2" in module) or ((not is_v3) and "*S-1-5-32-545:RX" in module and "Get-AutoRunnerUnsafeAclEntries" in module)),
    "Manifesto validado no runner": "Test-AutoRunnerManifest" in runner,
    "Mutex abandonado tratado": "AbandonedMutexException" in runner,
    "Retentativas implementadas": "RetryCount" in runner and "for ($attempt" in runner,
    "Falha individual não gera throw": "Execução interrompida pela opção Parar" in runner,
    "Intervalo individual por job": "jobInterval" in runner and "LastSuccessfulRunUtc" in runner,
    "Artefato de job inclui hash": "Get-AutoRunnerJobArtifactName" in runner and "Get-AutoRunnerStringHash" in module,
    "JSON atômico validado": "ConvertFrom-Json" in module and "File]::Replace" in module,
    "Rollback presente": "Restore-Rollback" in installer,
    "Jobs duplicados recusados": "Job duplicado na seleção" in installer,
    "Seleção técnica confirmada": "ConfirmedByTechnician" in installer and "ConfirmedByTechnician=$true" in manager,
    "Reparse point recusado": "ReparsePoint" in module and "ReparsePoint" in uninstaller,
    "Remoção preserva SQLBackupAndFTP": "Os jobs e as configurações do SQLBackupAndFTP não foram alterados" in uninstaller,
    "Interface possui Testar": "Testar backup agora" in manager,
    "Interface possui diagnóstico": "Exportar diagnóstico" in manager,
    "Interface possui reparo": "Reparar automação" in manager and "Reparar aplicativo" in manager,
    "Estado global recuperável": "backupPath" in module and "corruptPath" in module,
    "Estado individual isolável": "Read-JobStateSafe" in runner,
    "Todos ignorados encerram processo sem falha": "LastExitCode = 12" in runner and "exit 0" in runner,
    "Validação inclui registro e atalho": "Entrada em Aplicativos instalados" in module and "Atalho do Menu Iniciar" in module,
    "Rollback restaura integrações": "Register-AutoRunnerUninstallEntry" in installer and "New-AutoRunnerShortcut" in installer,
    "Launcher executável sem console": (ROOT / "SQLBackupAndFTP-AutoRunner.exe").is_file() and (ROOT / "SQLBackupAndFTP-AutoRunner.exe").read_bytes()[:2] == b"MZ" and "WindowStyle = 'Hidden'" in manager,
    "Elevação ocorre somente em operações administrativas": "-Elevated" in manager and "if ($Elevated -and -not (Test-AutoRunnerAdministrator))" in manager,
    "Mutex concorrente é condição normal": "Outra execução já está ativa" in runner and re.search(r"Outra execução já está ativa[\s\S]{0,300}?exit 0", runner) is not None,
    "Confirmação técnica não é promovida automaticamente": "$legacyConfirmationDefault = ([int]$schema -lt 3)" in module and "-Default $legacyConfirmationDefault" in module,
    "Reparse point ancestral é recusado": "Test-AutoRunnerPathHasReparsePoint" in module,
    "Dados operacionais seguem política ACL da versão": ((is_v3 and "Set-AutoRunnerProductFullControlAcl" in module and "Test-AutoRunnerProductFullControlAcl" in module) or ((not is_v3) and "*S-1-5-32-545:$readFlags" in module and "Get-AutoRunnerUnsafeAclEntries -Path $sensitivePath" in module)),
    "Schema futuro é recusado": "é mais novo que o suportado" in module and "bootstrap $bootstrapSchema é mais novo" in runner,
    "Configuração operacional centralizada": "function Test-AutoRunnerConfiguration" in module and "RequireSecurityHashes" in runner,
    "Integridade é obrigatória": "$new.Security.EnforceManifest = $true" in module and "Hash do manifesto ausente ou inválido" in runner,
    "Módulo validado antes da importação no runner": runner.find("Get-FileHash -LiteralPath $modulePath") < runner.find("Import-Module $modulePath"),
    "CLI recusada em diretório inseguro": "Test-AutoRunnerExecutionPathSecurity" in runner and "exitCode=23" in runner,
    "Pacote oficial exige checksum": "SHA256SUMS.txt ausente. Use um pacote oficial íntegro" in installer,
    "Reparo aceita fonte instalada validada": "Fonte instalada validada pelo manifesto" in installer,
    "Validação disponível na interface": "Validar instalação" in manager and "Invoke-ValidateCore" in manager,
    "Reparo disponível em instalação incompleta": "HasConfiguration" in manager and "$btnRepair.Enabled=$s.Installed.HasConfiguration" in manager,
    "Teste manual concorrente não simula sucesso": "else{exit 13}" in runner,
    "Manifesto rejeita traversal antes de normalizar": "$parts -contains '..'" in module and "TrimStart('./')" not in module,
    "Checksum rejeita todo arquivo não declarado": "Cada arquivo do pacote, sem exceções silenciosas" in module and r"\.(tmp|bak)" not in module[module.find("function Test-AutoRunnerPackageChecksums"):module.find("function Get-AutoRunnerExecutablePathFromCommandLine")],
    "ACL da CLI verifica ancestrais": "Get-AutoRunnerUnsafeAclEntries -Path $ancestor -CurrentOnly" in module,
    "Evidência de falha remove ACL ampla": "SQLBackupAndFTPAuto-InstallFailures" in installer and "*S-1-5-11" in installer,
    "Manager não expõe ações sem implementação": "'Install','Reconfigure'" not in manager.splitlines()[3],
    "Detecção do Registro tolera DisplayName ausente": "$item.DisplayName" not in module and "Get-AutoRunnerPropertyValue -InputObject $item -Name 'DisplayName'" in module,
    "Instalador protege pasta da aplicação": "Protect-ApplicationDirectory -Path $Destination" in setup_wizard and "Test-AutoRunnerExecutionPathSecurity" in setup_wizard,
    "Instalador diferencia EXE e MSI": "InstallTechnology='EXE'" in setup_wizard and 'InstallTechnology" Value="MSI' in msi_builder,
    "Manager mantém aplicativo por tecnologia": "Start-AutoRunnerApplicationMaintenance" in manager and "MsiProductCode" in module,
    "MSI remove automação antes dos arquivos": "CleanupAutomation" in msi_builder and 'Before="RemoveFiles"' in msi_builder,
    "MSI preserva automação durante upgrade": "NOT UPGRADINGPRODUCTCODE" in msi_builder,
    "Setup usa diretório temporário privado": "ConvertStringSecurityDescriptorToSecurityDescriptorW" in read(ROOT / "native/setup.c") and "BCryptGenRandom" in read(ROOT / "native/setup.c"),
}
for name, condition in requirements.items():
    add(name, condition, "implementado" if condition else "não localizado")

# Runtime files declared by installer must exist.
match = re.search(r"\$runtimeFiles\s*=\s*@\((.*?)\n\s*\)", installer, re.S)
refs: list[str] = []
if match:
    refs = [m.replace("\\", "/") for m in re.findall(r"'([^']+)'", match.group(1))]
missing_refs = [ref for ref in refs if not (ROOT / ref).is_file()]
add("Arquivos declarados pelo instalador", bool(refs) and not missing_refs,
    f"{len(refs)} referências válidas" if refs and not missing_refs else f"ausentes: {missing_refs}")

# Duplicate PowerShell function names within each file usually indicate accidental overwrite.
function_issues: list[str] = []
for path in scripts:
    names = re.findall(r"(?im)^\s*function\s+([\w-]+)", read(path))
    dup = sorted({n.lower() for n in names if sum(1 for x in names if x.lower() == n.lower()) > 1})
    if dup:
        function_issues.append(f"{path.relative_to(ROOT)}: {', '.join(dup)}")
add("Sem funções duplicadas por arquivo", not function_issues, "nenhuma" if not function_issues else "; ".join(function_issues))

ico = (ROOT / "assets/AutoRunner.ico").read_bytes()
add("Ícone ICO válido no cabeçalho", ico[:4] == b"\x00\x00\x01\x00", f"{len(ico)} bytes")

# Create reproducible static report with hashes.
hashes = {}
for path in sorted(p for p in ROOT.rglob("*") if p.is_file() and "test-results" not in p.parts):
    hashes[str(path.relative_to(ROOT)).replace("\\", "/")] = hashlib.sha256(path.read_bytes()).hexdigest().upper()
report = {
    "tool": "Static-QA.py",
    "scope": "static/non-Windows",
    "passed": sum(bool(r["passed"]) for r in RESULTS),
    "failed": sum(not bool(r["passed"]) for r in RESULTS),
    "results": RESULTS,
    "hashes": hashes,
    "limitations": [
        "Não usa o parser AST oficial do PowerShell.",
        "Não executa Windows Forms, Agendador, serviços, ACL, GAC ou a CLI real.",
        "Deve ser complementado por scripts/Invoke-QA.ps1 em Windows."
    ],
}
out = ROOT / "test-results"
out.mkdir(exist_ok=True)
(out / "static-qa.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Relatório: {out / 'static-qa.json'}")
sys.exit(1 if report["failed"] else 0)
