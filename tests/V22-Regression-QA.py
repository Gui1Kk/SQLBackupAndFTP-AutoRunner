#!/usr/bin/env python3
"""Historical 2.2 architecture checks carried forward to the current release."""
from __future__ import annotations
import json, re, struct, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RESULTS=[]
def read(rel): return (ROOT/rel).read_text(encoding='utf-8-sig')
def add(name,ok,detail):
    RESULTS.append({'name':name,'passed':bool(ok),'detail':detail})
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")

module=read('modules/AutoRunner.Core.psm1')
manager=read('scripts/Manager.ps1')
setup=read('scripts/Setup-Wizard.ps1')
installer=read('scripts/Install-SQLBackupAndFTP-Auto.ps1')
uninstaller=read('scripts/Uninstall-SQLBackupAndFTP-Auto.ps1')
setup_c=(ROOT/'native/setup.c').read_text()
launcher_c=(ROOT/'native/launcher.c').read_text()

version=read('VERSION').strip()
major_version=int(version.split('.',1)[0])
add('Versão canônica', ("$script:AutoRunnerVersion = '"+version+"'") in module and 'Get-AutoRunnerVersion' in manager, 'módulo e interface usam VERSION')
add('Correção DisplayName com StrictMode', "$item.DisplayName" not in module and "Get-AutoRunnerPropertyValue -InputObject $item -Name 'DisplayName'" in module, 'propriedades opcionais do registro acessadas com segurança')
for prop in ('InstallLocation','DisplayIcon','UninstallString','Publisher'):
    add(f'Registro seguro: {prop}', f"Get-AutoRunnerPropertyValue -InputObject $item -Name '{prop}'" in module, 'acessor tolerante a propriedade ausente')
add('Validação ARP tolera propriedades ausentes', '$entry.InstallLocation' not in module and '$entry.UninstallString' not in module and "Get-AutoRunnerPropertyValue -InputObject $entry -Name 'InstallLocation'" in module and "Get-AutoRunnerPropertyValue -InputObject $entry -Name 'UninstallString'" in module, 'validação da instalação também usa acesso seguro sob StrictMode')
add('Detecção multicamada', all(token in module for token in ('Preferência salva','Registro:','Serviço:','Processo:','App Paths','Atalho:','Pasta padrão','Busca limitada no volume')), 'fontes previstas presentes, incluindo busca limitada em volumes locais')
add('Busca profunda limitada', 'Find-SqlBakCliLimited' in module and ('MaxDirectories=12000' in module or 'MaxDirectories=8000' in module) and 'Get-ChildItem -LiteralPath $current.Path -Directory' in module, 'BFS com profundidade e teto de diretórios')
add('Seleção manual disponível', 'FolderBrowserDialog' in manager and 'Localizar SQLBackupAndFTP' in manager and 'Set-AutoRunnerUserSettings -PreferredSqlBackupPath' in manager, 'usuário pode escolher e persistir pasta validada')
add('Validação exige CLI', "SqlBak.Job.Cli.exe" in module and 'if (-not $cli) { return $null }' in module, 'diretório sem CLI é rejeitado')
add('Sem console no launcher', 'CREATE_NO_WINDOW' in launcher_c and 'SW_HIDE' in launcher_c and '-WindowStyle Hidden' in launcher_c, 'bootstrapper GUI inicia PowerShell oculto')
add('Setup gráfico autoextraível', "'A','L','P','H','A','S','E','T','U','P','Z','I','P','0','1','!'" in setup_c and 'ZipFileExtensions]::ExtractToFile' in setup_c and 'requireAdministrator' in (ROOT/'native/setup.manifest').read_text(encoding='utf-8'), 'payload anexado, extração controlada e UAC administrativo')
validate_index = setup_c.find('Entrada ZIP escaparia da pasta privada')
extract_index = setup_c.find('ZipFileExtensions]::ExtractToFile')
remove_zip_index = setup_c.find('Remove-Item -LiteralPath $env:ALPHA_PAYLOAD_ZIP -Force;')
checksum_index = setup_c.find("$sum=Join-Path $root 'SHA256SUMS.txt'")
setup_wizard_index = setup_c.find(r"scripts\\Setup-Wizard.ps1")
add('Payload temporário removido antes da validação', min(validate_index, extract_index, remove_zip_index, checksum_index, setup_wizard_index) >= 0 and validate_index < extract_index < remove_zip_index < checksum_index < setup_wizard_index, 'nomes ZIP são validados antes da extração, o ZIP é removido e hashes são conferidos antes dos scripts')
add('Setup temporário privado', 'BCryptGenRandom' in setup_c and 'ConvertStringSecurityDescriptorToSecurityDescriptorW' in setup_c and 'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)' in setup_c, 'RNG criptográfico e ACL restrita')
if major_version >= 3:
    add('Pasta da aplicação usa ACL 3.x FullControl', 'Set-AutoRunnerProductFullControlAcl -Path $Path' in setup and all(t in module for t in ('S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-1-0','S-1-15-2-1','S-1-15-2-2','S-1-3-0','S-1-3-4','FullControl')), 'política de produto 3.x explícita e versionada')
else:
    add('Pasta da aplicação protegida', 'Protect-ApplicationDirectory -Path $Destination' in setup and 'S-1-5-32-545' in setup and 'S-1-1-0' in setup and 'ReadAndExecute' in setup and 'Get-AutoRunnerUnsafeAclEntries' in setup, 'SYSTEM/Admin full; identidades amplas somente RX e escrita ampla rejeitada')
msi=read('build/Build-MSI.ps1')
bridge_c=(ROOT/'native/msi-bridge.c').read_text()
add('Manutenção EXE/MSI separada', "InstallTechnology='EXE'" in setup and 'InstallTechnology" Value="MSI' in msi and 'Start-AutoRunnerApplicationMaintenance' in manager, 'reparo e remoção usam a tecnologia instalada')
add('MSI limpa automação com preservação opcional', 'CleanupAutomation' in msi and 'NOT UPGRADINGPRODUCTCODE' in msi and 'PRESERVEDATA=[PRESERVEDATA]' in msi and 'PRESERVEDATA=1' in bridge_c, 'uninstall controlado sem limpeza durante upgrade')
add('MSI checksum atualizado', 'Payload MSI inválido após regenerar checksums' in msi, 'bridge e cleanup são declarados no manifesto interno')
add('Aplicação instalada separadamente', 'Alpha Software\\SQLBackupAndFTP AutoRunner' in setup and 'SQLBackupAndFTP AutoRunner$' in setup, 'não mistura arquivos com produto de terceiro')
add('Atalho Menu Iniciar', 'Microsoft\\Windows\\Start Menu\\Programs\\Alpha Software' in setup and 'New-Shortcut' in setup, 'atalho comum criado')
add('Atalho Desktop opcional', 'CommonDesktopDirectory' in setup and 'DesktopShortcut' in setup, 'opção implementada')
add('ARP, reparo e remoção', all(t in setup for t in ('UninstallString','QuietUninstallString','ModifyPath','DisplayVersion','EstimatedSize')), 'Aplicativos Instalados completo')
add('Tutorial inicial', all(t in manager for t in ('Show-AutoRunnerTutorial','Não mostrar novamente','Pular','TutorialDoNotShowAgain','TutorialVersion')), 'assistente e preferência por usuário')
add('Ajuda permanente', "$btnHelp=New-ModernButton 'Ajuda e tutorial'" in manager and 'Show-AutoRunnerTutorial' in manager, 'tutorial reabrível')
add('Elevação sob demanda', 'Start-ElevatedManager' in manager and 'Start-ElevatedManager' not in '\n'.join(manager.splitlines()[25:45]) and '-Elevated' in manager, 'interface não exige UAC para abrir')
add('Sem launchers BAT/CMD', not list(ROOT.glob('*.bat')) and not list(ROOT.glob('*.cmd')) and '.bat' not in setup and '.cmd' not in setup, 'distribuição usa EXE')
add('Aplicativo e automação distinguidos', all(t in manager for t in ('Reparar automação','Remover automação','Reparar aplicativo','Desinstalar aplicativo')), 'ações não são ambíguas')
add('Desinstalação com guardas', 'Assert-SafeApplicationPath' in setup and 'Test-AutoRunnerTreeHasReparsePoint' in setup and 'destino diverge do caminho registrado' in setup, 'caminho registrado, sufixo e reparse validados')
add('Automação não apaga SQLBackupAndFTP', 'Os jobs e as configurações do SQLBackupAndFTP não foram alterados' in uninstaller, 'escopo explícito')
add('Pacote exige checksum', 'Test-AutoRunnerPackageChecksums' in setup and 'Integridade do pacote inválida' in setup, 'instalação rejeita adulteração')
add('Setup preservado para manutenção', "SQLBackupAndFTP-AutoRunner-Setup.exe" in setup and 'O instalador não pôde ser preservado' in setup, 'reparo/desinstalação independem do download original')
add('Rollback de atualização', '.rollback-' in setup and 'Restore-ApplicationDirectoryFromUpgradeBackup' in setup and '[IO.Directory]::Move' in setup, 'instalação anterior restaurada em falha')
add('Sem QA de desenvolvimento no app instalado', 'scripts\\Invoke-QA' not in setup, 'runtime de produção reduzido')

# Native safety hardening added after the first RC audit.
for rel, text in (('launcher', launcher_c), ('setup', setup_c), ('msi-bridge', bridge_c)):
    add(f'Buffers nativos limitados: {rel}', 'g_cmd[32768]' in text and 'wcopy_s' in text and 'wappend_s' in text, 'construção de caminhos/comandos respeita o limite do CreateProcessW')
    add(f'Sem cópia nativa ilimitada: {rel}', 'static void wcopy(' not in text and 'static void wappend(' not in text, 'helpers antigos sem capacidade foram removidos')
add('Setup falha fechado sem RNG', 'BCryptGenRandom' in setup_c and 'GetTickCount' not in setup_c and 'GetCurrentProcessId' not in setup_c and 'gerador criptográfico do Windows falhou' in setup_c, 'nome temporário depende exclusivamente do RNG do Windows')
add('Comando nativo com falha controlada', 'append_cmd' in setup_c and 'excedeu o limite seguro do Windows' in setup_c, 'overflow de linha de comando cancela o setup')
add('Temporários PowerShell privados', 'New-SetupPrivateTemporaryDirectory' in setup and 'New-AutoRunnerPrivilegedScratchDirectory' in setup and all(t in module for t in ('function New-AutoRunnerPrivilegedScratchDirectory','DirectorySecurity','SetAccessRuleProtection($true, $false)','S-1-5-18','S-1-5-32-544','Get-AutoRunnerUnsafeAclEntries')), 'Setup delega ao helper canônico SYSTEM/Admin exclusivo')
add('Staging/rollback usam diretório privado', all(t in setup for t in (".stage-",".rollback-","AlphaAutoRunner-IntegrationBackup-","AlphaAutoRunner-Maintenance-")) and 'Protect-ApplicationDirectory -Path $stage' in setup, 'todas as áreas mutáveis críticas usam helper endurecido')
add('Setup preservado somente se autoextraível', 'Test-SetupInstallerExecutable' in setup and "ALPHASETUPZIP01!" in setup and 'Test-SetupInstallerExecutable -Path $InstallerPath' in setup, 'arquivo MZ com trailer/payload válido exigido para manutenção futura')
add('Abertura pós-instalação sem elevação', 'Start-ApplicationUnelevated' in setup and ('Shell.Application' in setup or 'explorer.exe' in setup) and 'Start-ApplicationUnelevated -Path $launcher' in setup, 'primeira abertura usa o shell da sessão em vez do token elevado do setup')
add('Reparo não move instalação', '$registeredDestination=Assert-SafeApplicationPath' in setup and 'O reparo não altera a pasta registrada' in setup and '$txtPath.ReadOnly=$true' in setup and '$browseApp.Enabled=$false' in setup, 'mudança de pasta exige desinstalação explícita')
add('Rollback possui estado transacional', all(t in setup for t in ('$destinationModified=$false','$backupReady=$false','$integrationModified=$false','$settingsModified=$false','$rollbackIssues')) and 'Protect-ApplicationDirectory -Path $Destination' in setup, 'restauração é condicionada ao ponto de mutação e reaplica ACL')
add('Desinstalação diferida privada', '$deferredDirectory=New-SetupPrivateTemporaryDirectory' in setup and 'AlphaAutoRunner-Maintenance-' in setup and 'Start-DeferredInstallerCleanup' in setup, 'setup em uso é copiado para diretório privado e limpo depois')
add('Cópia diferida revalidada', 'Test-SetupInstallerExecutable -Path $deferredSetup' in setup and 'A cópia externa do instalador não passou na validação estrutural' in setup, 'desinstalação não executa cópia temporária truncada ou incompatível')
remove_app=setup.find('Remove-ApplicationDirectorySafe -Path $destination')
remove_shortcut=setup.find('foreach($shortcut in @($startMenuShortcut,$desktopShortcutPath))')
remove_registry=setup.find('foreach($key in @($uninstallKey,$machineKey))')
add('Desinstalação evita instalação órfã', min(remove_app,remove_shortcut,remove_registry) >= 0 and remove_app < remove_shortcut < remove_registry and '$cleanupIssues' in setup, 'arquivos são removidos antes de atalhos/registro e resíduos são reportados')
add('Instalador localiza SQLBackup automaticamente/manual', all(t in setup for t in ('$locateSql','$browseSql','Refresh-InstallerDetection','Select-InstallerSqlBackupFolder','Test-SqlBackupAndFTPDirectory')), 'wizard oferece detecção profunda e seleção de pasta validada')
add('Preferência do SQLBackup persistida no instalador', 'Set-AutoRunnerUserSettings -PreferredSqlBackupPath' in setup and 'DetectionSource' in setup, 'caminho escolhido é reutilizado pelo aplicativo')
add('Aviso de produto ausente antes da instalação', 'O SQLBackupAndFTP ainda não foi localizado' in setup and "'YesNo','Warning'" in setup, 'instalação sem dependência detectada exige decisão consciente')
add('Imports sem aviso de verbos', all('-DisableNameChecking' in read(rel) for rel in ('scripts/Manager.ps1','scripts/Setup-Wizard.ps1','scripts/Install-SQLBackupAndFTP-Auto.ps1','scripts/Uninstall-SQLBackupAndFTP-Auto.ps1','scripts/Run-SQLBackupAndFTPJob.ps1')), 'interface e rotinas não exibem o aviso amarelo de verbos não aprovados')

# Validate PE headers and GUI subsystem directly.
def pe_info(path: Path):
    b=path.read_bytes()
    if b[:2]!=b'MZ': return None
    pe=struct.unpack_from('<I',b,0x3c)[0]
    if b[pe:pe+4]!=b'PE\0\0': return None
    opt=pe+24
    magic=struct.unpack_from('<H',b,opt)[0]
    subsystem=struct.unpack_from('<H',b,opt+(68 if magic==0x20B else 68))[0]
    return {'magic':magic,'subsystem':subsystem,'size':len(b)}
for rel in ('SQLBackupAndFTP-AutoRunner.exe','native/setup-base.exe','native/SQLBackupAndFTP-AutoRunner-MsiBridge.exe'):
    info=pe_info(ROOT/rel)
    add(f'PE GUI válido: {rel}', bool(info and info['magic']==0x20B and info['subsystem']==2), str(info))

out=ROOT/'test-results';out.mkdir(exist_ok=True)
report={'suite':'v22-regression-qa','passed':sum(r['passed'] for r in RESULTS),'failed':sum(not r['passed'] for r in RESULTS),'results':RESULTS}
(out/'v22-regression-qa.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(1 if report['failed'] else 0)
