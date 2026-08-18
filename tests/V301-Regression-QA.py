#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; R=[]
def rd(p): return (ROOT/p).read_text(encoding='utf-8-sig')
def add(n,p,d): R.append({'name':n,'passed':bool(p),'detail':d}); print(f"[{'PASS' if p else 'FAIL'}] {n}: {d}")
version=rd('VERSION').strip(); channel=rd('RELEASE_CHANNEL').strip()
add('Versão estável 3.0.1',version=='3.0.1' and channel.upper()=='STABLE',f'{version}-{channel}')
manager=rd('scripts/Manager.ps1'); core=rd('modules/AutoRunner.Core.psm1'); runner=rd('scripts/Run-SQLBackupAndFTPJob.ps1'); setup=rd('scripts/Setup-Wizard.ps1'); winqa=rd('scripts/Invoke-QA.ps1')

# Bootstrap must accept the current canonical config schema before importing the module.
core_schema_match=re.search(r"\$script:ConfigSchemaVersion\s*=\s*(\d+)",core)
bootstrap_schema_match=re.search(r"\$bootstrapSupportedSchema\s*=\s*(\d+)",runner)
core_schema=int(core_schema_match.group(1)) if core_schema_match else -1
bootstrap_schema=int(bootstrap_schema_match.group(1)) if bootstrap_schema_match else -2
add('Bootstrap aceita schema canônico',core_schema==bootstrap_schema and core_schema>0,f'core={core_schema}; bootstrap={bootstrap_schema}')
add('Bootstrap rejeita somente schema futuro','if($bootstrapSchema -gt $bootstrapSupportedSchema)' in runner,'limite explícito e versionado')
workflow_path=ROOT/'.github/workflows/qa.yml'
workflow_text=workflow_path.read_text(encoding='utf-8') if workflow_path.exists() else ''
add('GitHub Actions não possui gatilho automático',workflow_path.exists() and 'workflow_call:' in workflow_text and all(x not in workflow_text for x in ('push:', 'pull_request:', 'schedule:', 'workflow_dispatch:')),'somente reusable workflow sem trigger autônomo')
add('GitHub Actions não aloca runner',workflow_path.exists() and 'if: ${{ false }}' in workflow_text,'jobs hard-disabled antes de runner allocation')

# PowerShell #27558 regression: List<T> created by New-Object can throw on @($list).
ps_text='\n'.join(p.read_text(encoding='utf-8-sig') for p in ROOT.rglob('*') if p.is_file() and p.suffix.lower() in ('.ps1','.psm1'))
legacy_lists=re.findall(r'New-Object\s+System\.Collections\.Generic\.List\s*\[',ps_text,re.I)
add('Nenhuma List<T> problemática criada por New-Object',not legacy_lists,f'{len(legacy_lists)} ocorrência(s)')
add('Salvar jobs usa array explícito seguro',"New-InstallRequest -Jobs $chosen.ToArray()" in manager,'ToArray no fluxo GUI')
sqlite_start=core.find('function Get-SqlBakJobsFromSqlite'); sqlite_end=core.find('\nfunction ',sqlite_start+10); sqlite=core[sqlite_start:sqlite_end]
add('Descoberta SQLite usa construtor .NET seguro','[System.Collections.Generic.List[object]]::new()' in sqlite,'sem binder problemático no retorno')

# UX simple-first and responsive layout.
add('Modo simples é padrão','UseAdvancedSettings = $false' in core and "Text='Usar configurações avançadas'" in manager,'avançado opt-in')
add('Modo simples oculta colunas técnicas',"@('Type','Scheduled','LastRun','Source','BackupType')" in manager and '.Visible=$enabled' in manager,'metadados só no avançado')
add('Modo simples força tipo Default',"$backupType=if($advancedToggle.Checked)" in manager and "else{'Default'}" in manager,'não exige conhecimento de backup type')
add('Modo simples usa perfil interno sem knobs','$execution=$defaults.Execution | Select-Object *' in manager and '$execution.MinimumIntervalHours=0' in manager and '$execution.RetryCount=0' in manager and '$logging=$defaults.Logging | Select-Object *' in manager,'cada boot, sem retry, defaults internos')
add('Janela principal tem host rolável','$mainHost.AutoScroll=$true' in manager and "$mainGrid.Dock='Top'" in manager,'conteúdo não é achatado')
add('Área de ações tem altura mínima estável',"SizeType]::Absolute,220" in manager and 'contentFloor' in manager and 'DeviceDpi' in manager,'floor vertical escalado por DPI + scroll')
add('Configuração usa DPI + scroll',"$dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi" in manager and '$dialog.AutoScroll=$true' in manager and '$root.Dock=\'Top\'' in manager and 'baseHeight*$dpiScale' in manager,'layout adaptativo + floor escalado')

# ACL FullControl policy repaired after real 3.0.0-RC failure.
required=['S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-1-0','S-1-15-2-1','S-1-15-2-2','S-1-3-0','S-1-3-4']
add('ACL mantém todos SIDs normativos',all(x in core for x in required),'9 SIDs + instalador atual')
add('icacls usa SID numérico prefixado por asterisco',"('*{0}:(OI)(CI)F' -f $sidText)" in core and 'Invoke-AutoRunnerIcacls' in core,'compatível com SID numérico')
add('CREATOR OWNER é inherit-only',"('*{0}:(OI)(CI)(IO)F' -f $sidText)" in core and "S-1-3-0 (CREATOR OWNER) sem FullControl inherit-only OI/CI" in core,'não exige ACE efetiva nos filhos')
eff_start=core.find('function Get-AutoRunnerProductEffectiveFullControlSidList'); eff_end=core.find('\nfunction ',eff_start+10); eff=core[eff_start:eff_end]
add('Validador efetivo exclui placeholder CREATOR OWNER',"$_ -ne 'S-1-3-0'" in eff,'filhos recebem ACL materializada')
add('Aplicação normaliza ACL herdada dos filhos',"'/reset','/T','/C','/Q'" in core,'staging antigo não preserva ACL protegida')
add('QA Windows exercita política FullControl real','ACL FullControl 3.0.1 real em ProgramData' in winqa and 'Set-AutoRunnerProductFullControlAcl -Path $aclDir' in winqa,'gate integrado administrativo')
add('Mensagens operacionais usam 3.0.1','3.0.0-RC não conforme' not in core and 'política 3.0.0-RC' not in setup,'sem gate antigo')

# Verify every advanced switch shown in UI has an implementation path.
exec_props=['StartupDelayMinutes','MinimumIntervalHours','RetryCount','RetryDelayMinutes','RetryOnCliError','ServiceWaitSeconds','SqlServiceWaitSeconds','SqlServiceWaitMode','ExecutionTimeLimitHours','PostJobDelaySeconds','StopOnFirstFailure','TaskRestartOnFailure','TaskRestartCount','TaskRestartIntervalMinutes']
for prop in exec_props:
    declared=prop in manager
    applied=(f'Execution.{prop}' in runner) or (f'Execution.{prop}' in core)
    add(f'Avançado aplicado: {prop}',declared and applied,'UI + runtime/task')
for prop in ['MaxSizeMB','KeepFiles','RetentionDays']:
    add(f'Log avançado aplicado: {prop}',prop in manager and prop in core,'UI + rotação/retention')
add('BackupType avançado chega à CLI','BackupType' in manager and "-backupType" in core and '$job.BackupType' in runner,'UI -> config -> CLI')

report={'tool':'V301-Regression-QA.py','passed':sum(x['passed'] for x in R),'failed':sum(not x['passed'] for x in R),'results':R}
(ROOT/'test-results').mkdir(exist_ok=True); (ROOT/'test-results/v301-regression.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(1 if report['failed'] else 0)
