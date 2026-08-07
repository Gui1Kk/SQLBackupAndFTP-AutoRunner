#!/usr/bin/env python3
"""Executable specification model for AutoRunner business rules.
It validates expected outcomes independently from the PowerShell implementation.
It is not an integration test of SQLBackupAndFTP or Windows.
"""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS=[]

def record(name, ok, detail):
    RESULTS.append({"name":name,"passed":bool(ok),"detail":detail})
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")

@dataclass
class Job:
    name: str
    outcomes: list[int]
    last_success: datetime|None=None

@dataclass
class Result:
    name: str
    result: str
    attempts: int
    exit_code: int


def artifact(name: str) -> str:
    safe=''.join('_' if c in '<>:"/\\|?*' else c for c in name).strip().rstrip('.')[:80] or 'item'
    return f"{safe}-{hashlib.sha256(name.encode()).hexdigest()[:10]}"


def simulate(jobs, *, retry_count=0, retry_on_cli_error=False, stop=False, min_hours=0, now=None):
    now=now or datetime.now(timezone.utc)
    results=[]
    stopped=False
    for job in jobs:
        if stopped:
            results.append(Result(job.name,'Não executado após falha anterior',0,14)); continue
        if job.last_success and min_hours>0 and now < job.last_success+timedelta(hours=min_hours):
            results.append(Result(job.name,'Ignorado pelo intervalo mínimo',0,12)); continue
        attempts=0; exit_code=98; success=False
        for i in range(retry_count+1):
            attempts+=1
            exit_code=job.outcomes[min(i,len(job.outcomes)-1)]
            if exit_code==0: success=True; break
            if not retry_on_cli_error: break
        if success:
            results.append(Result(job.name,'CLI sem erro',attempts,0))
        else:
            results.append(Result(job.name,'Falha',attempts,exit_code))
            stopped=stop
    success=sum(r.result=='CLI sem erro' for r in results)
    fail=sum(r.result=='Falha' for r in results)
    skipped=sum(r.result=='Ignorado pelo intervalo mínimo' for r in results)
    notrun=sum(r.result=='Não executado após falha anterior' for r in results)
    if fail==0 and success>0: process=0; state=0
    elif fail==0 and success==0 and skipped>0: process=0; state=12
    elif success>0 and fail>0: process=10; state=10
    else: process=11; state=11
    return results, process, state, (success,fail,skipped,notrun)

r,p,s,c=simulate([Job('A',[0]),Job('B',[0])])
record('Sucesso total',p==0 and c==(2,0,0,0),'dois jobs, processo 0')
r,p,s,c=simulate([Job('A',[7]),Job('B',[0])])
record('Falha parcial continua',p==10 and [x.result for x in r]==['Falha','CLI sem erro'],str(c))
r,p,s,c=simulate([Job('A',[7]),Job('B',[0])],stop=True)
record('Parar após primeira falha audita pendente',p==11 and r[1].exit_code==14,str([x.result for x in r]))
r,p,s,c=simulate([Job('A',[7,0])],retry_count=1)
record('Código não zero não repete por padrão',p==11 and r[0].attempts==1,str(r[0]))
r,p,s,c=simulate([Job('A',[7,0])],retry_count=1,retry_on_cli_error=True)
record('Retentativa por código de CLI exige opt-in',p==0 and r[0].attempts==2,str(r[0]))
now=datetime.now(timezone.utc)
r,p,s,c=simulate([Job('Antigo',[0],now-timedelta(hours=1)),Job('Novo',[0],None)],min_hours=12,now=now)
record('Job novo não é bloqueado pelo sucesso de outro',p==0 and [x.result for x in r]==['Ignorado pelo intervalo mínimo','CLI sem erro'],str([x.result for x in r]))
r,p,s,c=simulate([Job('A',[0],now-timedelta(hours=1)),Job('B',[0],now-timedelta(hours=2))],min_hours=12,now=now)
record('Todos dentro do intervalo é condição normal',p==0 and s==12 and c==(0,0,2,0),str(c))
record('Artefatos sanitizados não colidem',artifact('Backup: Matriz')!=artifact('Backup? Matriz'),f"{artifact('Backup: Matriz')} | {artifact('Backup? Matriz')}")

# Link the specification to implementation tokens, without pretending execution equivalence.
runner=(ROOT/'scripts/Run-SQLBackupAndFTPJob.ps1').read_text(encoding='utf-8-sig')
links={
 'retry':'for ($attempt' in runner and 'if(-not $retryOnCliError)' in runner,
 'continue':'StopOnFirstFailure' in runner,
 'notrun':'Não executado após falha anterior' in runner,
 'per_job':'Read-JobStateSafe' in runner and 'jobInterval' in runner,
 'normal_skip':'LastExitCode = 12' in runner and 'exit 0' in runner,
}
record('Modelo possui pontos correspondentes no runner',all(links.values()),json.dumps(links,ensure_ascii=False))

report={"tool":"Behavioral-Model.py","scope":"business-rule executable specification","passed":sum(r['passed'] for r in RESULTS),"failed":sum(not r['passed'] for r in RESULTS),"results":RESULTS,"limitations":["Modelo independente; não executa o PowerShell real.","Não testa CLI, Windows, serviços, ACL ou backups."]}
out=ROOT/'test-results';out.mkdir(exist_ok=True)
(out/'behavioral-model.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(f"Relatório: {out/'behavioral-model.json'}")
sys.exit(1 if report['failed'] else 0)
