#!/usr/bin/env python3
"""Historical PowerShell 5.1 and tutorial regression checks."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS: list[dict[str, object]] = []


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8-sig")


def add(name: str, passed: bool, detail: str) -> None:
    RESULTS.append({"name": name, "passed": bool(passed), "detail": detail})
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")


setup = read("scripts/Setup-Wizard.ps1")
manager = read("scripts/Manager.ps1")
module = read("modules/AutoRunner.Core.psm1")
builder = read("build/Build-Release.py")

version = read("VERSION").strip()
add(
    "Versão única atual",
    ("$script:AutoRunnerVersion = '" + version + "'") in module and "read_version(root)" in builder,
    "módulo e builder usam a fonte VERSION",
)

unsafe_ordered_foreach = re.findall(r"foreach\s*\([^\n]*\bin\s+\[ordered\]@\{", setup, flags=re.I)
add(
    "Sem ordered hashtable não parenthesizada em foreach",
    not unsafe_ordered_foreach,
    "as expressões [ordered] são parenthesizadas antes de GetEnumerator",
)
add(
    "Registro da aplicação compatível com PowerShell 5.1",
    "foreach($entry in ([ordered]@{ApplicationInstallDir=" in setup
    and "}).GetEnumerator()){\n        New-ItemProperty -Path $uninstallKey" in setup,
    "os dois loops críticos usam ([ordered]@{...}).GetEnumerator()",
)
add(
    "Tutorial usa estado compartilhado no formulário",
    "$wizard.Tag=[pscustomobject]@{" in manager
    and "$state=$wizard.Tag" in manager
    and "$state.Index=[int]$state.Index+1" in manager
    and "$state.Index=[int]$state.Index-1" in manager,
    "navegação não depende de atribuição a variável escalar capturada",
)
tutorial_start = manager.index("function Show-AutoRunnerTutorial")
tutorial_end = manager.index("function Show-SqlBackupLocationDialog", tutorial_start)
tutorial_section = manager[tutorial_start:tutorial_end]
add(
    "Tutorial não usa índice escalar capturado",
    "$index++" not in tutorial_section
    and "$index--" not in tutorial_section
    and "$pages[$index]" not in tutorial_section
    and "$index=" not in tutorial_section,
    "padrão que congelava callbacks foi removido apenas do escopo do tutorial",
)
add(
    "Callbacks do tutorial tratam exceções",
    all(
        token in manager
        for token in (
            "Tutorial: $Context",
            "falha ao renderizar uma página",
            "falha ao voltar",
            "falha ao avançar",
            "falha ao pular",
        )
    ),
    "erros são registrados e exibidos",
)
add(
    "Tutorial inicial é adiado até a interface estar pronta",
    "$startupTutorialTimer=New-Object Windows.Forms.Timer" in manager
    and "$startupTutorialTimer.Add_Tick" in manager
    and "$form.Add_Shown" in manager
    and "Show-AutoRunnerTutorial" in manager,
    "abertura ocorre por timer depois do evento Shown",
)
add(
    "Falha do tutorial não fecha a interface principal",
    "A interface principal continuará aberta." in manager
    and "$startupTutorialTimer.Stop()" in manager,
    "erro é isolado do formulário principal",
)
add(
    "Smoke test real de navegação do tutorial",
    "TutorialSmoke" in manager
    and "TUTORIAL_SMOKE_PASS" in manager
    and "$next.PerformClick()" in manager
    and "$back.PerformClick()" in manager
    and "Smoke test do tutorial falhou" in manager,
    "avançar, voltar e concluir são exercitados por WinForms",
)
add(
    "Pular salva preferência antes de fechar",
    re.search(
        r"\$skip\.Add_Click\(\{.*?if \(& \$saveTutorialSettings \$false\).*?\$wizard\.Close\(\)",
        manager,
        flags=re.S,
    )
    is not None,
    "o botão não encerra silenciosamente antes da persistência",
)
add(
    "Concluir salva preferência antes de fechar",
    re.search(
        r"if \(& \$saveTutorialSettings \$true\).*?DialogResult.*?\$wizard\.Close\(\)",
        manager,
        flags=re.S,
    )
    is not None,
    "conclusão persiste o estado e fecha somente o assistente",
)

result = {
    "suite": "V221-Regression-QA",
    "passed": sum(1 for item in RESULTS if item["passed"]),
    "failed": sum(1 for item in RESULTS if not item["passed"]),
    "results": RESULTS,
}
out = ROOT / "test-results"
out.mkdir(exist_ok=True)
(out / "V221-Regression-QA.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"passed": result["passed"], "failed": result["failed"]}, ensure_ascii=False))
raise SystemExit(0 if result["failed"] == 0 else 1)
