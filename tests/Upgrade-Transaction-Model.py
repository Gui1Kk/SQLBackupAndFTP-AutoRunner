#!/usr/bin/env python3
"""Fault-injection model for the sibling-directory upgrade transaction."""
from __future__ import annotations

import itertools
import json
import random
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass
class State:
    destination: str | None = "old"
    stage: str | None = None
    rollback: str | None = None
    registry: str = "old"
    shortcuts: str = "old"

    def invariant(self) -> None:
        if self.destination not in (None, "old", "new"):
            raise AssertionError(f"destination inválido: {self.destination}")
        if self.stage not in (None, "new"):
            raise AssertionError(f"stage inválido: {self.stage}")
        if self.rollback not in (None, "old"):
            raise AssertionError(f"rollback inválido: {self.rollback}")
        if self.destination is None and self.rollback is None:
            raise AssertionError("nenhuma instalação recuperável")
        if self.destination == "old" and self.rollback == "old":
            raise AssertionError("instalação antiga duplicada")


def recover(state: State) -> State:
    # Mirrors Recover-ApplicationTransactionResidue.
    state.stage = None
    if state.destination is None and state.rollback == "old":
        state.destination, state.rollback = "old", None
    elif state.destination is not None and state.rollback == "old":
        state.rollback = None
    state.invariant()
    return state


def rollback(state: State) -> State:
    if state.destination == "new":
        state.destination = None
    if state.rollback == "old":
        state.destination, state.rollback = "old", None
    state.stage = None
    state.registry = "old"
    state.shortcuts = "old"
    state.invariant()
    return state


STEPS = (
    "create_stage",
    "copy_payload",
    "protect_stage",
    "move_old_to_rollback",
    "promote_stage",
    "protect_destination",
    "write_integrations",
    "delete_rollback",
)


def execute(fail_before: int | None = None, crash: bool = False) -> State:
    state = State()
    for index, step in enumerate(STEPS):
        if fail_before == index:
            return recover(state) if crash else rollback(state)
        if step == "create_stage":
            state.stage = "new"
        elif step == "copy_payload":
            if state.stage != "new":
                raise AssertionError("cópia sem stage")
        elif step == "protect_stage":
            if state.stage != "new":
                raise AssertionError("ACL sem stage")
        elif step == "move_old_to_rollback":
            if state.destination != "old" or state.rollback is not None:
                raise AssertionError("pré-condição de rollback inválida")
            state.destination, state.rollback = None, "old"
        elif step == "promote_stage":
            if state.destination is not None or state.stage != "new":
                raise AssertionError("pré-condição de promoção inválida")
            state.destination, state.stage = "new", None
        elif step == "protect_destination":
            if state.destination != "new":
                raise AssertionError("ACL sem versão nova")
        elif step == "write_integrations":
            state.registry = state.shortcuts = "new"
        elif step == "delete_rollback":
            if state.destination != "new":
                raise AssertionError("limpeza sem nova instalação")
            state.rollback = None
        state.invariant()
    return state


def main() -> int:
    cases: list[dict[str, object]] = []
    failures: list[str] = []
    for crash, fail_before in itertools.product((False, True), range(len(STEPS) + 1)):
        try:
            state = execute(fail_before if fail_before < len(STEPS) else None, crash)
            state.invariant()
            if fail_before < len(STEPS):
                # A exceção capturada faz rollback para old. Uma queda abrupta
                # depois da promoção pode ser recuperada como new. Em ambos os
                # casos deve existir exatamente uma instalação íntegra.
                expected = {"old"} if not crash else ({"old"} if fail_before <= STEPS.index("promote_stage") else {"new"})
                if state.destination not in expected:
                    raise AssertionError(f"falha não convergiu para {sorted(expected)}: {state}")
            else:
                if state.destination != "new" or state.rollback is not None:
                    raise AssertionError(f"sucesso não consolidou versão nova: {state}")
            cases.append({"crash": crash, "failBefore": fail_before, "state": state.__dict__, "passed": True})
        except Exception as exc:
            failures.append(f"crash={crash} failBefore={fail_before}: {exc}")
            cases.append({"crash": crash, "failBefore": fail_before, "passed": False, "error": str(exc)})

    rng = random.Random(20260300)
    for index in range(100000):
        crash = bool(rng.getrandbits(1))
        fail_before = rng.randrange(0, len(STEPS) + 1)
        state = execute(fail_before if fail_before < len(STEPS) else None, crash)
        state.invariant()
        if fail_before >= len(STEPS):
            expected = "new"
        elif not crash or fail_before <= STEPS.index("promote_stage"):
            expected = "old"
        else:
            expected = "new"
        if state.destination != expected:
            failures.append(f"fuzz {index}: esperado={expected} atual={state}")
            break

    script = (ROOT / "scripts" / "Setup-Wizard.ps1").read_text(encoding="utf-8-sig")
    required_tokens = (
        "New-ApplicationStageDirectory",
        "Move-ApplicationDirectoryForUpgrade",
        "Move-ApplicationDirectoryAtomic -Source $stage -Destination $Destination",
        "Restore-ApplicationDirectoryFromUpgradeBackup",
        "Recover-ApplicationTransactionResidue",
        "Remove-ApplicationUpgradeBackupSafe",
    )
    missing = [token for token in required_tokens if token not in script]
    if missing:
        failures.append("tokens ausentes no implementador: " + ", ".join(missing))

    report = {"suite": "Upgrade-Transaction-Model", "cases": cases, "fuzzIterations": 100000, "failed": failures}
    output = ROOT / "test-results"
    output.mkdir(exist_ok=True)
    (output / "Upgrade-Transaction-Model.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if failures:
        for failure in failures:
            print("[FAIL]", failure)
        return 1
    print(f"[PASS] {len(cases)} falhas determinísticas e 100000 iterações de fuzz preservaram old ou new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
