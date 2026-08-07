#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PayloadRoot,
    [string]$InstallerPath,
    [ValidateSet('Auto','Install','Repair','Uninstall')][string]$Mode='Auto',
    [string]$InstallDir,
    [switch]$Silent,
    [switch]$DesktopShortcut,
    [switch]$LaunchAfterInstall,
    [switch]$DoNotShowTutorial,
    [switch]$PreserveData,
    [switch]$Deferred
)
$setupLogDirectory=Join-Path $env:TEMP 'SQLBackupAndFTPAuto'
$setupLogPath=Join-Path $setupLogDirectory 'setup-startup.log'
try{
    New-Item -ItemType Directory -Path $setupLogDirectory -Force -ErrorAction SilentlyContinue|Out-Null
    Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' START Setup-Wizard.ps1 PID='+$PID) -Encoding UTF8 -ErrorAction SilentlyContinue
    Set-StrictMode -Version 2.0
    $ErrorActionPreference='Stop'
    $module=Join-Path $PayloadRoot 'modules\AutoRunner.Core.psm1'
    if(-not(Test-Path -LiteralPath $module -PathType Leaf)){throw "Pacote inválido: módulo ausente em $module"}
    Import-Module $module -Force -DisableNameChecking
}catch{
    try{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' FATAL '+$_.Exception.ToString()) -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
    throw
}
$version=Get-AutoRunnerVersion
$machineKey=Get-AutoRunnerMachineRegistryPath
$uninstallKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SQLBackupAndFTPAutoRunner'
$startMenuDir=Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Alpha Software'
$startMenuShortcut=Join-Path $startMenuDir 'SQLBackupAndFTP AutoRunner.lnk'
$desktopShortcutPath=Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'SQLBackupAndFTP AutoRunner.lnk'
$supportDir=Get-AutoRunnerDefaultSupportDir
if([string]::IsNullOrWhiteSpace($InstallDir)){
    $base=$env:ProgramFiles
    if([string]::IsNullOrWhiteSpace($base)){$base=${env:ProgramFiles(x86)}}
    $InstallDir=Join-Path $base 'Alpha Software\SQLBackupAndFTP AutoRunner'
}
function Get-InstalledApplication {
    try{
        $item=Get-ItemProperty -LiteralPath $machineKey -ErrorAction Stop
        $dir=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'ApplicationInstallDir' -Default '')
        if($dir){return [pscustomobject]@{InstallDir=$dir;Version=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'ApplicationVersion' -Default '');Installed=(Test-Path -LiteralPath $dir -PathType Container)}}
    }catch{}
    return [pscustomobject]@{InstallDir='';Version='';Installed=$false}
}
function Assert-SafeApplicationPath([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)){throw 'Informe um caminho local absoluto para a instalação.'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root=[IO.Path]::GetPathRoot($full)
    if([string]::IsNullOrWhiteSpace($root) -or $root.StartsWith('\\')){throw 'Instalação em compartilhamento de rede não é permitida.'}
    foreach($protected in @($env:SystemRoot,$env:ProgramData,$env:ProgramFiles,${env:ProgramFiles(x86)},$root)|Where-Object{$_}){
        $protectedFull=[IO.Path]::GetFullPath($protected).TrimEnd('\')
        if($full -ieq $protectedFull){throw "Diretório de instalação inseguro: $full"}
    }
    if($full -notmatch '(?i)Alpha Software\\SQLBackupAndFTP AutoRunner$'){throw 'A pasta de instalação precisa terminar em Alpha Software\SQLBackupAndFTP AutoRunner.'}
    if(Test-AutoRunnerPathHasReparsePoint -Path $full -StopAtPath $root){throw 'A pasta de instalação ou um diretório ancestral contém junction ou link simbólico.'}
    return $full
}
function Remove-ApplicationDirectorySafe([string]$Path,[switch]$IgnoreMissing){
    $safe=Assert-SafeApplicationPath $Path
    if(-not(Test-Path -LiteralPath $safe)){
        if($IgnoreMissing){return}
        throw "Diretório da aplicação não encontrado: $safe"
    }
    $inspection=Get-AutoRunnerTreeInspection -Path $safe
    if(-not $inspection.InspectionSucceeded){throw ('Remoção recusada porque a árvore não pôde ser inspecionada: '+($inspection.Errors -join '; '))}
    if($inspection.HasReparsePoint){throw ('Remoção recusada: a árvore da aplicação contém junction ou link simbólico: '+($inspection.ReparsePoints -join '; '))}
    Remove-AutoRunnerTreeNoFollow -Path $safe
}
function Get-ApplicationProcessesReferencingPath([string]$Path){
    $safe=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $result=New-Object System.Collections.Generic.List[object]
    $rows=$null
    try{$rows=@(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)}
    catch{try{$rows=@(Get-WmiObject -Class Win32_Process -ErrorAction Stop)}catch{$rows=@()}}
    foreach($row in @($rows)){
        $id=[int]$row.ProcessId
        if($id -le 0 -or $id -eq $PID){continue}
        $exe=[string]$row.ExecutablePath
        $cmd=[string]$row.CommandLine
        $references=$false
        if(-not [string]::IsNullOrWhiteSpace($exe)){$references=Test-AutoRunnerPathIsWithin -ChildPath $exe -ParentPath $safe}
        if(-not $references -and -not [string]::IsNullOrWhiteSpace($cmd)){$references=($cmd.IndexOf($safe,[StringComparison]::OrdinalIgnoreCase) -ge 0)}
        if($references){$result.Add([pscustomobject]@{Id=$id;Name=[string]$row.Name;ExecutablePath=$exe;CommandLine=$cmd})}
    }
    if($rows.Count -eq 0){
        foreach($process in @(Get-Process -ErrorAction SilentlyContinue)){
            if($process.Id -eq $PID){continue}
            try{$exe=[string]$process.Path}catch{continue}
            if($exe -and (Test-AutoRunnerPathIsWithin -ChildPath $exe -ParentPath $safe)){$result.Add([pscustomobject]@{Id=$process.Id;Name=$process.ProcessName;ExecutablePath=$exe;CommandLine=''})}
        }
    }
    return @($result|Sort-Object Id -Unique)
}
function Stop-ApplicationProcessesUnderPath([string]$Path){
    $safe=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    for($round=0;$round -lt 4;$round++){
        $references=@(Get-ApplicationProcessesReferencingPath -Path $safe)
        if($references.Count -eq 0){return}
        foreach($process in $references){
            try{Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop}
            catch{throw "Não foi possível encerrar $($process.Name) (PID $($process.Id)), que referencia a instalação anterior: $($_.Exception.Message)"}
        }
        Start-Sleep -Milliseconds 500
    }
    $remaining=@(Get-ApplicationProcessesReferencingPath -Path $safe)
    if($remaining.Count -gt 0){throw ('Processos ainda mantêm a instalação em uso: '+(($remaining|ForEach-Object{"$($_.Name) PID=$($_.Id)"}) -join '; '))}
}
function Invoke-SetupFileSystemRetry([scriptblock]$Operation,[string]$Description,[int]$Attempts=12,[int]$DelayMilliseconds=400){
    $last=$null
    for($attempt=1;$attempt -le $Attempts;$attempt++){
        try{& $Operation;return}
        catch{$last=$_.Exception;if($attempt -ge $Attempts){break};[GC]::Collect();[GC]::WaitForPendingFinalizers();Start-Sleep -Milliseconds $DelayMilliseconds}
    }
    throw "$Description falhou após $Attempts tentativas. Último erro: $($last.Message)"
}
function Get-ApplicationTransactionPath([string]$Destination,[ValidateSet('stage','rollback')][string]$Kind){
    $safe=Assert-SafeApplicationPath $Destination
    $parent=Split-Path -Parent $safe
    $leaf=Split-Path -Leaf $safe
    return Join-Path $parent ('.'+$leaf+'.'+$Kind+'-'+[Guid]::NewGuid().ToString('N'))
}
function Test-ApplicationTransactionPath([string]$Path,[string]$Destination,[ValidateSet('stage','rollback')][string]$Kind){
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    $safe=Assert-SafeApplicationPath $Destination
    $parent=[IO.Path]::GetFullPath((Split-Path -Parent $safe)).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if((Split-Path -Parent $full) -ine $parent){return $false}
    $prefix='.'+(Split-Path -Leaf $safe)+'.'+$Kind+'-'
    $name=Split-Path -Leaf $full
    if(-not $name.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){return $false}
    $suffix=$name.Substring($prefix.Length)
    return ($suffix -match '^[A-Fa-f0-9]{32}$')
}
function Remove-ApplicationTransactionDirectorySafe([string]$Path,[string]$Destination,[ValidateSet('stage','rollback')][string]$Kind){
    if([string]::IsNullOrWhiteSpace($Path) -or -not(Test-Path -LiteralPath $Path)){return}
    if(-not(Test-ApplicationTransactionPath -Path $Path -Destination $Destination -Kind $Kind)){throw "Diretório transacional inesperado: $Path"}
    $inspection=Get-AutoRunnerTreeInspection -Path $Path
    if(-not $inspection.InspectionSucceeded){throw ('Diretório transacional não pôde ser inspecionado: '+($inspection.Errors -join '; '))}
    if($inspection.HasReparsePoint){throw ('Diretório transacional contém junction ou link simbólico: '+($inspection.ReparsePoints -join '; '))}
    Invoke-SetupFileSystemRetry -Description "Remoção de $Kind" -Operation {Remove-AutoRunnerTreeNoFollow -Path $Path}
}
function Move-ApplicationDirectoryAtomic([string]$Source,[string]$Destination,[string]$Description){
    if(Test-Path -LiteralPath $Destination){throw "O destino da operação já existe: $Destination"}
    Invoke-SetupFileSystemRetry -Description $Description -Operation {[IO.Directory]::Move($Source,$Destination)}
}
function New-ApplicationStageDirectory([string]$Destination){
    $stage=Get-ApplicationTransactionPath -Destination $Destination -Kind stage
    $parent=Split-Path -Parent $stage
    New-Item -ItemType Directory -Path $parent -Force|Out-Null
    if(Test-AutoRunnerPathHasReparsePoint -Path $parent -StopAtPath ([IO.Path]::GetPathRoot($parent))){throw "A pasta pai da instalação contém junction ou link simbólico: $parent"}
    [IO.Directory]::CreateDirectory($stage)|Out-Null
    if((Get-Item -LiteralPath $stage -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'O staging foi substituído por um reparse point.'}
    return $stage
}
function Recover-ApplicationTransactionResidue([string]$Destination){
    $safe=Assert-SafeApplicationPath $Destination
    $parent=Split-Path -Parent $safe
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){return}
    $leaf=Split-Path -Leaf $safe
    $stages=@(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop|Where-Object{$_.Name.StartsWith('.'+$leaf+'.stage-',[StringComparison]::OrdinalIgnoreCase)})
    $backups=@(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop|Where-Object{$_.Name.StartsWith('.'+$leaf+'.rollback-',[StringComparison]::OrdinalIgnoreCase)})
    foreach($stage in $stages){Remove-ApplicationTransactionDirectorySafe -Path $stage.FullName -Destination $safe -Kind stage}
    if(-not(Test-Path -LiteralPath $safe -PathType Container)){
        if($backups.Count -gt 1){throw 'Existem múltiplos backups de rollback e a instalação principal está ausente. Intervenção manual necessária.'}
        if($backups.Count -eq 1){Move-ApplicationDirectoryAtomic -Source $backups[0].FullName -Destination $safe -Description 'Recuperação automática da instalação anterior';return}
    }
    foreach($backup in $backups){Remove-ApplicationTransactionDirectorySafe -Path $backup.FullName -Destination $safe -Kind rollback}
}
function Move-ApplicationDirectoryForUpgrade([string]$Path){
    $safe=Assert-SafeApplicationPath $Path
    if(-not(Test-Path -LiteralPath $safe -PathType Container)){return $null}
    $inspection=Get-AutoRunnerTreeInspection -Path $safe
    if(-not $inspection.InspectionSucceeded){throw ('Atualização recusada porque a instalação anterior não pôde ser inspecionada: '+($inspection.Errors -join '; '))}
    if($inspection.HasReparsePoint){throw ('Atualização recusada: a instalação anterior contém junction ou link simbólico: '+($inspection.ReparsePoints -join '; '))}
    Stop-ApplicationProcessesUnderPath -Path $safe
    $backup=Get-ApplicationTransactionPath -Destination $safe -Kind rollback
    Move-ApplicationDirectoryAtomic -Source $safe -Destination $backup -Description 'Renomeação da instalação anterior para rollback'
    return $backup
}
function Restore-ApplicationDirectoryFromUpgradeBackup([string]$BackupPath,[string]$Destination){
    if([string]::IsNullOrWhiteSpace($BackupPath) -or -not(Test-Path -LiteralPath $BackupPath -PathType Container)){throw 'Backup de atualização ausente para rollback.'}
    $safe=Assert-SafeApplicationPath $Destination
    if(-not(Test-ApplicationTransactionPath -Path $BackupPath -Destination $safe -Kind rollback)){throw "Caminho de rollback inesperado: $BackupPath"}
    if(Test-Path -LiteralPath $safe){Remove-ApplicationDirectorySafe -Path $safe}
    Move-ApplicationDirectoryAtomic -Source $BackupPath -Destination $safe -Description 'Restauração da instalação anterior'
}
function Remove-ApplicationUpgradeBackupSafe([string]$BackupPath,[string]$Destination){
    Remove-ApplicationTransactionDirectorySafe -Path $BackupPath -Destination $Destination -Kind rollback
}
function Remove-SetupTemporaryDirectorySafe([string]$Path,[string[]]$AllowedPrefixes){
    Remove-AutoRunnerPrivilegedScratchDirectory -Path $Path -AllowedPrefixes $AllowedPrefixes
}
function New-SetupPrivateTemporaryDirectory([string]$Prefix){
    return New-AutoRunnerPrivilegedScratchDirectory -Prefix $Prefix
}
function Test-SetupInstallerExecutable([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path) -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
    $stream=$null
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if($stream.Length -lt 26){return $false}
        $header=New-Object byte[] 2
        if($stream.Read($header,0,2) -ne 2 -or $header[0] -ne 0x4D -or $header[1] -ne 0x5A){return $false}
        [void]$stream.Seek(-24,[IO.SeekOrigin]::End)
        $trailer=New-Object byte[] 24
        if($stream.Read($trailer,0,24) -ne 24){return $false}
        $expected=[Text.Encoding]::ASCII.GetBytes('ALPHASETUPZIP01!')
        for($index=0;$index -lt 16;$index++){if($trailer[$index] -ne $expected[$index]){return $false}}
        $payloadSize=[BitConverter]::ToUInt64($trailer,16)
        return ($payloadSize -gt 0 -and $payloadSize -le [uint64]($stream.Length-24))
    }catch{return $false}
    finally{if($stream){$stream.Dispose()}}
}
function Test-ApplicationInterfaceProcess([string]$InstallRoot){
    $safe=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    try{
        foreach($row in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='SQLBackupAndFTP-AutoRunner.exe'" -ErrorAction SilentlyContinue)){
            $exe=[string](Get-AutoRunnerPropertyValue -InputObject $row -Name 'ExecutablePath' -Default '')
            $cmd=[string](Get-AutoRunnerPropertyValue -InputObject $row -Name 'CommandLine' -Default '')
            if($exe -and (Test-AutoRunnerPathIsWithin -ChildPath $exe -ParentPath $safe)){return $true}
            if($cmd -and $cmd.IndexOf((Join-Path $safe 'scripts\Manager.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0){return $true}
        }
    }catch{}
    return $false
}
function Start-ApplicationUnelevated([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Aplicativo não encontrado: $Path"}
    $installRoot=Split-Path -Parent $Path
    $shell=$null
    try{
        # O Explorer funciona como broker para remover o token elevado do Setup.
        # ShellExecute não retorna um código confiável via COM, então a 2.3.5 também
        # confirma que a interface realmente apareceu antes de dizer que abriu.
        $shell=New-Object -ComObject Shell.Application
        $shell.ShellExecute($Path,'',$installRoot,'open',1)
    }finally{
        if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    }
    $deadline=(Get-Date).AddSeconds(7)
    do{
        if(Test-ApplicationInterfaceProcess -InstallRoot $installRoot){return $true}
        Start-Sleep -Milliseconds 250
    }while((Get-Date)-lt $deadline)
    throw 'O aplicativo foi instalado, mas o Windows não confirmou a inicialização da interface. Use Reparar ou consulte os logs em %TEMP%\SQLBackupAndFTPAuto.'
}
function Protect-ApplicationDirectory([string]$Path){
    if(-not(Test-AutoRunnerAdministrator)){throw 'Administrador necessário para aplicar a política ACL 3.0.0-RC.'}
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){throw "Pasta da aplicação não encontrada: $Path"}
    [void](Set-AutoRunnerProductFullControlAcl -Path $Path)
    foreach($requiredFile in @(
        (Join-Path $Path 'SQLBackupAndFTP-AutoRunner.exe'),
        (Join-Path $Path 'SQLBackupAndFTP-AutoRunner-Setup.exe'),
        (Join-Path $Path 'assets\AutoRunner.ico'),
        (Join-Path $Path 'assets\AutoRunner.png'),
        (Join-Path $Path 'scripts\Manager.ps1'),
        (Join-Path $Path 'agent\remote-control\AutoRunner.RemoteAgent.ps1')
    )){if(-not(Test-Path -LiteralPath $requiredFile -PathType Leaf)){throw "Arquivo obrigatório ausente após instalação: $requiredFile"}}
    foreach($executable in @((Join-Path $Path 'SQLBackupAndFTP-AutoRunner.exe'),(Join-Path $Path 'SQLBackupAndFTP-AutoRunner-Setup.exe'))){
        $executionSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath $executable -AllowProductFullControlPolicy
        if(-not $executionSecurity.IsSafe){throw ('Caminho da aplicação não atende a política 3.0.0-RC: '+($executionSecurity.Issues -join '; '))}
    }
}

function New-Shortcut([string]$Path,[string]$Target,[string]$WorkingDirectory,[string]$Icon){
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force|Out-Null
    $shell=$null;$shortcut=$null
    try{
        $shell=New-Object -ComObject WScript.Shell
        $shortcut=$shell.CreateShortcut($Path)
        $shortcut.TargetPath=$Target
        $shortcut.WorkingDirectory=$WorkingDirectory
        $shortcut.Description='Gerenciar SQLBackupAndFTP AutoRunner'
        $shortcut.IconLocation=($Target+',0')
        $shortcut.Save()
    }finally{
        if($shortcut){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)}
        if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    }
}
function Write-ApplicationRegistry([string]$Destination,[bool]$HasDesktopShortcut){
    New-Item -Path $machineKey -Force|Out-Null
    foreach($entry in ([ordered]@{ApplicationInstallDir=$Destination;ApplicationVersion=$version;SetupPath=(Join-Path $Destination 'SQLBackupAndFTP-AutoRunner-Setup.exe');InstallTechnology='EXE';MsiProductCode='';InstalledAtUtc=[DateTime]::UtcNow.ToString('o')}).GetEnumerator()){
        New-ItemProperty -Path $machineKey -Name $entry.Key -Value $entry.Value -PropertyType String -Force|Out-Null
    }
    New-ItemProperty -Path $machineKey -Name DesktopShortcut -Value $(if($HasDesktopShortcut){1}else{0}) -PropertyType DWord -Force|Out-Null
    New-Item -Path $uninstallKey -Force|Out-Null
    $setup=Join-Path $Destination 'SQLBackupAndFTP-AutoRunner-Setup.exe'
    $uninstall='"'+$setup+'" /uninstall'
    $repair='"'+$setup+'" /repair'
    foreach($entry in ([ordered]@{
        DisplayName='SQLBackupAndFTP AutoRunner';DisplayVersion=$version;Publisher='Alpha Software';InstallLocation=$Destination;DisplayIcon=((Join-Path $Destination 'SQLBackupAndFTP-AutoRunner.exe')+',0');UninstallString=$uninstall;QuietUninstallString=($uninstall+' /silent');ModifyPath=$repair;InstallDate=(Get-Date -Format 'yyyyMMdd')
    }).GetEnumerator()){
        New-ItemProperty -Path $uninstallKey -Name $entry.Key -Value $entry.Value -PropertyType String -Force|Out-Null
    }
    $sum=(Get-ChildItem -LiteralPath $Destination -Recurse -File -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
    New-ItemProperty -Path $uninstallKey -Name EstimatedSize -Value ([int][Math]::Ceiling(([int64]$sum)/1KB)) -PropertyType DWord -Force|Out-Null
    New-ItemProperty -Path $uninstallKey -Name NoModify -Value 0 -PropertyType DWord -Force|Out-Null
    New-ItemProperty -Path $uninstallKey -Name NoRepair -Value 0 -PropertyType DWord -Force|Out-Null
}
function Get-ApplicationFiles {
    $include=@('SQLBackupAndFTP-AutoRunner.exe','README.md','CHANGELOG.md','VERSION','RELEASE_CHANNEL','LICENSE','SECURITY.md','SUPPORT.md')
    $files=New-Object System.Collections.Generic.List[object]
    foreach($relative in $include){$p=Join-Path $PayloadRoot $relative;if(Test-Path -LiteralPath $p -PathType Leaf){$files.Add([pscustomobject]@{Source=$p;Relative=$relative})}}
    foreach($dirName in @('assets','modules','scripts','docs','agent')){
        $dir=Join-Path $PayloadRoot $dirName
        if(Test-Path -LiteralPath $dir -PathType Container){
            foreach($file in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)){
                if($file.Name -match '(?i)\.(log|tmp|bak|pyc)$'){continue}
                $rel=$file.FullName.Substring($PayloadRoot.Length).TrimStart('\')
                if($rel -match '(?i)^(scripts\\Setup-Wizard\.ps1|scripts\\Install-SQLBackupAndFTP-Auto\.ps1|scripts\\Uninstall-SQLBackupAndFTP-Auto\.ps1|scripts\\Manager\.ps1|scripts\\Run-SQLBackupAndFTPJob\.ps1|scripts\\Export-Diagnostics\.ps1|scripts\\Update-AutoRunner\.ps1|scripts\\Check-Updates\.ps1|modules\\|assets\\|docs\\|agent\\remote-control\\)'){$files.Add([pscustomobject]@{Source=$file.FullName;Relative=$rel})}
            }
        }
    }
    return @($files|Sort-Object Relative -Unique)
}
function Install-Application([string]$Destination,[bool]$CreateDesktop,[bool]$Launch,[bool]$HideTutorial){
    $installedBefore=Get-InstalledApplication
    $wasInstalled=$installedBefore.Installed
    if(-not(Test-AutoRunnerAdministrator)){throw 'A instalação exige privilégios de administrador.'}
    $Destination=Assert-SafeApplicationPath $Destination
    if($wasInstalled){
        $registeredDestination=Assert-SafeApplicationPath ([string]$installedBefore.InstallDir)
        if($Destination -ine $registeredDestination){throw 'Para mover o aplicativo, desinstale e instale novamente. O reparo não altera a pasta registrada.'}
    }
    $launcherSource=Join-Path $PayloadRoot 'SQLBackupAndFTP-AutoRunner.exe'
    if(-not(Test-Path -LiteralPath $launcherSource -PathType Leaf)){throw 'Launcher executável não encontrado no pacote.'}
    $packageCheck=Test-AutoRunnerPackageChecksums -RootPath $PayloadRoot
    if(-not $packageCheck.IsPresent){throw 'Pacote sem inventário SHA256SUMS.txt.'}
    if(-not $packageCheck.IsValid){throw ('Integridade do pacote inválida: '+($packageCheck.Issues -join '; '))}

    Recover-ApplicationTransactionResidue -Destination $Destination
    $stage=$null;$backup=$null;$integrationBackup=$null
    $regExe=Join-Path $env:SystemRoot 'System32\reg.exe'
    $machineRegFile=$null;$uninstallRegFile=$null
    $hadMachineKey=Test-Path -LiteralPath $machineKey
    $hadUninstallKey=Test-Path -LiteralPath $uninstallKey
    $oldUserSettings=Get-AutoRunnerUserSettings
    $destinationModified=$false;$backupReady=$false;$integrationModified=$false;$settingsModified=$false
    try{
        $stage=New-ApplicationStageDirectory -Destination $Destination
        $integrationBackup=New-SetupPrivateTemporaryDirectory -Prefix 'AlphaAutoRunner-IntegrationBackup-'
        $machineRegFile=Join-Path $integrationBackup 'machine.reg'
        $uninstallRegFile=Join-Path $integrationBackup 'uninstall.reg'
        if($hadMachineKey){& $regExe export 'HKLM\Software\Alpha Software\SQLBackupAndFTP AutoRunner' $machineRegFile /y|Out-Null;if($LASTEXITCODE -ne 0){throw 'Falha ao preservar o registro da aplicação.'}}
        if($hadUninstallKey){& $regExe export 'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\SQLBackupAndFTPAutoRunner' $uninstallRegFile /y|Out-Null;if($LASTEXITCODE -ne 0){throw 'Falha ao preservar o registro de desinstalação.'}}
        if(Test-Path -LiteralPath $startMenuShortcut){Copy-Item -LiteralPath $startMenuShortcut -Destination (Join-Path $integrationBackup 'start.lnk') -Force}
        if(Test-Path -LiteralPath $desktopShortcutPath){Copy-Item -LiteralPath $desktopShortcutPath -Destination (Join-Path $integrationBackup 'desktop.lnk') -Force}

        foreach($file in @(Get-ApplicationFiles)){
            $target=Join-Path $stage $file.Relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
            Copy-Item -LiteralPath $file.Source -Destination $target -Force
        }
        if($InstallerPath -and (Test-SetupInstallerExecutable -Path $InstallerPath)){Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $stage 'SQLBackupAndFTP-AutoRunner-Setup.exe') -Force}
        if(-not(Test-Path -LiteralPath (Join-Path $stage 'SQLBackupAndFTP-AutoRunner-Setup.exe') -PathType Leaf)){throw 'O instalador não pôde ser preservado para reparo e desinstalação.'}
        if(Test-AutoRunnerTreeHasReparsePoint -Path $stage){throw 'Staging contém link simbólico ou junction.'}
        Protect-ApplicationDirectory -Path $stage

        if(Test-Path -LiteralPath $Destination -PathType Container){$backup=Move-ApplicationDirectoryForUpgrade -Path $Destination;$backupReady=($null -ne $backup)}
        Move-ApplicationDirectoryAtomic -Source $stage -Destination $Destination -Description 'Promoção atômica da nova instalação'
        $stage=$null;$destinationModified=$true
        Protect-ApplicationDirectory -Path $Destination

        $launcher=Join-Path $Destination 'SQLBackupAndFTP-AutoRunner.exe'
        $icon=Join-Path $Destination 'assets\AutoRunner.ico'
        $integrationModified=$true
        New-Shortcut -Path $startMenuShortcut -Target $launcher -WorkingDirectory $Destination -Icon $icon
        if($CreateDesktop){New-Shortcut -Path $desktopShortcutPath -Target $launcher -WorkingDirectory $Destination -Icon $icon}else{Remove-Item -LiteralPath $desktopShortcutPath -Force -ErrorAction SilentlyContinue}
        Write-ApplicationRegistry -Destination $Destination -HasDesktopShortcut $CreateDesktop
        $settingsModified=$true
        if($wasInstalled){Set-AutoRunnerUserSettings -TutorialDoNotShowAgain $HideTutorial -TutorialVersion $version}
        else{Set-AutoRunnerUserSettings -TutorialDoNotShowAgain $HideTutorial -TutorialCompleted $false -TutorialVersion $version}
        try{Get-SqlBackupAndFTPInstall -DeepSearch -AllowNotFound -SavePreference|Out-Null}catch{}

        if($backupReady -and $backup -and (Test-Path -LiteralPath $backup)){
            Remove-ApplicationUpgradeBackupSafe -BackupPath $backup -Destination $Destination
            $backupReady=$false;$backup=$null
        }
        if($Launch){try{[void](Start-ApplicationUnelevated -Path $launcher)}catch{$script:SetupPostInstallWarning='Aplicativo instalado, porém a abertura automática falhou: '+$_.Exception.Message;Write-Warning $script:SetupPostInstallWarning}}
    }catch{
        $originalException=$_.Exception
        $rollbackIssues=New-Object System.Collections.Generic.List[string]
        try{
            if($destinationModified -and (Test-Path -LiteralPath $Destination)){Remove-ApplicationDirectorySafe -Path $Destination -IgnoreMissing}
            if($backupReady -and $backup){Restore-ApplicationDirectoryFromUpgradeBackup -BackupPath $backup -Destination $Destination;$backupReady=$false;$backup=$null}
        }catch{$rollbackIssues.Add('aplicação: '+$_.Exception.Message)}
        if($integrationModified){
            try{
                Remove-Item -LiteralPath $machineKey -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
                if($hadMachineKey -and $machineRegFile -and (Test-Path -LiteralPath $machineRegFile)){& $regExe import $machineRegFile|Out-Null;if($LASTEXITCODE -ne 0){throw 'Falha ao restaurar registro da aplicação.'}}
                if($hadUninstallKey -and $uninstallRegFile -and (Test-Path -LiteralPath $uninstallRegFile)){& $regExe import $uninstallRegFile|Out-Null;if($LASTEXITCODE -ne 0){throw 'Falha ao restaurar registro de desinstalação.'}}
                Remove-Item -LiteralPath $startMenuShortcut -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $desktopShortcutPath -Force -ErrorAction SilentlyContinue
                if($hadMachineKey -and $integrationBackup -and (Test-Path -LiteralPath (Join-Path $integrationBackup 'start.lnk'))){New-Item -ItemType Directory -Path (Split-Path -Parent $startMenuShortcut) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $integrationBackup 'start.lnk') -Destination $startMenuShortcut -Force}
                if($integrationBackup -and (Test-Path -LiteralPath (Join-Path $integrationBackup 'desktop.lnk'))){Copy-Item -LiteralPath (Join-Path $integrationBackup 'desktop.lnk') -Destination $desktopShortcutPath -Force}
            }catch{$rollbackIssues.Add('integrações: '+$_.Exception.Message)}
        }
        if($settingsModified){try{Set-AutoRunnerUserSettings -PreferredSqlBackupPath $oldUserSettings.PreferredSqlBackupPath -PreferredSqlBackupCliPath $oldUserSettings.PreferredSqlBackupCliPath -PreferredSqlBackupAppPath $oldUserSettings.PreferredSqlBackupAppPath -DetectionSource $oldUserSettings.DetectionSource -TutorialCompleted ([bool]$oldUserSettings.TutorialCompleted) -TutorialDoNotShowAgain ([bool]$oldUserSettings.TutorialDoNotShowAgain) -TutorialVersion $oldUserSettings.TutorialVersion}catch{$rollbackIssues.Add('preferências: '+$_.Exception.Message)}}
        if($rollbackIssues.Count -gt 0){throw ('A instalação falhou: '+$originalException.Message+' | O rollback ficou incompleto: '+($rollbackIssues -join '; '))}
        throw $originalException
    }finally{
        if($stage){try{Remove-ApplicationTransactionDirectorySafe -Path $stage -Destination $Destination -Kind stage}catch{Write-Warning $_.Exception.Message}}
        try{Remove-SetupTemporaryDirectorySafe -Path $integrationBackup -AllowedPrefixes @('AlphaAutoRunner-IntegrationBackup-')}catch{Write-Warning $_.Exception.Message}
    }
}
function Uninstall-Application([bool]$KeepData){
    if(-not(Test-AutoRunnerAdministrator)){throw 'A desinstalação exige privilégios de administrador.'}
    $installed=Get-InstalledApplication
    $destination=[string]$installed.InstallDir
    if([string]::IsNullOrWhiteSpace($destination) -and -not [string]::IsNullOrWhiteSpace($InstallDir) -and (Test-Path -LiteralPath $InstallDir -PathType Container)){
        $destination=$InstallDir
    }
    if($destination){$destination=Assert-SafeApplicationPath $destination}

    # O agente remoto tem tarefa própria em execução como SYSTEM. Pare e remova essa
    # tarefa antes de excluir o diretório da aplicação, senão a desinstalação pode
    # deixar um processo órfão apontando para arquivos que acabaram de desaparecer.
    if($destination){
        $remoteAgent=Join-Path $destination 'agent\remote-control\AutoRunner.RemoteAgent.ps1'
        if(Test-Path -LiteralPath $remoteAgent -PathType Leaf){
            $agentArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$remoteAgent,'-UninstallTask')
            $agentProcess=Start-Process -FilePath (Get-AutoRunnerWindowsPowerShellPath) -ArgumentList (Join-AutoRunnerProcessArguments -Arguments $agentArgs) -Wait -PassThru -WindowStyle Hidden
            try{$agentProcess.Refresh()}catch{}
            if($agentProcess.ExitCode -ne 0){throw "Falha ao remover o Remote Agent. Código $($agentProcess.ExitCode)."}
        }
    }

    # Primeiro retire a tarefa e os arquivos da aplicação. Atalhos e registro são
    # removidos somente depois que a fronteira destrutiva principal termina. Assim,
    # uma falha de ACL/arquivo em uso não transforma uma instalação ainda existente
    # em uma instalação órfã e invisível em Aplicativos Instalados.
    $uninstaller=if($destination){Join-Path $destination 'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1'}else{$null}
    if($uninstaller -and (Test-Path -LiteralPath $uninstaller)){
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$uninstaller,'-SupportDir',$supportDir,'-Quiet')
        if($KeepData){$args+='-KeepDiagnostics'}
        $process=Start-Process -FilePath (Get-AutoRunnerWindowsPowerShellPath) -ArgumentList (Join-AutoRunnerProcessArguments -Arguments $args) -Wait -PassThru -WindowStyle Hidden
        try{$process.WaitForExit()}catch{}
        try{$process.Refresh()}catch{}
        $uninstallExit=$null
        try{$uninstallExit=[int]$process.ExitCode}catch{}
        if($null -eq $uninstallExit){$uninstallExit=1}
        if($uninstallExit -eq -1){
            # ShellExecute/PowerShell 5.1 can expose -1 even after a successful child.
            # Trust the observable postcondition only when both config and task are gone.
            Start-Sleep -Milliseconds 350
            $remaining=Get-AutoRunnerInstalledState -SupportDir $supportDir -TaskName 'SQLBackupAndFTP AutoRunner' -TaskPath '\SQLBackupAndFTPAuto\'
            if(-not $remaining.HasConfiguration -and -not $remaining.HasTask){$uninstallExit=0}
        }
        if($uninstallExit -ne 0){throw "Falha ao remover a automação. Código $uninstallExit."}
    }
    if($destination -and (Test-Path -LiteralPath $destination)){
        $registered=[string]$installed.InstallDir
        if(-not [string]::IsNullOrWhiteSpace($registered)){
            $registered=[IO.Path]::GetFullPath($registered).TrimEnd('\')
            if(-not($destination -ieq $registered)){throw 'Remoção recusada: o destino diverge do caminho registrado.'}
        }else{
            $expected=Assert-SafeApplicationPath $InstallDir
            if(-not($destination -ieq $expected)){throw 'Remoção recusada: o destino sem Registro diverge do caminho de manutenção validado.'}
        }
        if(Test-AutoRunnerTreeHasReparsePoint -Path $destination){throw 'Remoção recusada: instalação contém junction ou link simbólico.'}
        Remove-ApplicationDirectorySafe -Path $destination
    }

    $cleanupIssues=New-Object System.Collections.Generic.List[string]
    foreach($shortcut in @($startMenuShortcut,$desktopShortcutPath)){
        try{Remove-Item -LiteralPath $shortcut -Force -ErrorAction Stop}catch{if(Test-Path -LiteralPath $shortcut){$cleanupIssues.Add('atalho '+$shortcut+': '+$_.Exception.Message)}}
    }
    foreach($key in @($uninstallKey,$machineKey)){
        try{Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop}catch{if(Test-Path -LiteralPath $key){$cleanupIssues.Add('registro '+$key+': '+$_.Exception.Message)}}
    }
    if(-not $KeepData -and (Test-Path -LiteralPath $supportDir)){
        try{
            if(-not(Test-AutoRunnerSupportPath -Path $supportDir)){throw 'diretório de suporte inválido'}
            if(Test-AutoRunnerTreeHasReparsePoint -Path $supportDir){throw 'suporte contém junction ou link simbólico'}
            Remove-Item -LiteralPath $supportDir -Recurse -Force -ErrorAction Stop
        }catch{$cleanupIssues.Add('dados operacionais: '+$_.Exception.Message)}
    }
    if($cleanupIssues.Count -gt 0){throw ('A aplicação foi removida, mas a limpeza de integrações ficou incompleta: '+($cleanupIssues -join '; '))}
}
function Invoke-SelectedMode([string]$SelectedMode,[string]$Destination,[bool]$CreateDesktop,[bool]$Launch,[bool]$HideTutorial,[bool]$KeepData){
    switch($SelectedMode){
        'Install'{Install-Application $Destination $CreateDesktop $Launch $HideTutorial}
        'Repair'{Install-Application $Destination $CreateDesktop $Launch $HideTutorial}
        'Uninstall'{Uninstall-Application $KeepData}
        default{throw "Modo inválido: $SelectedMode"}
    }
}
if(-not(Test-AutoRunnerAdministrator)){
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-PayloadRoot',$PayloadRoot,'-InstallerPath',$InstallerPath,'-Mode',$Mode,'-InstallDir',$InstallDir)
    if($Silent){$arguments+='-Silent'};if($DesktopShortcut){$arguments+='-DesktopShortcut'};if($LaunchAfterInstall){$arguments+='-LaunchAfterInstall'};if($DoNotShowTutorial){$arguments+='-DoNotShowTutorial'};if($PreserveData){$arguments+='-PreserveData'};if($Deferred){$arguments+='-Deferred'}
    $p=Start-Process -FilePath (Get-AutoRunnerWindowsPowerShellPath) -ArgumentList (Join-AutoRunnerProcessArguments -Arguments $arguments) -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}
$script:SetupMutex=$null
try{
    $created=$false
    $script:SetupMutex=New-Object Threading.Mutex($false,'Global\AlphaSoftware.SQLBackupAndFTPAutoRunner.Setup',[ref]$created)
    $setupMutexTaken=$false
    try{$setupMutexTaken=$script:SetupMutex.WaitOne(0,$false)}catch [Threading.AbandonedMutexException]{$setupMutexTaken=$true}
    if(-not $setupMutexTaken){throw 'Outra instalação, reparação ou desinstalação do AutoRunner já está em andamento.'}
}catch{throw}
$installedApp=Get-InstalledApplication
$maintenanceRoot=''
if($installedApp.Installed -and -not [string]::IsNullOrWhiteSpace([string]$installedApp.InstallDir)){
    $maintenanceRoot=Assert-SafeApplicationPath ([string]$installedApp.InstallDir)
}elseif($InstallerPath){
    # Recuperação para Registro ausente/corrompido no caminho padrão. Sem isso, o
    # Setup preservado poderia tentar mover a própria pasta e repetir o acesso negado.
    try{
        $candidate=[IO.Path]::GetFullPath((Split-Path -Parent $InstallerPath)).TrimEnd('\')
        $defaultCandidate=Assert-SafeApplicationPath $InstallDir
        if($candidate -ieq $defaultCandidate -and (Test-Path -LiteralPath (Join-Path $candidate 'SQLBackupAndFTP-AutoRunner.exe') -PathType Leaf)){
            $maintenanceRoot=$candidate
        }
    }catch{}
}

# O instalador preservado fica dentro da pasta do aplicativo. Reparar, atualizar
# ou desinstalar a partir desse executável manteria a própria pasta aberta e pode
# fazer Directory.Move falhar com acesso negado. Toda manutenção interna é
# relançada de uma cópia privada externa e a instância original encerra primeiro.
if($maintenanceRoot -and $InstallerPath){
    $installerFull=[IO.Path]::GetFullPath($InstallerPath)
    $installedFull=[IO.Path]::GetFullPath($maintenanceRoot).TrimEnd('\')
    $installerInside=Test-AutoRunnerPathIsWithin -ChildPath $installerFull -ParentPath $installedFull
    if($installerInside -and -not $Deferred){
        $deferredDirectory=New-SetupPrivateTemporaryDirectory -Prefix 'AlphaAutoRunner-Maintenance-'
        $deferredSetup=Join-Path $deferredDirectory 'SQLBackupAndFTP-AutoRunner-Setup.exe'
        try{
            Copy-Item -LiteralPath $installerFull -Destination $deferredSetup -Force
            if(-not(Test-SetupInstallerExecutable -Path $deferredSetup)){throw 'A cópia externa do instalador não passou na validação estrutural.'}
            $originalHash=(Get-FileHash -LiteralPath $installerFull -Algorithm SHA256).Hash
            $deferredHash=(Get-FileHash -LiteralPath $deferredSetup -Algorithm SHA256).Hash
            if($originalHash -ne $deferredHash){throw 'A cópia externa do instalador divergiu no SHA-256.'}
            $effectiveMode=if($Mode -eq 'Uninstall'){'/uninstall'}else{'/repair'}
            $deferredArgs=@($effectiveMode,'/deferred')
            if($Silent){$deferredArgs+='/silent'}
            if($DesktopShortcut){$deferredArgs+='/desktop'}
            if(-not $LaunchAfterInstall){$deferredArgs+='/nolaunch'}
            if(-not $PreserveData){$deferredArgs+='/purgedata'}
            if($DoNotShowTutorial){$deferredArgs+='/notutorial'}
            Start-Process -FilePath $deferredSetup -ArgumentList (Join-AutoRunnerProcessArguments -Arguments $deferredArgs) -ErrorAction Stop|Out-Null
        }catch{
            try{Remove-SetupTemporaryDirectorySafe -Path $deferredDirectory -AllowedPrefixes @('AlphaAutoRunner-Maintenance-')}catch{}
            throw
        }
        exit 0
    }
    if($Deferred){
        $deadline=(Get-Date).AddSeconds(60)
        $originalSetup=Join-Path $installedFull 'SQLBackupAndFTP-AutoRunner-Setup.exe'
        do{
            $originalRunning=$false
            $rows=$null
            try{$rows=@(Get-CimInstance Win32_Process -ErrorAction Stop)}catch{try{$rows=@(Get-WmiObject Win32_Process -ErrorAction Stop)}catch{$rows=@()}}
            foreach($process in @($rows)){
                $exe=[string](Get-AutoRunnerPropertyValue -InputObject $process -Name 'ExecutablePath' -Default '')
                if($exe -and $exe -ieq $originalSetup){$originalRunning=$true;break}
            }
            if($originalRunning){Start-Sleep -Milliseconds 500}
        }while($originalRunning -and (Get-Date)-lt $deadline)
        if($originalRunning){throw 'A instância original do instalador não encerrou no prazo; manutenção cancelada com segurança.'}
    }
}
if($maintenanceRoot){$InstallDir=$maintenanceRoot}
elseif($installedApp.Installed -and -not [string]::IsNullOrWhiteSpace([string]$installedApp.InstallDir)){$InstallDir=$installedApp.InstallDir}
if($Mode -eq 'Auto'){$Mode=if($installedApp.Installed -or $maintenanceRoot){'Repair'}else{'Install'}}

function Start-DeferredInstallerCleanup {
    if(-not $Deferred -or [string]::IsNullOrWhiteSpace($InstallerPath)){return}
    try{
        $full=[IO.Path]::GetFullPath($InstallerPath)
        $directory=[IO.Path]::GetFullPath((Split-Path -Parent $full)).TrimEnd('\')
        $programFiles=[IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
        $parent=[IO.Path]::GetFullPath((Split-Path -Parent $directory)).TrimEnd('\')
        $leaf=Split-Path -Leaf $directory
        $validName=$false
        foreach($prefix in @('AlphaAutoRunner-Maintenance-','AlphaAutoRunner-Uninstall-')){
            if($leaf.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
                $suffix=$leaf.Substring($prefix.Length)
                if($suffix -match '^[A-Fa-f0-9]{32}$'){$validName=$true;break}
            }
        }
        if($parent -ine $programFiles -or -not $validName){return}
        if(Test-AutoRunnerTreeHasReparsePoint -Path $directory){return}
        $quoted=$directory.Replace("'","''")
        $cleanupCommand="`$ErrorActionPreference='SilentlyContinue';for(`$i=0;`$i -lt 60;`$i++){Remove-Item -LiteralPath '$quoted' -Recurse -Force -ErrorAction SilentlyContinue;if(-not(Test-Path -LiteralPath '$quoted')){break};Start-Sleep -Milliseconds 500}"
        Start-Process -FilePath (Get-AutoRunnerWindowsPowerShellPath) -ArgumentList (Join-AutoRunnerProcessArguments -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-Command',$cleanupCommand)) -WindowStyle Hidden|Out-Null
    }catch{}
}
if($Silent){
    Invoke-SelectedMode $Mode $InstallDir ([bool]$DesktopShortcut) ([bool]$LaunchAfterInstall) ([bool]$DoNotShowTutorial) ([bool]$PreserveData)
    Start-DeferredInstallerCleanup
    exit 0
}
$script:SetupOperationAttempted=$false
$script:SetupOperationSucceeded=$false
$script:SetupPostInstallWarning=''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
try{[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)}catch{}
if(-not ('AlphaSoftware.AutoRunner.SetupNativeUi' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AlphaSoftware.AutoRunner {
[StructLayout(LayoutKind.Sequential, Pack=4)]
public struct SetupPropertyKey {
    public Guid formatId; public uint propertyId;
    public SetupPropertyKey(Guid formatId,uint propertyId){this.formatId=formatId;this.propertyId=propertyId;}
}
[StructLayout(LayoutKind.Explicit)]
public struct SetupPropVariant {
    [FieldOffset(0)] public ushort valueType;
    [FieldOffset(8)] public IntPtr pointerValue;
}
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ISetupPropertyStore {
    [PreserveSig] int GetCount(out uint cProps);
    [PreserveSig] int GetAt(uint iProp,out SetupPropertyKey pkey);
    [PreserveSig] int GetValue(ref SetupPropertyKey key,out SetupPropVariant pv);
    [PreserveSig] int SetValue(ref SetupPropertyKey key,ref SetupPropVariant pv);
    [PreserveSig] int Commit();
}
public static class SetupNativeUi {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", EntryPoint="SetProcessDpiAwarenessContext")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shell32.dll", PreserveSig=true)] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd,ref Guid iid,out ISetupPropertyStore propertyStore);
    [DllImport("ole32.dll", PreserveSig=true)] static extern int PropVariantClear(ref SetupPropVariant pvar);
    static SetupPropVariant StringVariant(string value){SetupPropVariant pv=new SetupPropVariant();pv.valueType=31;pv.pointerValue=Marshal.StringToCoTaskMemUni(value??String.Empty);return pv;}
    static void SetString(ISetupPropertyStore store,Guid fmt,uint pid,string value){SetupPropertyKey key=new SetupPropertyKey(fmt,pid);SetupPropVariant pv=StringVariant(value);try{int hr=store.SetValue(ref key,ref pv);if(hr<0)Marshal.ThrowExceptionForHR(hr);}finally{PropVariantClear(ref pv);}}
    public static void SetWindowAppIdentity(IntPtr hwnd,string appId,string relaunchCommand,string displayName,string iconResource){
        Guid iid=new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");ISetupPropertyStore store=null;
        int hr=SHGetPropertyStoreForWindow(hwnd,ref iid,out store);if(hr<0||store==null)Marshal.ThrowExceptionForHR(hr);
        Guid fmt=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        try{
            SetString(store,fmt,2,relaunchCommand);
            SetString(store,fmt,4,displayName);
            SetString(store,fmt,3,iconResource);
            SetString(store,fmt,5,appId);
            hr=store.Commit();if(hr<0)Marshal.ThrowExceptionForHR(hr);
        }
        finally{if(store!=null)Marshal.ReleaseComObject(store);}
    }
}
}
'@ -ErrorAction Stop
}
try{[void][AlphaSoftware.AutoRunner.SetupNativeUi]::SetCurrentProcessExplicitAppUserModelID('AlphaSoftware.SQLBackupAndFTPAutoRunner.Setup')}catch{}
try{[void][AlphaSoftware.AutoRunner.SetupNativeUi]::SetProcessDpiAwarenessContext([IntPtr](-4))}catch{try{[void][AlphaSoftware.AutoRunner.SetupNativeUi]::SetProcessDPIAware()}catch{}}
$form=New-Object Windows.Forms.Form
$form.Text='Instalação do SQLBackupAndFTP AutoRunner'
$form.Size=[Drawing.Size]::new(1020,680)
$form.MinimumSize=[Drawing.Size]::new(960,640)
$form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.MaximizeBox=$true
$form.BackColor=[Drawing.Color]::FromArgb(245,248,252)
$form.Opacity=1
$icon=Join-Path $PayloadRoot 'assets\AutoRunner.ico'
if(Test-Path -LiteralPath $icon){
    try{$form.Icon=[Drawing.Icon]::new($icon)}catch{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' ICON_ERROR '+$_.Exception.Message) -Encoding UTF8 -ErrorAction SilentlyContinue}
}
$form.ShowIcon=$true
$form.Add_Shown({
    try{
        $relaunch=$InstallerPath
        if([string]::IsNullOrWhiteSpace($relaunch) -or -not(Test-Path -LiteralPath $relaunch -PathType Leaf)){$relaunch=Join-Path $PayloadRoot 'SQLBackupAndFTP-AutoRunner.exe'}
        if(Test-Path -LiteralPath $relaunch -PathType Leaf){
            $setupRelaunch='"'+$relaunch+'"'
            [AlphaSoftware.AutoRunner.SetupNativeUi]::SetWindowAppIdentity($form.Handle,'AlphaSoftware.SQLBackupAndFTPAutoRunner.Setup',$setupRelaunch,'Instalação do SQLBackupAndFTP AutoRunner',($relaunch+',0'))
        }
    }catch{try{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' TASKBAR_ID_ERROR '+$_.Exception.Message) -Encoding UTF8}catch{}}
})

function Set-SetupWindowOnActiveScreen {
    param([Windows.Forms.Form]$Window,[int]$PreferredWidth=1020,[int]$PreferredHeight=680)
    try{
        $screen=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position)
        if($null -eq $screen){$screen=[Windows.Forms.Screen]::PrimaryScreen}
        $area=$screen.WorkingArea
        $availableWidth=[Math]::Max(540,$area.Width-32)
        $availableHeight=[Math]::Max(430,$area.Height-32)
        $width=[Math]::Min($PreferredWidth,$availableWidth)
        $height=[Math]::Min($PreferredHeight,$availableHeight)
        $Window.MinimumSize=[Drawing.Size]::new([Math]::Min(900,$availableWidth),[Math]::Min(600,$availableHeight))
        $Window.Size=[Drawing.Size]::new([int]$width,[int]$height)
        $Window.Location=[Drawing.Point]::new(
            [int]($area.Left+[Math]::Max(0,($area.Width-$width)/2)),
            [int]($area.Top+[Math]::Max(0,($area.Height-$height)/2))
        )
        $Window.WindowState=[Windows.Forms.FormWindowState]::Normal
        Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' WINDOW_PLACED screen='+$screen.DeviceName+' bounds='+$Window.Bounds.ToString()) -Encoding UTF8 -ErrorAction SilentlyContinue
    }catch{
        try{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' WINDOW_PLACEMENT_ERROR '+$_.Exception.ToString()) -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
    }
}

$setupNavy=[Drawing.Color]::FromArgb(18,39,62)
$setupBlue=[Drawing.Color]::FromArgb(30,112,213)
$setupBlueHover=[Drawing.Color]::FromArgb(20,92,188)
$setupText=[Drawing.Color]::FromArgb(31,42,55)
$setupMuted=[Drawing.Color]::FromArgb(101,113,128)
$setupBorder=[Drawing.Color]::FromArgb(216,224,233)
$setupCard=[Drawing.Color]::White

function Set-SetupButtonStyle($Button,[string]$Kind='Secondary'){
    $Button.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize=1
    $Button.Cursor=[Windows.Forms.Cursors]::Hand
    $Button.Font=New-Object Drawing.Font('Segoe UI Semibold',9.5)
    switch($Kind){
        'Primary'{$Button.BackColor=$setupBlue;$Button.ForeColor=[Drawing.Color]::White;$Button.FlatAppearance.BorderColor=$setupBlue;$Button.FlatAppearance.MouseOverBackColor=$setupBlueHover}
        'Danger'{$Button.BackColor=[Drawing.Color]::FromArgb(255,245,246);$Button.ForeColor=[Drawing.Color]::FromArgb(204,62,68);$Button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(240,190,194);$Button.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(255,232,234)}
        default{$Button.BackColor=[Drawing.Color]::White;$Button.ForeColor=$setupText;$Button.FlatAppearance.BorderColor=$setupBorder;$Button.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(238,244,252)}
    }
}

$root=New-Object Windows.Forms.TableLayoutPanel
$root.Dock='Fill';$root.ColumnCount=2;$root.RowCount=1;$root.Margin=0;$root.Padding=0
[void]$root.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,280)))
[void]$root.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$form.Controls.Add($root)

$side=New-Object Windows.Forms.Panel
$side.Dock='Fill';$side.BackColor=$setupNavy;$side.Padding=New-Object Windows.Forms.Padding(24,22,24,20);$side.AutoScroll=$true
[void]$root.Controls.Add($side,0,0)
$sideLayout=New-Object Windows.Forms.TableLayoutPanel
$sideLayout.Dock='Fill';$sideLayout.BackColor=$setupNavy;$sideLayout.Margin=0;$sideLayout.Padding=0;$sideLayout.ColumnCount=1;$sideLayout.RowCount=5
[void]$sideLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$sideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,82)))
[void]$sideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,1)))
[void]$sideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,42)))
[void]$sideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$sideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,94)))
$side.Controls.Add($sideLayout)

$brandPanel=New-Object Windows.Forms.TableLayoutPanel
$brandPanel.Dock='Fill';$brandPanel.Margin=0;$brandPanel.Padding=0;$brandPanel.ColumnCount=2;$brandPanel.RowCount=1
[void]$brandPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,58)))
[void]$brandPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$brandPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$logoPath=Join-Path $PayloadRoot 'assets\AutoRunner.png'
if(Test-Path -LiteralPath $logoPath){
    try{
        $setupLogo=New-Object Windows.Forms.PictureBox
        $setupLogo.Image=[Drawing.Image]::FromFile($logoPath);$setupLogo.SizeMode='Zoom';$setupLogo.Dock='Fill';$setupLogo.Margin=New-Object Windows.Forms.Padding(0,0,10,12)
        [void]$brandPanel.Controls.Add($setupLogo,0,0)
    }catch{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' LOGO_ERROR '+$_.Exception.Message) -Encoding UTF8 -ErrorAction SilentlyContinue}
}
$brandText=New-Object Windows.Forms.TableLayoutPanel
$brandText.Dock='Fill';$brandText.Margin=0;$brandText.Padding=0;$brandText.ColumnCount=1;$brandText.RowCount=2
[void]$brandText.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$brandText.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,62)))
[void]$brandText.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,38)))
$sideTitle=New-Object Windows.Forms.Label;$sideTitle.Text='AutoRunner';$sideTitle.Dock='Fill';$sideTitle.AutoEllipsis=$true;$sideTitle.ForeColor=[Drawing.Color]::White;$sideTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',17);$sideTitle.TextAlign='BottomLeft';$sideTitle.Margin=0
$sideVersion=New-Object Windows.Forms.Label;$sideVersion.Text=('Instalador '+(Get-AutoRunnerDisplayVersion));$sideVersion.Dock='Fill';$sideVersion.AutoEllipsis=$true;$sideVersion.ForeColor=[Drawing.Color]::FromArgb(156,176,196);$sideVersion.TextAlign='TopLeft';$sideVersion.Margin=0
[void]$brandText.Controls.Add($sideTitle,0,0);[void]$brandText.Controls.Add($sideVersion,0,1)
[void]$brandPanel.Controls.Add($brandText,1,0);[void]$sideLayout.Controls.Add($brandPanel,0,0)

$sideLine=New-Object Windows.Forms.Panel;$sideLine.Dock='Fill';$sideLine.Margin=0;$sideLine.BackColor=[Drawing.Color]::FromArgb(47,70,94);[void]$sideLayout.Controls.Add($sideLine,0,1)
$stepsTitle=New-Object Windows.Forms.Label;$stepsTitle.Text='ETAPAS';$stepsTitle.Dock='Fill';$stepsTitle.ForeColor=[Drawing.Color]::FromArgb(123,148,171);$stepsTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',8);$stepsTitle.TextAlign='MiddleLeft';$stepsTitle.Margin=New-Object Windows.Forms.Padding(0,8,0,0);[void]$sideLayout.Controls.Add($stepsTitle,0,2)

$stepsPanel=New-Object Windows.Forms.TableLayoutPanel
$stepsPanel.Dock='Top';$stepsPanel.AutoSize=$true;$stepsPanel.Margin=0;$stepsPanel.Padding=0;$stepsPanel.ColumnCount=1;$stepsPanel.RowCount=4
[void]$stepsPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
$stepNames=@('Validar o ambiente','Escolher a instalação','Criar os atalhos','Concluir e abrir')
for($stepIndex=0;$stepIndex -lt $stepNames.Count;$stepIndex++){
    [void]$stepsPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)))
    $stepRow=New-Object Windows.Forms.TableLayoutPanel;$stepRow.Dock='Fill';$stepRow.Margin=0;$stepRow.Padding=0;$stepRow.ColumnCount=2;$stepRow.RowCount=1
    [void]$stepRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,34)))
    [void]$stepRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$stepRow.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    $stepNumber=New-Object Windows.Forms.Label;$stepNumber.Text=('{0:00}' -f ($stepIndex+1));$stepNumber.Dock='Fill';$stepNumber.ForeColor=[Drawing.Color]::FromArgb(100,181,246);$stepNumber.Font=New-Object Drawing.Font('Segoe UI Semibold',9);$stepNumber.TextAlign='MiddleLeft';$stepNumber.Margin=0
    $stepLabel=New-Object Windows.Forms.Label;$stepLabel.Text=$stepNames[$stepIndex];$stepLabel.Dock='Fill';$stepLabel.AutoEllipsis=$true;$stepLabel.ForeColor=[Drawing.Color]::FromArgb(220,229,238);$stepLabel.Font=New-Object Drawing.Font('Segoe UI',10);$stepLabel.TextAlign='MiddleLeft';$stepLabel.Margin=0
    [void]$stepRow.Controls.Add($stepNumber,0,0);[void]$stepRow.Controls.Add($stepLabel,1,0);[void]$stepsPanel.Controls.Add($stepRow,0,$stepIndex)
}
[void]$sideLayout.Controls.Add($stepsPanel,0,3)
$sideNote=New-Object Windows.Forms.Label;$sideNote.Text='O AutoRunner fica separado do SQLBackupAndFTP e detecta automaticamente o caminho da CLI.';$sideNote.Dock='Fill';$sideNote.AutoEllipsis=$true;$sideNote.ForeColor=[Drawing.Color]::FromArgb(147,166,184);$sideNote.TextAlign='BottomLeft';$sideNote.Margin=New-Object Windows.Forms.Padding(0,8,0,0);[void]$sideLayout.Controls.Add($sideNote,0,4)

$right=New-Object Windows.Forms.Panel
$right.Dock='Fill';$right.BackColor=$form.BackColor;$right.Padding=New-Object Windows.Forms.Padding(24,16,24,18);$right.AutoScroll=$true
[void]$root.Controls.Add($right,1,0)

# O instalador da 2.3.5 RC não usa coordenadas absolutas no conteúdo principal.
# O painel interno é AutoSize + Dock=Top e o contêiner externo possui scroll,
# evitando controles sobrepostos/cortados em DPI 125/150/175/200% ou telas baixas.
$rightGrid=New-Object Windows.Forms.TableLayoutPanel
$rightGrid.Dock='Top';$rightGrid.AutoSize=$true;$rightGrid.AutoSizeMode='GrowAndShrink';$rightGrid.Margin=0;$rightGrid.Padding=0;$rightGrid.ColumnCount=1;$rightGrid.RowCount=7
[void]$rightGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
for($i=0;$i -lt 7;$i++){[void]$rightGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))}
$right.Controls.Add($rightGrid)

$header=New-Object Windows.Forms.TableLayoutPanel
$header.Dock='Top';$header.AutoSize=$true;$header.Margin=New-Object Windows.Forms.Padding(4,0,4,12);$header.Padding=0;$header.ColumnCount=1;$header.RowCount=2
[void]$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
[void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
$headerTitle=New-Object Windows.Forms.Label;$headerTitle.Text=if($installedApp.Installed){'Atualizar ou reparar'}else{'Instalar o AutoRunner'};$headerTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',22);$headerTitle.ForeColor=$setupText;$headerTitle.AutoSize=$true;$headerTitle.Margin=New-Object Windows.Forms.Padding(0,0,0,2)
$headerSub=New-Object Windows.Forms.Label;$headerSub.Text='Confirme o caminho, valide o SQLBackupAndFTP e escolha as opções.';$headerSub.ForeColor=$setupMuted;$headerSub.AutoSize=$true;$headerSub.Margin=0
[void]$header.Controls.Add($headerTitle,0,0);[void]$header.Controls.Add($headerSub,0,1);[void]$rightGrid.Controls.Add($header,0,0)

$statusCard=New-Object Windows.Forms.Panel;$statusCard.Dock='Top';$statusCard.Height=78;$statusCard.Margin=New-Object Windows.Forms.Padding(4,0,4,12);$statusCard.Padding=New-Object Windows.Forms.Padding(14,9,14,9);$statusCard.BackColor=$setupCard;$statusCard.BorderStyle='FixedSingle'
$statusLayout=New-Object Windows.Forms.TableLayoutPanel;$statusLayout.Dock='Fill';$statusLayout.Margin=0;$statusLayout.Padding=0;$statusLayout.ColumnCount=2;$statusLayout.RowCount=1
[void]$statusLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,30)));[void]$statusLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
$statusDot=New-Object Windows.Forms.Label;$statusDot.Text='●';$statusDot.ForeColor=[Drawing.Color]::FromArgb(220,145,20);$statusDot.Font=New-Object Drawing.Font('Segoe UI',13);$statusDot.Dock='Fill';$statusDot.TextAlign='MiddleLeft';$statusDot.Margin=0
$lblStatus=New-Object Windows.Forms.Label;$lblStatus.Dock='Fill';$lblStatus.ForeColor=$setupText;$lblStatus.Text='Aguardando a detecção inicial do SQLBackupAndFTP...';$lblStatus.TextAlign='MiddleLeft';$lblStatus.AutoEllipsis=$true;$lblStatus.Margin=0
[void]$statusLayout.Controls.Add($statusDot,0,0);[void]$statusLayout.Controls.Add($lblStatus,1,0);$statusCard.Controls.Add($statusLayout);[void]$rightGrid.Controls.Add($statusCard,0,1)

$appCard=New-Object Windows.Forms.Panel;$appCard.Dock='Top';$appCard.Height=98;$appCard.Margin=New-Object Windows.Forms.Padding(4,0,4,12);$appCard.Padding=New-Object Windows.Forms.Padding(14,9,14,10);$appCard.BackColor=$setupCard;$appCard.BorderStyle='FixedSingle'
$appLayout=New-Object Windows.Forms.TableLayoutPanel;$appLayout.Dock='Fill';$appLayout.Margin=0;$appLayout.Padding=0;$appLayout.ColumnCount=1;$appLayout.RowCount=2
[void]$appLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));[void]$appLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,28)));[void]$appLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$lblPath=New-Object Windows.Forms.Label;$lblPath.Text='Pasta de instalação do AutoRunner';$lblPath.Dock='Fill';$lblPath.ForeColor=$setupMuted;$lblPath.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$lblPath.TextAlign='MiddleLeft';$lblPath.Margin=0
$appPathRow=New-Object Windows.Forms.TableLayoutPanel;$appPathRow.Dock='Fill';$appPathRow.Margin=0;$appPathRow.Padding=0;$appPathRow.ColumnCount=2;$appPathRow.RowCount=1
[void]$appPathRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));[void]$appPathRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,64)))
$txtPath=New-Object Windows.Forms.TextBox;$txtPath.Dock='Fill';$txtPath.Margin=New-Object Windows.Forms.Padding(0,5,8,4);$txtPath.Text=if($installedApp.Installed){$installedApp.InstallDir}else{$InstallDir};$txtPath.BorderStyle='FixedSingle'
$browseApp=New-Object Windows.Forms.Button;$browseApp.Text='...';$browseApp.Dock='Fill';$browseApp.Margin=New-Object Windows.Forms.Padding(0,3,0,3);Set-SetupButtonStyle $browseApp
if($installedApp.Installed){$txtPath.ReadOnly=$true;$browseApp.Enabled=$false}
[void]$appPathRow.Controls.Add($txtPath,0,0);[void]$appPathRow.Controls.Add($browseApp,1,0);[void]$appLayout.Controls.Add($lblPath,0,0);[void]$appLayout.Controls.Add($appPathRow,0,1);$appCard.Controls.Add($appLayout);[void]$rightGrid.Controls.Add($appCard,0,2)

$sqlCard=New-Object Windows.Forms.Panel;$sqlCard.Dock='Top';$sqlCard.Height=116;$sqlCard.Margin=New-Object Windows.Forms.Padding(4,0,4,12);$sqlCard.Padding=New-Object Windows.Forms.Padding(14,8,14,9);$sqlCard.BackColor=$setupCard;$sqlCard.BorderStyle='FixedSingle'
$sqlLayout=New-Object Windows.Forms.TableLayoutPanel;$sqlLayout.Dock='Fill';$sqlLayout.Margin=0;$sqlLayout.Padding=0;$sqlLayout.ColumnCount=1;$sqlLayout.RowCount=3
[void]$sqlLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));[void]$sqlLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,26)));[void]$sqlLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,42)));[void]$sqlLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$lblSql=New-Object Windows.Forms.Label;$lblSql.Text='Instalação do SQLBackupAndFTP';$lblSql.Dock='Fill';$lblSql.ForeColor=$setupMuted;$lblSql.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$lblSql.TextAlign='MiddleLeft';$lblSql.Margin=0
$sqlRow=New-Object Windows.Forms.TableLayoutPanel;$sqlRow.Dock='Fill';$sqlRow.Margin=0;$sqlRow.Padding=0;$sqlRow.ColumnCount=4;$sqlRow.RowCount=1
[void]$sqlRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));[void]$sqlRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,92)));[void]$sqlRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,100)));[void]$sqlRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,98)))
$txtSql=New-Object Windows.Forms.TextBox;$txtSql.Dock='Fill';$txtSql.Margin=New-Object Windows.Forms.Padding(0,4,8,4);$txtSql.ReadOnly=$true;$txtSql.BorderStyle='FixedSingle'
$locateSql=New-Object Windows.Forms.Button;$locateSql.Text='Detectar';$locateSql.Dock='Fill';$locateSql.Margin=New-Object Windows.Forms.Padding(0,2,6,2);Set-SetupButtonStyle $locateSql 'Primary'
$browseSql=New-Object Windows.Forms.Button;$browseSql.Text='Selecionar';$browseSql.Dock='Fill';$browseSql.Margin=New-Object Windows.Forms.Padding(0,2,6,2);Set-SetupButtonStyle $browseSql
$downloadSql=New-Object Windows.Forms.Button;$downloadSql.Text='Baixar';$downloadSql.Dock='Fill';$downloadSql.Margin=New-Object Windows.Forms.Padding(0,2,0,2);Set-SetupButtonStyle $downloadSql
[void]$sqlRow.Controls.Add($txtSql,0,0);[void]$sqlRow.Controls.Add($locateSql,1,0);[void]$sqlRow.Controls.Add($browseSql,2,0);[void]$sqlRow.Controls.Add($downloadSql,3,0)
$sqlHint=New-Object Windows.Forms.Label;$sqlHint.Text='Detecção automática por caminho salvo, Registro, serviço, processos, App Paths, atalhos e busca limitada da CLI.';$sqlHint.ForeColor=$setupMuted;$sqlHint.Dock='Fill';$sqlHint.AutoEllipsis=$true;$sqlHint.TextAlign='MiddleLeft';$sqlHint.Margin=0
[void]$sqlLayout.Controls.Add($lblSql,0,0);[void]$sqlLayout.Controls.Add($sqlRow,0,1);[void]$sqlLayout.Controls.Add($sqlHint,0,2);$sqlCard.Controls.Add($sqlLayout);[void]$rightGrid.Controls.Add($sqlCard,0,3)

$optionsCard=New-Object Windows.Forms.Panel;$optionsCard.Dock='Top';$optionsCard.Height=126;$optionsCard.Margin=New-Object Windows.Forms.Padding(4,0,4,12);$optionsCard.Padding=New-Object Windows.Forms.Padding(14,8,14,9);$optionsCard.BackColor=$setupCard;$optionsCard.BorderStyle='FixedSingle'
$optionsLayout=New-Object Windows.Forms.TableLayoutPanel;$optionsLayout.Dock='Fill';$optionsLayout.Margin=0;$optionsLayout.Padding=0;$optionsLayout.ColumnCount=2;$optionsLayout.RowCount=3
[void]$optionsLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)));[void]$optionsLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))
[void]$optionsLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,28)));[void]$optionsLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,50)));[void]$optionsLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,50)))
$optionsTitle=New-Object Windows.Forms.Label;$optionsTitle.Text='Opções';$optionsTitle.Dock='Fill';$optionsTitle.ForeColor=$setupMuted;$optionsTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$optionsTitle.TextAlign='MiddleLeft';$optionsTitle.Margin=0
[void]$optionsLayout.Controls.Add($optionsTitle,0,0);$optionsLayout.SetColumnSpan($optionsTitle,2)
$desktop=New-Object Windows.Forms.CheckBox;$desktop.Text='Criar atalho na Área de Trabalho';$desktop.Dock='Fill';$desktop.AutoEllipsis=$true;$desktop.Margin=New-Object Windows.Forms.Padding(0,0,8,0);$desktop.Checked=if($installedApp.Installed){try{[bool](Get-ItemPropertyValue -LiteralPath $machineKey -Name DesktopShortcut -ErrorAction Stop)}catch{$false}}else{$true}
$launch=New-Object Windows.Forms.CheckBox;$launch.Text='Executar ao concluir';$launch.Dock='Fill';$launch.AutoEllipsis=$true;$launch.Margin=0;$launch.Checked=$true
$userSettings=Get-AutoRunnerUserSettings
$tutorial=New-Object Windows.Forms.CheckBox;$tutorial.Text='Mostrar tutorial na primeira abertura';$tutorial.Dock='Fill';$tutorial.AutoEllipsis=$true;$tutorial.Margin=New-Object Windows.Forms.Padding(0,0,8,0);$tutorial.Checked=(-not [bool]$userSettings.TutorialDoNotShowAgain)
$keep=New-Object Windows.Forms.CheckBox;$keep.Text='Exportar diagnóstico ao desinstalar';$keep.Dock='Fill';$keep.AutoEllipsis=$true;$keep.Margin=0;$keep.Checked=$true
[void]$optionsLayout.Controls.Add($desktop,0,1);[void]$optionsLayout.Controls.Add($launch,1,1);[void]$optionsLayout.Controls.Add($tutorial,0,2);[void]$optionsLayout.Controls.Add($keep,1,2);$optionsCard.Controls.Add($optionsLayout);[void]$rightGrid.Controls.Add($optionsCard,0,4)

$progress=New-Object Windows.Forms.ProgressBar;$progress.Dock='Top';$progress.Height=6;$progress.Margin=New-Object Windows.Forms.Padding(4,0,4,8);$progress.Style='Marquee';$progress.MarqueeAnimationSpeed=24;$progress.Visible=$false
[void]$rightGrid.Controls.Add($progress,0,5)
$buttonPanel=New-Object Windows.Forms.FlowLayoutPanel;$buttonPanel.FlowDirection='RightToLeft';$buttonPanel.WrapContents=$false;$buttonPanel.Dock='Top';$buttonPanel.Height=52;$buttonPanel.Margin=New-Object Windows.Forms.Padding(4,0,4,0);$buttonPanel.Padding=0
$installBtn=New-Object Windows.Forms.Button;$installBtn.Text=if($installedApp.Installed){'Atualizar / reparar'}else{'Instalar agora'};$installBtn.Size=[Drawing.Size]::new(168,44);$installBtn.Margin=New-Object Windows.Forms.Padding(6,2,0,2);Set-SetupButtonStyle $installBtn 'Primary'
$uninstallBtn=New-Object Windows.Forms.Button;$uninstallBtn.Text='Desinstalar';$uninstallBtn.Size=[Drawing.Size]::new(118,44);$uninstallBtn.Margin=New-Object Windows.Forms.Padding(6,2,0,2);$uninstallBtn.Enabled=$installedApp.Installed;Set-SetupButtonStyle $uninstallBtn 'Danger'
$cancelBtn=New-Object Windows.Forms.Button;$cancelBtn.Text='Cancelar';$cancelBtn.Size=[Drawing.Size]::new(100,44);$cancelBtn.Margin=New-Object Windows.Forms.Padding(6,2,0,2);Set-SetupButtonStyle $cancelBtn;$cancelBtn.Add_Click({$form.Close()})
$buttonPanel.Controls.AddRange(@($installBtn,$uninstallBtn,$cancelBtn));[void]$rightGrid.Controls.Add($buttonPanel,0,6)

$script:SetupSqlBackupCandidate=$null
function Set-InstallerSqlBackupCandidate($Candidate){
    $script:SetupSqlBackupCandidate=$Candidate
    if($Candidate){
        Set-AutoRunnerUserSettings -PreferredSqlBackupPath $Candidate.InstallDir -PreferredSqlBackupCliPath $Candidate.CliPath -PreferredSqlBackupAppPath $Candidate.AppPath -DetectionSource (@($Candidate.DetectionSources)-join '; ')
        $txtSql.Text="$($Candidate.InstallDir) | CLI $($Candidate.CliVersion)"
        $statusDot.ForeColor=[Drawing.Color]::FromArgb(22,153,99)
        $lblStatus.Text='SQLBackupAndFTP localizado e validado. O AutoRunner será instalado separadamente e utilizará este caminho automaticamente.'
    }else{
        $txtSql.Text='Não localizado'
        $statusDot.ForeColor=[Drawing.Color]::FromArgb(220,145,20)
        $lblStatus.Text='SQLBackupAndFTP não localizado. Use Detectar, Selecionar ou Baixar para obter a versão oficial.'
    }
}
function Refresh-InstallerDetection([bool]$Deep){
    try{$candidate=Get-SqlBackupAndFTPInstall -DeepSearch:$Deep -Quick:(-not $Deep) -AllowNotFound;Set-InstallerSqlBackupCandidate $candidate}
    catch{$script:SetupSqlBackupCandidate=$null;$txtSql.Text='Falha na detecção';$statusDot.ForeColor=[Drawing.Color]::FromArgb(204,62,68);$lblStatus.Text=$_.Exception.Message}
}
function Select-InstallerSqlBackupFolder{
    $folder=New-Object Windows.Forms.FolderBrowserDialog
    $folder.Description='Selecione a pasta do SQLBackupAndFTP que contém SqlBak.Job.Cli.exe.'
    $folder.ShowNewFolderButton=$false
    $settings=Get-AutoRunnerUserSettings
    if($settings.PreferredSqlBackupPath -and (Test-Path -LiteralPath $settings.PreferredSqlBackupPath -PathType Container)){$folder.SelectedPath=$settings.PreferredSqlBackupPath}
    if($folder.ShowDialog($form) -ne 'OK'){return}
    $validated=Test-SqlBackupAndFTPDirectory -Path $folder.SelectedPath
    if(-not $validated){[Windows.Forms.MessageBox]::Show('A pasta selecionada não contém SqlBak.Job.Cli.exe.','Pasta incompatível','OK','Error')|Out-Null;return}
    $candidate=Get-SqlBackupAndFTPInstall -PreferredPath $folder.SelectedPath
    Set-InstallerSqlBackupCandidate $candidate
}
$browseApp.Add_Click({$folder=New-Object Windows.Forms.FolderBrowserDialog;$folder.Description='Selecione a pasta pai. O instalador criará Alpha Software\SQLBackupAndFTP AutoRunner.';$folder.SelectedPath=Split-Path -Parent (Split-Path -Parent $txtPath.Text);if($folder.ShowDialog($form)-eq 'OK'){$txtPath.Text=Join-Path $folder.SelectedPath 'Alpha Software\SQLBackupAndFTP AutoRunner'}})
$locateSql.Add_Click({try{$form.UseWaitCursor=$true;Refresh-InstallerDetection $true}finally{$form.UseWaitCursor=$false};if(-not $script:SetupSqlBackupCandidate){[Windows.Forms.MessageBox]::Show('A detecção automática não encontrou uma instalação válida. Você pode selecionar manualmente ou usar Baixar para obter o SQLBackupAndFTP.','SQLBackupAndFTP','OK','Information')|Out-Null;Select-InstallerSqlBackupFolder}})
$browseSql.Add_Click({Select-InstallerSqlBackupFolder})
$downloadSql.Add_Click({
    $url=Get-SqlBackupAndFTPDownloadUrl
    if([Windows.Forms.MessageBox]::Show("Deseja abrir o download oficial da versão mais recente do SQLBackupAndFTP?`r`n`r`n$url",'Baixar SQLBackupAndFTP','YesNo','Information') -eq 'Yes'){
        try{Start-Process $url}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha ao abrir o download','OK','Error')|Out-Null}
    }
})
$installBtn.Add_Click({
    $script:SetupOperationAttempted=$true
    try{
        if(-not $script:SetupSqlBackupCandidate){
            $continue=[Windows.Forms.MessageBox]::Show('O SQLBackupAndFTP ainda não foi localizado. O aplicativo pode ser instalado, mas a automação só poderá ser configurada depois da localização. Continuar?','SQLBackupAndFTP não localizado','YesNo','Warning')
            if($continue -ne 'Yes'){return}
        }
        $form.Enabled=$false;$progress.Visible=$true;$statusDot.ForeColor=$setupBlue;$lblStatus.Text='Instalando e protegendo os arquivos. Aguarde...';$selected=if($installedApp.Installed){'Repair'}else{'Install'};$script:SetupPostInstallWarning='';Invoke-SelectedMode $selected $txtPath.Text $desktop.Checked $launch.Checked (-not $tutorial.Checked) $keep.Checked;$script:SetupOperationSucceeded=$true;$progress.Visible=$false;if($script:SetupPostInstallWarning){$statusDot.ForeColor=[Drawing.Color]::FromArgb(220,145,20);$lblStatus.Text='Instalação concluída, mas a abertura precisa de atenção.';[Windows.Forms.MessageBox]::Show($script:SetupPostInstallWarning,'AutoRunner instalado com aviso','OK','Warning')|Out-Null}else{$statusDot.ForeColor=[Drawing.Color]::FromArgb(22,153,99);$lblStatus.Text='Instalação concluída com sucesso.';[Windows.Forms.MessageBox]::Show('Instalação concluída e a interface foi iniciada com sucesso.','AutoRunner','OK','Information')|Out-Null};$form.Close()
    }
    catch{$form.Enabled=$true;$progress.Visible=$false;$statusDot.ForeColor=[Drawing.Color]::FromArgb(204,62,68);$lblStatus.Text='A instalação falhou. Consulte a mensagem e o log para detalhes.';[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha na instalação','OK','Error')|Out-Null}
})
$uninstallBtn.Add_Click({
    if([Windows.Forms.MessageBox]::Show('Remover o AutoRunner? Os jobs do SQLBackupAndFTP não serão apagados.','Desinstalar','YesNo','Warning') -ne 'Yes'){return}
    $script:SetupOperationAttempted=$true
    try{$form.Enabled=$false;$progress.Visible=$true;Invoke-SelectedMode 'Uninstall' $txtPath.Text $false $false $true $keep.Checked;$script:SetupOperationSucceeded=$true;$progress.Visible=$false;[Windows.Forms.MessageBox]::Show('AutoRunner removido.','AutoRunner','OK','Information')|Out-Null;$form.Close()}
    catch{$form.Enabled=$true;$progress.Visible=$false;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Falha na desinstalação','OK','Error')|Out-Null}
})
$startupForegroundTimer=New-Object Windows.Forms.Timer
$startupForegroundTimer.Interval=900
$startupForegroundTimer.Add_Tick({
    $startupForegroundTimer.Stop()
    try{
        if(-not $form.IsDisposed){
            $form.TopMost=$false
            $form.Activate()
            $form.BringToFront()
        }
    }catch{
        try{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' FOREGROUND_ERROR '+$_.Exception.ToString()) -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
    }
})
$initialDetectionTimer=New-Object Windows.Forms.Timer
$initialDetectionTimer.Interval=700
$initialDetectionTimer.Add_Tick({
    $initialDetectionTimer.Stop()
    try{
        Refresh-InstallerDetection $false
        Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' UI_READY') -Encoding UTF8 -ErrorAction SilentlyContinue
    }catch{
        $txtSql.Text='Falha na detecção inicial'
        $lblStatus.Text='A instalação continua disponível. Use Detectar ou Selecionar para localizar o SQLBackupAndFTP.'
        try{Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' DETECTION_ERROR '+$_.Exception.ToString()) -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
    }
})
$form.Add_Load({
    Set-SetupWindowOnActiveScreen -Window $form
})
$form.Add_Shown({
    Set-SetupWindowOnActiveScreen -Window $form
    $form.ShowInTaskbar=$true
    $form.WindowState=[Windows.Forms.FormWindowState]::Normal
    $form.TopMost=$true
    $form.Activate()
    $form.BringToFront()
    [Windows.Forms.Application]::DoEvents()
    Add-Content -LiteralPath $setupLogPath -Value ((Get-Date).ToString('s')+' WINDOW_SHOWN') -Encoding UTF8 -ErrorAction SilentlyContinue
    $startupForegroundTimer.Start()
    $initialDetectionTimer.Start()
})
$form.Add_FormClosed({
    try{$startupForegroundTimer.Stop();$startupForegroundTimer.Dispose()}catch{}
    try{$initialDetectionTimer.Stop();$initialDetectionTimer.Dispose()}catch{}
})
[Windows.Forms.Application]::Run($form)
$form.Dispose()
Start-DeferredInstallerCleanup
if($script:SetupOperationSucceeded){exit 0}
if($script:SetupOperationAttempted){exit 1}
exit 1602
