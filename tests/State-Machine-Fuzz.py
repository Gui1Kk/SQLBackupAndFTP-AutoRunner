#!/usr/bin/env python3
"""Fuzz/model checking da política de execução do AutoRunner.

Não executa a CLI real. Valida invariantes da máquina de estados em cenários
aleatórios reproduzíveis, além de casos direcionados de fronteira.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "test-results" / "state-machine-fuzz.json"
DEFAULT_SEED = 20260805


@dataclass
class Job:
    name: str
    within: bool
    outcomes: list[object]  # int exit code or Exception


@dataclass
class Result:
    name: str
    result: str
    attempts: int
    code: int


def run(
    jobs: list[Job],
    retry_count: int,
    retry_cli: bool,
    stop: bool,
    startup: bool = True,
    force: bool = False,
):
    results: list[Result] = []
    calls: list[str] = []
    stopped = False
    for job in jobs:
        if stopped:
            results.append(Result(job.name, "Não executado após falha anterior", 0, 14))
            continue
        if startup and not force and job.within:
            results.append(Result(job.name, "Ignorado pelo intervalo mínimo", 0, 12))
            continue

        success = False
        last = 98
        attempts = 0
        for n in range(retry_count + 1):
            attempts = n + 1
            calls.append(job.name)
            outcome = job.outcomes[min(n, len(job.outcomes) - 1)]
            if isinstance(outcome, Exception):
                last = 98
                continue
            last = int(outcome)
            if last == 0:
                success = True
                break
            if not retry_cli:
                break

        results.append(Result(job.name, "CLI sem erro" if success else "Falha", attempts, last))
        if not success and stop:
            stopped = True

    ok = sum(x.result == "CLI sem erro" for x in results)
    fail = sum(x.result == "Falha" for x in results)
    skip = sum(x.result == "Ignorado pelo intervalo mínimo" for x in results)
    notrun = sum(x.result == "Não executado após falha anterior" for x in results)
    if fail == 0 and ok > 0:
        process, state = 0, 0
    elif fail == 0 and ok == 0 and skip > 0:
        process, state = 0, 12
    elif ok > 0 and fail > 0:
        process, state = 10, 10
    else:
        process, state = 11, 11
    return results, calls, process, state, (ok, fail, skip, notrun)


def execute(scenarios: int, seed: int) -> dict[str, object]:
    rng = random.Random(seed)
    failures: list[object] = []

    for case in range(scenarios):
        count = rng.randint(1, 12)
        retry = rng.randint(0, 5)
        retry_cli = rng.choice([False, False, False, True])
        stop = rng.choice([False, False, True])
        force = rng.choice([False, False, True])
        jobs: list[Job] = []
        for i in range(count):
            within = rng.choice([False, False, True])
            outcomes: list[object] = []
            for _ in range(retry + 1):
                pick = rng.randrange(10)
                outcomes.append(0 if pick < 5 else (7 if pick < 9 else RuntimeError("transitório")))
            jobs.append(Job(f"Job {i}", within, outcomes))

        results, calls, process, state, counts = run(jobs, retry, retry_cli, stop, True, force)

        if len(results) != count or len({x.name for x in results}) != count:
            failures.append((case, "resultado não total/único"))
            break
        if len(calls) != sum(x.attempts for x in results):
            failures.append((case, "chamadas divergem das tentativas"))
            break
        if any(x.attempts < 0 or x.attempts > retry + 1 for x in results):
            failures.append((case, "tentativas fora do limite"))
            break
        if any(
            x.result in {"Ignorado pelo intervalo mínimo", "Não executado após falha anterior"}
            and x.attempts != 0
            for x in results
        ):
            failures.append((case, "skip/not-run chamou CLI"))
            break

        for job, result in zip(jobs, results):
            if result.result in {"Ignorado pelo intervalo mínimo", "Não executado após falha anterior"}:
                continue
            if (
                not retry_cli
                and isinstance(job.outcomes[0], int)
                and job.outcomes[0] != 0
                and result.attempts != 1
            ):
                failures.append((case, "retry de código CLI sem opt-in"))
                break
        if failures:
            break

        if stop:
            seen_fail = False
            for result in results:
                if seen_fail and result.result != "Não executado após falha anterior":
                    failures.append((case, "stop não marcou pendente"))
                    break
                if result.result == "Falha":
                    seen_fail = True
        if failures:
            break

        ok, fail, skip, _notrun = counts
        expected = (
            (0, 0)
            if fail == 0 and ok > 0
            else ((0, 12) if fail == 0 and ok == 0 and skip > 0 else ((10, 10) if ok > 0 and fail > 0 else (11, 11)))
        )
        if (process, state) != expected:
            failures.append((case, "código agregado incoerente"))
            break

    directed: list[dict[str, str]] = []

    def check(name: str, condition: bool, detail: str) -> None:
        directed.append({"name": name, "status": "PASS" if condition else "FAIL", "detail": detail})
        if not condition:
            failures.append(("directed", name))

    res, calls, process, state, _ = run([Job("A", True, [0]), Job("B", True, [0])], 3, True, False, True, False)
    check(
        "Todos no intervalo não chamam CLI",
        calls == [] and process == 0 and state == 12 and all(x.attempts == 0 for x in res),
        str((calls, process, state, res)),
    )
    res, calls, process, _state, _ = run([Job("A", False, [7, 0])], 5, False, False)
    check(
        "Código CLI sem opt-in faz uma tentativa",
        len(calls) == 1 and res[0].attempts == 1 and process == 11,
        str((calls, process, res)),
    )
    res, calls, process, _state, _ = run([Job("A", False, [RuntimeError(), 0])], 1, False, False)
    check(
        "Exceção transitória pode recuperar",
        len(calls) == 2 and res[0].result == "CLI sem erro" and process == 0,
        str((calls, process, res)),
    )
    res, calls, process, _state, _ = run(
        [Job("A", False, [0]), Job("B", False, [7]), Job("C", False, [0])], 0, False, True
    )
    check(
        "Stop audita restante sem chamar",
        calls == ["A", "B"] and res[2].code == 14 and process == 10,
        str((calls, process, res)),
    )
    res, calls, process, state, _ = run([Job("A", True, [0])], 0, False, False, startup=True, force=True)
    check(
        "Force ignora intervalo mínimo",
        calls == ["A"] and res[0].result == "CLI sem erro" and (process, state) == (0, 0),
        str((calls, process, state, res)),
    )
    res, calls, process, state, _ = run([Job("A", False, [7, 7, 0])], 2, True, False)
    check(
        "Retentativa opt-in pode recuperar código CLI",
        len(calls) == 3 and res[0].attempts == 3 and res[0].result == "CLI sem erro" and (process, state) == (0, 0),
        str((calls, process, state, res)),
    )

    return {
        "suite": "state-machine-fuzz",
        "seed": seed,
        "scenarios": scenarios,
        "directed": directed,
        "failures": failures,
        "status": "PASS" if not failures else "FAIL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", "--scenarios", dest="scenarios", type=int, default=15000)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if args.scenarios < 1 or args.scenarios > 2_000_000:
        parser.error("--iterations deve ficar entre 1 e 2.000.000")

    report = execute(args.scenarios, args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"[{'PASS' if report['status'] == 'PASS' else 'FAIL'}] Fuzz: "
        f"{args.scenarios} cenários, seed {args.seed}, falhas={len(report['failures'])}"
    )
    for directed in report["directed"]:
        print(f"[{directed['status']}] {directed['name']}: {directed['detail']}")
    print(f"Relatório: {args.output}")
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
