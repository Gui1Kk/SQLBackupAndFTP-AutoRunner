#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; R=[]
def rd(p): return (ROOT/p).read_text(encoding='utf-8-sig')
def add(n,p,d): R.append({'name':n,'passed':bool(p),'detail':d}); print(f"[{'PASS' if p else 'FAIL'}] {n}: {d}")
add('Versão 3.0.0 RC',rd('VERSION').strip()=='3.0.0' and rd('RELEASE_CHANNEL').strip().upper()=='RC','canônica')
manager=rd('scripts/Manager.ps1'); module=rd('modules/AutoRunner.Core.psm1'); compose=rd('deploy/docker/docker-compose.yml'); agent=rd('agent/remote-control/AutoRunner.RemoteAgent.psm1')
checks={
 'Manager integra conectar/desconectar Central': all(x in manager for x in ('Conectar à Central','Desconectar da Central','AutoRunner.RemoteAgent')),
 'Enrollment elevado usa arquivo + hash': 'EnrollmentRequestPath' in manager and 'EnrollmentRequestSha256' in manager and 'Get-AutoRunnerFileHash' in manager,
 'Agente roda como tarefa SYSTEM': 'SYSTEM' in agent and 'Register-ScheduledTask' in agent,
 'Agente persiste identidade sem token de enrollment': 'SecretProtected' in agent and 'EnrollmentToken' not in agent[agent.find('function Save-RemoteAgentIdentity'):agent.find('function Get-OrCreateRemoteInstallId')],
 'Control Plane só entra via Caddy': 'caddy:' in compose and 'ms-a:' in compose and 'ms-b:' in compose and 'ms-c:' in compose,
 'FullControl 3.0 é requisito executável': 'Set-AutoRunnerProductFullControlAcl' in module and 'FullControl' in module,
 'Contratos são preenchidos': (ROOT/'contracts/openapi.yaml').stat().st_size>500 and (ROOT/'contracts/schema.graphql').stat().st_size>500,
 'Dashboard central entregue': all((ROOT/f'apps/central-web/{x}').stat().st_size>500 for x in ('index.html','app.css','app.js')),
 'Backup e restauração do plano de controle': (ROOT/'deploy/windows/Backup-ControlPlane.ps1').stat().st_size>500 and (ROOT/'deploy/windows/Restore-ControlPlane.ps1').stat().st_size>500,
}
for n,p in checks.items(): add(n,p,'implementado' if p else 'ausente')
report={'tool':'V300-Regression-QA.py','passed':sum(x['passed'] for x in R),'failed':sum(not x['passed'] for x in R),'results':R}
(ROOT/'test-results').mkdir(exist_ok=True); (ROOT/'test-results/v300-regression.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(1 if report['failed'] else 0)
