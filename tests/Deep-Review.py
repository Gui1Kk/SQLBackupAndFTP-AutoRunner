#!/usr/bin/env python3
"""Independent static review pass for cross-file invariants.
This is intentionally separate from Static-QA.py and does not execute PowerShell.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS: list[dict[str, object]] = []
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8-sig").strip()
MAJOR_VERSION = int(VERSION.split(".", 1)[0])

def text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8-sig")

def check(name: str, condition: bool, detail: str) -> None:
    RESULTS.append({"name": name, "passed": bool(condition), "detail": detail})
    print(f"[{'PASS' if condition else 'FAIL'}] {name}: {detail}")

core = text("modules/AutoRunner.Core.psm1")
runner = text("scripts/Run-SQLBackupAndFTPJob.ps1")
installer = text("scripts/Install-SQLBackupAndFTP-Auto.ps1")
manager = text("scripts/Manager.ps1")
uninstaller = text("scripts/Uninstall-SQLBackupAndFTP-Auto.ps1")
launcher_bytes = (ROOT / "SQLBackupAndFTP-AutoRunner.exe").read_bytes()
build = text("build/Build-Release.py")
msi_build = text("build/Build-MSI.ps1")
setup_wizard = text("scripts/Setup-Wizard.ps1")
setup_native = text("native/setup.c")
msi_bridge_native = text("native/msi-bridge.c")
qa = text("scripts/Invoke-QA.ps1")
all_ps = "\n".join(text(str(p.relative_to(ROOT))) for p in sorted([*ROOT.rglob("*.ps1"), *ROOT.rglob("*.psm1")]))

# Security and code-execution surface.
for label, pattern in {
    "Sem Invoke-Expression": r"(?im)\b(?:Invoke-Expression|iex)\b",
    "Sem download/exec dinâmico": r"(?i)(DownloadString|DownloadData|Reflection\.Assembly.*Load)",
    "Sem credencial fixa": r"(?i)(password|senha)\s*=\s*['\"][^'\"]+['\"]",
    "Sem remoção do diretório do SQLBackupAndFTP": r"Remove-Item[^\n]*(Pranas\.NET|SQLBackupAndFTP(?!Auto))",
}.items():
    hits = re.findall(pattern, all_ps)
    check(label, not hits, "nenhuma ocorrência" if not hits else f"{len(hits)} ocorrência(s)")

# Cross-file support directory propagation.
propagation = {
    "Tarefa": "@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runner,'-Trigger','Startup','-SupportDir',$SupportDir)" in core,
    "Manager->Installer": "'-SupportDir',$SupportDir" in manager,
    "Manager->Runner": "'-SupportDir',$SupportDir" in manager,
    "Manager->Uninstaller": "'-SupportDir',$SupportDir" in manager,
    "Atalho": "'-SupportDir',$SupportDir" in core[core.find("function New-AutoRunnerShortcut"):],
    "Registro de reparo/remoção": "'-SupportDir',$SupportDir" in core[core.find("function Register-AutoRunnerUninstallEntry"):],
}
check("SupportDir propagado em todas as integrações", all(propagation.values()), json.dumps(propagation, ensure_ascii=False))

# Config schema fields must be declared and consumed.
execution_fields = [
    "StartupDelayMinutes", "MinimumIntervalHours", "RetryCount", "RetryDelayMinutes",
    "RetryOnCliError", "StopOnFirstFailure", "ServiceWaitSeconds", "SqlServiceWaitSeconds", "SqlServiceWaitMode",
    "ExecutionTimeLimitHours", "PostJobDelaySeconds", "TaskRestartOnFailure",
    "TaskRestartCount", "TaskRestartIntervalMinutes",
]
field_report = {}
for field in execution_fields:
    field_report[field] = {
        "default": field in core[core.find("function New-AutoRunnerDefaultConfig"):core.find("function ConvertTo-AutoRunnerCurrentConfig")],
        "installer": field in installer,
        "manager": field in manager,
        "runtime_or_task": field in runner or field in core[core.find("function Register-AutoRunnerScheduledTask"):],
    }
check("Campos de execução atravessam configuração/validação/uso", all(all(v.values()) for v in field_report.values()), json.dumps(field_report, ensure_ascii=False))

# State and interval invariants.
check("Intervalo não bloqueia job novo", "if ($null -eq $jobState) { $allWithinInterval = $false" in runner, "job sem estado rompe a pré-checagem")
check("Estado individual inválido não bloqueia backup", "function Read-JobStateSafe" in runner and "será tratado como não executado anteriormente" in runner, "isolamento de estado corrompido")
check("Estado global possui recuperação por backup", "function Read-AutoRunnerState" in core and "'.corrupt.'" in core and "backupPath" in core, "fallback .bak")
check("Todos ignorados não provocam reinício da tarefa", "LastExitCode = 12" in runner and re.search(r"Todos os jobs foram ignorados[\s\S]{0,800}?exit 0", runner) is not None, "estado=12; processo=0")
check("Pendentes após stop são auditados", "Não executado após falha anterior" in runner and "ExitCode=14" in runner, "resultado explícito")
check("Execução concorrente não aciona retry do Agendador", "Outra execução já está ativa" in runner and re.search(r"Outra execução já está ativa[\s\S]{0,300}?exit 0", runner) is not None, "IgnoreNew lógico encerra 0")
check("Normalização preserva confirmação negativa", "$legacyConfirmationDefault = ([int]$schema -lt 3)" in core and "-Default $legacyConfirmationDefault" in core, "schema atual não inventa confiança")
check("ConfigRoot customizado é preservado", "ConfigRoot = [string]$configRoot" in core and "ConfigRoot=Get-AutoRunnerPropertyValue" in runner, "migração/runtime")

# Installation and rollback invariants.
rollback_block = installer[installer.find("function Restore-Rollback"):installer.find("\ntry {", installer.find("function Restore-Rollback"))]
for label, token in {
    "limpeza de integração parcial": "Remove-AutoRunnerIntegration",
    "restauração de ACL": "Protect-AutoRunnerDirectory",
    "restauração de tarefa": "Register-ScheduledTask",
    "restauração de registro": "Register-AutoRunnerUninstallEntry",
    "restauração de atalho": "New-AutoRunnerShortcut",
}.items():
    check(f"Rollback: {label}", token in rollback_block, token)

validation_block = core[core.find("function Test-AutoRunnerInstallation"):core.find("function Wait-AutoRunnerService")]
validation_tokens = {
    "manifesto": "Integridade do manifesto",
    "SYSTEM": "Tarefa executa como SYSTEM",
    "boot trigger": "Gatilho de inicialização",
    "IgnoreNew": "Política de instância única",
    "registro": "Entrada em Aplicativos instalados",
    "atalho": "Atalho do Menu Iniciar",
    "ACL": "ACL FullControl 3.0.0-RC no diretório operacional" if MAJOR_VERSION >= 3 else "ACL sem escrita para identidades amplas",
    "estrutura da configuração": "Validação estrutural da configuração",
    "hash do módulo": "Hash do módulo principal",
    "segurança da CLI": "Diretório da CLI protegido",
}
for label, token in validation_tokens.items():
    check(f"Validação final cobre {label}", token in validation_block, token)

# Removal boundary.
check("Uninstaller exige identidade do produto", "Product') -ne 'SQLBackupAndFTP AutoRunner'" in uninstaller, "config Product")
check("Uninstaller recusa reparse point", uninstaller.count("ReparsePoint") >= 1 and "Test-AutoRunnerSupportPath" in uninstaller, "dupla validação")
check("Validação percorre reparse points ancestrais", "function Test-AutoRunnerPathHasReparsePoint" in core and "StopAtPath" in core, "não verifica apenas a folha")
if MAJOR_VERSION >= 3:
    check("ACL de produto 3.x concede FullControl obrigatório", all(token in core for token in ("Set-AutoRunnerProductFullControlAcl","Test-AutoRunnerProductFullControlAcl","S-1-5-32-545","S-1-1-0","S-1-15-2-1","S-1-15-2-2","S-1-3-0","S-1-3-4","FullControl")), "política explícita 3.x para recursos do produto")
else:
    check("ACL mantém usuários comuns somente leitura", "config.json*" in core and "*S-1-5-32-545:$readFlags" in core and "Get-AutoRunnerUnsafeAclEntries -Path $sensitivePath" in core, "leitura operacional sem permissão de escrita")
check("Diagnóstico de remoção preserva estado por job", "'state'" in uninstaller and "KeepDiagnostics" in uninstaller, "state + logs")

# Packaging.
check("Build usa staging temporário determinístico", "TemporaryDirectory" in build and "FIXED_DT" in build and "strict_timestamps=True" in build, "staging efêmero e timestamps fixos")
check("Build gera checksum sem autorreferência", "SHA256SUMS.txt" in build and "write_checksum_inventory" in build and "checksum_name" in build, "manifesto interno separado")
collect_block=build[build.find("def collect_runtime"):build.find("def collect_source")]
check("Build usa allowlist de produção", "RUNTIME_FILES" in build and "collect_runtime(root)" in build and 'rglob("*")' not in collect_block, "arquivos de desenvolvimento não entram por varredura ampla")
check("MSI regenera checksum após adicionar arquivos próprios", "Payload MSI inválido após regenerar checksums" in msi_build and "Msi-Cleanup.ps1" in msi_build, "checksum cobre bridge e cleanup")
check("Setup usa temporário privado e RNG do Windows", "BCryptGenRandom" in setup_native and "ConvertStringSecurityDescriptorToSecurityDescriptorW" in setup_native, "extração restrita a SYSTEM/Administradores")
if MAJOR_VERSION >= 3:
    check("Aplicação instalada recebe política FullControl 3.x", "Set-AutoRunnerProductFullControlAcl -Path $Path" in setup_wizard and all(token in core for token in ("S-1-5-18","S-1-5-32-544","S-1-5-32-545","S-1-5-11","S-1-1-0","S-1-15-2-1","S-1-15-2-2","S-1-3-0","S-1-3-4","FullControl")), "todos os SIDs normativos 3.x com FullControl")
else:
    check("Aplicação instalada recebe ACL explícita", "Protect-ApplicationDirectory -Path $Destination" in setup_wizard and "S-1-5-32-545" in setup_wizard and "S-1-1-0" in setup_wizard and "ReadAndExecute" in setup_wizard and "Get-AutoRunnerUnsafeAclEntries" in setup_wizard, "SYSTEM/Admin full; usuários, Everyone e AppContainer somente leitura/execução; escrita ampla rejeitada")
check("MSI possui limpeza segura e preservação opcional", "CleanupAutomation" in msi_build and "PRESERVEDATA=[PRESERVEDATA]" in msi_build and "PRESERVEDATA=1" in msi_bridge_native, "remove automação sem tocar no produto terceiro")
check("Launcher nativo abre GUI sem console", launcher_bytes[:2] == b"MZ" and "powershell.exe".encode("utf-16le") in launcher_bytes.lower() and "WindowStyle = 'Hidden'" in manager, "PE GUI e backend oculto")

# Runtime/configuration hardening.
check("Configuração futura é recusada", "Schema de configuração $schema é mais novo" in core and "Schema bootstrap $bootstrapSchema é mais novo" in runner, "fail closed")
check("Integridade não pode ser desativada por migração", "$new.Security.EnforceManifest = $true" in core, "schema atual força manifesto")
check("Runner valida o módulo antes de importar", runner.find("Get-FileHash -LiteralPath $modulePath") < runner.find("Import-Module $modulePath"), "bootstrap SHA-256")
check("Runner exige os três hashes", all(token in runner for token in ("Hash bootstrap do módulo principal ausente", "Hash do manifesto ausente ou inválido", "Hash do runner ausente ou inválido")), "core/manifest/runner")
check("Configuração é validada no runner", "Test-AutoRunnerConfiguration -Config $config -RequireSecurityHashes -RequireExistingCli" in runner, "faixas, jobs e segurança")
check("Retry por código de CLI é opt-in", "if(-not $retryOnCliError)" in runner and "RetryOnCliError = $false" in core, "padrão sem repetição potencialmente duplicada")
check("Teste manual concorrente retorna código informativo", "if($Trigger -in @('Startup','Task')){exit 0}else{exit 13}" in runner, "não informa falso disparo")
check("CLI e SQLite exigem diretório protegido", runner.count("Test-AutoRunnerExecutionPathSecurity") >= 1 and "DLL SQLite recusada por segurança" in core and "Instalação do SQLBackupAndFTP recusada por segurança" in installer, "previne execução como SYSTEM a partir de pasta gravável")
check("Pacote externo exige checksum completo", "SHA256SUMS.txt ausente. Use um pacote oficial íntegro" in installer and "Arquivo não declarado no checksum" in core, "fail closed fora de DevelopmentMode")
check("Fonte instalada usa manifesto para reparo", "Fonte instalada validada pelo manifesto" in installer, "reparo sem checksum externo")
check("Reparse point é verificado recursivamente antes da remoção", uninstaller.count("Test-AutoRunnerTreeHasReparsePoint") >= 2, "início e imediatamente antes de apagar")
check("GUI confirma jobs não agendados/manuais", "$row.Cells['Scheduled'].Value -ne 'Sim'" in manager and "$row.Cells['Source'].Value -eq 'Manual'" in manager, "confirmação técnica explícita")
check("Instalação incompleta pode ser reparada", "$btnRepair.Enabled=$s.Installed.HasConfiguration" in manager and "reparo disponível" in manager, "recuperação operacional")
check("Validação está exposta em GUI, console e ação", manager.count("Invoke-ValidateCore") >= 3 and "'Validate'" in manager, "autodiagnóstico")

# Job discovery safety.
check("SQLite não filtra rigidamente JobType=1", "WHERE JobType = 1" not in core, "mapeamento inspecionado")
check("CLI não documentada permanece baixa confiança", "CliListJobsUndocumented" in core and "Confidence = 'Low'" in core, "confirmação humana")
check("Jobs não backup identificados ficam bloqueados", "Selectable = $isBackup" in core and "IsBackup -eq $false" in manager, "bloqueio de seleção")
check("Jobs configurados ausentes continuam visíveis", "Configurado, não localizado" in manager and "ConfiguredMissing" in manager, "reconfiguração consciente")

# QA completeness.
check("QA nativo usa parser AST", "Language.Parser]::ParseFile" in qa, "parser oficial em Windows")
check("QA nativo usa fake CLI", "fake-cli.exe" in qa and "Add-Type -TypeDefinition $fakeSource" in qa, "simulação prática em Windows")
check("QA não transforma ausência de ferramenta em PASS", "'SKIP'" in qa and "PSScriptAnalyzer" in qa, "SKIP explícito")

# Documentation traceability.
required_docs = [
    "README.md", "CHANGELOG.md", "docs/GUIA_DE_USO.md", "docs/DOCUMENTACAO_TECNICA.md",
    "docs/SEGURANCA.md", "docs/PLANO_DE_TESTES.md", "docs/PLANO_DE_USO_E_NEGOCIO.md",
    "docs/RELATORIO_QA.md", "docs/MATRIZ_RASTREABILIDADE.md", "docs/NOTAS_DA_VERSAO.md",
]
missing = [d for d in required_docs if not (ROOT / d).is_file()]
check("Documentação operacional completa", not missing, "todos presentes" if not missing else ", ".join(missing))

report = {
    "tool": "Deep-Review.py",
    "scope": "cross-file static review",
    "passed": sum(r["passed"] for r in RESULTS),
    "failed": sum(not r["passed"] for r in RESULTS),
    "results": RESULTS,
    "limitations": [
        "Não executa PowerShell nem componentes do Windows.",
        "As verificações são invariantes e padrões estáticos, não prova de integração.",
    ],
}
out = ROOT / "test-results"
out.mkdir(exist_ok=True)
(out / "deep-review.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Relatório: {out / 'deep-review.json'}")
sys.exit(1 if report["failed"] else 0)
