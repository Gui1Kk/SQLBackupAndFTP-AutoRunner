#!/usr/bin/env python3
from __future__ import annotations
import json, subprocess, sys
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
RESULTS=[]
def add(n,p,d):
    RESULTS.append({'name':n,'passed':bool(p),'detail':d}); print(f"[{'PASS' if p else 'FAIL'}] {n}: {d}")

def run(cmd):
    cp=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True)
    return cp.returncode, (cp.stdout+cp.stderr).strip()
files=sorted([*ROOT.glob('services/**/*.ts'),*ROOT.glob('deploy/scripts/*.ts')])
fail=[]
for f in files:
    rc,out=run(['node','--experimental-strip-types','--check',str(f.relative_to(ROOT))])
    if rc: fail.append(f'{f.relative_to(ROOT)}: {out}')
add('Sintaxe TypeScript executável pelo Node',not fail,f'{len(files)} arquivo(s)' if not fail else '; '.join(fail[:4]))
rc,out=run(['node','--check','apps/central-web/app.js'])
add('Sintaxe JavaScript do aplicativo central',rc==0,'válida' if rc==0 else out)
for rel in ['deploy/docker/docker-compose.yml','contracts/openapi.yaml']:
    try:
        data=yaml.safe_load((ROOT/rel).read_text(encoding='utf-8-sig'))
        add(f'YAML válido: {rel}',isinstance(data,dict),f'{len(data) if isinstance(data,dict) else 0} chave(s)')
    except Exception as e: add(f'YAML válido: {rel}',False,str(e))
# SQL lexical sanity: this is not a PostgreSQL parser, but catches damaged packaging.
sql=(ROOT/'deploy/postgres/init/001_control_plane.sql').read_text(encoding='utf-8-sig')
add('Schema PostgreSQL presente', 'CREATE TABLE IF NOT EXISTS ar_commands' in sql and 'CREATE TABLE IF NOT EXISTS ar_outbox' in sql and 'CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_agents_active_install_id' in sql, 'tabelas e índices centrais localizados')
report={'tool':'ControlPlane-Syntax-QA.py','passed':sum(r['passed'] for r in RESULTS),'failed':sum(not r['passed'] for r in RESULTS),'results':RESULTS,'limitations':['Sem npm install neste ambiente, portanto não resolve imports externos.','Sem PostgreSQL/Docker local, portanto o DDL é validado estruturalmente, não executado.']}
(ROOT/'test-results').mkdir(exist_ok=True)
(ROOT/'test-results/control-plane-syntax.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(1 if report['failed'] else 0)
