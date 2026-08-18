#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu','Repair','Validate','Test','Diagnostics','Uninstall','GuiSmoke','TutorialSmoke','Help','Locate')][string]$Action = 'Menu',
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$TaskName = 'SQLBackupAndFTP AutoRunner',
    [string]$TaskPath = '\SQLBackupAndFTPAuto\',
    [switch]$Console
)

# Registre falhas que aconteçam antes da interface e antes do módulo principal.
# Nas versões anteriores, um erro neste trecho deixava apenas powershell.exe em
# segundo plano, sem janela e sem informação para suporte.
$earlyLogDirectory = Join-Path $env:TEMP 'SQLBackupAndFTPAuto'
$earlyLogPath = Join-Path $earlyLogDirectory 'manager-startup.log'
try {
    New-Item -ItemType Directory -Path $earlyLogDirectory -Force -ErrorAction SilentlyContinue | Out-Null
    Add-Content -LiteralPath $earlyLogPath -Value ((Get-Date).ToString('s') + ' START Manager.ps1 PID=' + $PID) -Encoding UTF8 -ErrorAction SilentlyContinue
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    $rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $modulePath = Join-Path $rootDir 'modules\AutoRunner.Core.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) { $modulePath = Join-Path $SupportDir 'modules\AutoRunner.Core.psm1' }
    Import-Module $modulePath -Force -DisableNameChecking
}
catch {
    $detail = $_.Exception.ToString()
    try { Add-Content -LiteralPath $earlyLogPath -Value ((Get-Date).ToString('s') + ' FATAL ' + $detail) -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show(('O AutoRunner falhou antes de abrir a interface.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message+[Environment]::NewLine+[Environment]::NewLine+'Log: '+$earlyLogPath),'SQLBackupAndFTP AutoRunner','OK','Error') | Out-Null
    } catch {}
    exit 1
}

# Uma única interface por usuário. O mutex é liberado automaticamente pelo Windows
# mesmo após encerramento abrupto, evitando janelas duplicadas e ações concorrentes.
$script:ManagerMutex=$null
if(-not $Console -and $Action -in @('Menu','Help','Locate')){
    $sid='unknown'
    try{$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}catch{}
    $mutexName='Local\AlphaSoftware.SQLBackupAndFTPAutoRunner.Manager.'+($sid -replace '[^A-Za-z0-9_.-]','_')
    $created=$false
    $script:ManagerMutex=New-Object Threading.Mutex($false,$mutexName,[ref]$created)
    $taken=$false
    try{$taken=$script:ManagerMutex.WaitOne(0,$false)}catch [Threading.AbandonedMutexException]{$taken=$true}
    if(-not $taken){
        try{Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show('O SQLBackupAndFTP AutoRunner já está aberto.','SQLBackupAndFTP AutoRunner','OK','Information')|Out-Null}catch{}
        exit 0
    }
}

function Start-ElevatedManager {
    $ps = Get-AutoRunnerWindowsPowerShellPath
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Action',$Action,'-SupportDir',$SupportDir,'-TaskName',$TaskName,'-TaskPath',$TaskPath)
    if ($Console) { $args += '-Console' }
    $line = Join-AutoRunnerProcessArguments -Arguments $args
    $p = Start-Process -FilePath $ps -ArgumentList $line -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}


# Antes da instalação, não grave logs dentro do pacote de origem. O diretório TEMP
# evita modificar o pacote validado e continua gravável antes da criação do SupportDir.
$managerLog = Join-Path $SupportDir 'logs\manager.log'
if (-not (Test-Path -LiteralPath (Join-Path $SupportDir 'config.json') -PathType Leaf)) {
    $managerTempLogDir = Join-Path $env:TEMP 'SQLBackupAndFTPAuto'
    New-Item -ItemType Directory -Path $managerTempLogDir -Force -ErrorAction SilentlyContinue | Out-Null
    $managerLog = Join-Path $managerTempLogDir 'manager.log'
}
function Write-ManagerLog {
    param([string]$Message,[string]$Level='INFO')
    try { Write-AutoRunnerLog -Path $managerLog -Message $Message -Level $Level -Component 'Manager' -NoConsole }
    catch {}
}

function Get-ChildScriptPath {
    param([string]$Name)
    $path = Join-Path $rootDir ('scripts\' + $Name)
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $SupportDir ('scripts\' + $Name) }
    return $path
}

function Start-ChildPowerShell {
    param([string]$ScriptPath,[string[]]$Arguments,[switch]$Visible,[switch]$Elevated)
    $ps = Get-AutoRunnerWindowsPowerShellPath
    $all = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath) + $Arguments
    $line = Join-AutoRunnerProcessArguments -Arguments $all
    Write-ManagerLog ("Executando processo filho. Script: $ScriptPath; elevado: $Elevated")
    $params = @{ FilePath=$ps; ArgumentList=$line; Wait=$true; PassThru=$true }
    if ($Elevated -and -not (Test-AutoRunnerAdministrator)) { $params.Verb = 'RunAs' }
    if (-not $Visible) { $params.WindowStyle = 'Hidden' }
    $process = Start-Process @params
    try{$process.WaitForExit()}catch{}
    try{$process.Refresh()}catch{}
    $code=$null
    try{$code=[int]$process.ExitCode}catch{}
    if($null -eq $code){$code=1}
    Write-ManagerLog ("Processo finalizado com código $code")
    return $code
}

function New-InstallRequest {
    param($Jobs,$Execution,$Logging)
    return [pscustomobject][ordered]@{
        Product='SQLBackupAndFTP AutoRunner'
        RequestedAtUtc=[DateTime]::UtcNow.ToString('o')
        Jobs=@($Jobs)
        Execution=$Execution
        Logging=$Logging
    }
}

function Invoke-InstallerRequest {
    param([ValidateSet('Install','Reconfigure')][string]$Mode,$Request)
    $temp = Join-Path $env:TEMP ('SQLBackupAndFTPAuto-Request-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-AutoRunnerJsonAtomic -InputObject $Request -Path $temp -Depth 30
        $requestSha=Get-AutoRunnerFileHash -Path $temp
        if([string]::IsNullOrWhiteSpace($requestSha)){throw 'Não foi possível calcular o SHA-256 da solicitação de instalação.'}
        $installer = Get-ChildScriptPath 'Install-SQLBackupAndFTP-Auto.ps1'
        return Start-ChildPowerShell -ScriptPath $installer -Arguments @('-Mode',$Mode,'-RequestFile',$temp,'-RequestSha256',$requestSha,'-SupportDir',$SupportDir,'-TaskName',$TaskName,'-TaskPath',$TaskPath,'-Quiet') -Elevated
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Invoke-RepairCore {
    $installer = Get-ChildScriptPath 'Install-SQLBackupAndFTP-Auto.ps1'
    return Start-ChildPowerShell -ScriptPath $installer -Arguments @('-Mode','Repair','-SupportDir',$SupportDir,'-TaskName',$TaskName,'-TaskPath',$TaskPath,'-Quiet') -Elevated
}

function Invoke-ValidateCore {
    [CmdletBinding()]
    param([switch]$WriteConsole)
    $validation = Test-AutoRunnerInstallation -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
    if ($WriteConsole) {
        foreach ($check in @($validation.Checks)) {
            $label = if ($check.Ok) { '[OK]' } else { '[FALHA]' }
            $color = if ($check.Ok) { 'Green' } else { 'Red' }
            Write-Host ("{0} {1}: {2}" -f $label,$check.Name,$check.Detail) -ForegroundColor $color
        }
    }
    return [pscustomobject]@{ ExitCode=$(if($validation.IsValid){0}else{2}); Validation=$validation }
}

function Invoke-TestNow {
    $runner = Join-Path $SupportDir 'scripts\Run-SQLBackupAndFTPJob.ps1'
    if (-not (Test-Path -LiteralPath $runner)) { throw 'Runner não instalado.' }
    return Start-ChildPowerShell -ScriptPath $runner -Arguments @('-Trigger','Manual','-Force','-SupportDir',$SupportDir)
}

function Invoke-UninstallCore {
    param([switch]$Keep)
    $uninstaller = Get-ChildScriptPath 'Uninstall-SQLBackupAndFTP-Auto.ps1'
    $args = @('-SupportDir',$SupportDir,'-TaskName',$TaskName,'-TaskPath',$TaskPath,'-Quiet')
    if ($Keep) { $args += '-KeepDiagnostics' }
    $code=Start-ChildPowerShell -ScriptPath $uninstaller -Arguments $args -Elevated
    # Algumas combinações PowerShell 5.1 + ShellExecute/RunAs retornam -1 mesmo
    # depois do processo elevado encerrar. Nesse caso valide o estado real em vez
    # de transformar uma remoção bem-sucedida em falso erro visual.
    if($code -eq -1){
        Start-Sleep -Milliseconds 350
        $remaining=Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
        if(-not $remaining.HasConfiguration -and -not $remaining.HasTask){
            Write-ManagerLog 'Processo de remoção retornou -1, porém a verificação pós-condição confirmou remoção completa.' 'WARN'
            return 0
        }
        Write-ManagerLog 'Processo de remoção retornou -1 e ainda existem configuração ou tarefa.' 'ERROR'
        return 1
    }
    return $code
}

function Get-RemoteAgentScriptPath {
    $appDir=Get-AutoRunnerApplicationInstallDir
    if([string]::IsNullOrWhiteSpace([string]$appDir)){return $null}
    $scriptPath=Join-Path $appDir 'agent\remote-control\AutoRunner.RemoteAgent.ps1'
    if(Test-Path -LiteralPath $scriptPath -PathType Leaf){return $scriptPath}
    return $null
}

function Get-RemoteAgentStatus {
    $cfgPath=Join-Path $SupportDir 'remote-agent\agent.json'
    $cfg=$null
    try{if(Test-Path -LiteralPath $cfgPath -PathType Leaf){$cfg=Read-AutoRunnerJson -Path $cfgPath}}catch{Write-ManagerLog ('Configuração do Remote Agent inválida: '+$_.Exception.Message) 'WARN'}
    $task=$null
    try{$task=Get-ScheduledTask -TaskName 'SQLBackupAndFTP AutoRunner Remote Agent' -TaskPath '\Alpha Software\' -ErrorAction Stop}catch{}
    return [pscustomobject]@{
        IsEnrolled=($null -ne $cfg -and -not [string]::IsNullOrWhiteSpace([string]$cfg.agentId))
        HasTask=($null -ne $task)
        AgentId=if($cfg){[string]$cfg.agentId}else{''}
        MachineId=if($cfg){[string]$cfg.machineId}else{''}
        BaseUrl=if($cfg){[string]$cfg.baseUrl}else{''}
        WsUrl=if($cfg){[string]$cfg.wsUrl}else{''}
        AllowInsecureTransport=if($cfg){[bool]$cfg.allowInsecureTransport}else{$false}
        TaskState=if($task){[string]$task.State}else{'Ausente'}
    }
}

function Invoke-RemoteAgentEnrollmentCore {
    param([Parameter(Mandatory=$true)][string]$BaseUrl,[Parameter(Mandatory=$true)][string]$Token,[switch]$AllowInsecureTransport)
    $agentScript=Get-RemoteAgentScriptPath
    if(-not $agentScript){throw 'Instale o AutoRunner antes de conectar esta máquina ao Control Plane.'}
    $requestPath=Join-Path $env:TEMP ('SQLBackupAndFTPAuto-AgentEnroll-'+[Guid]::NewGuid().ToString('N')+'.json')
    try{
        $request=[ordered]@{BaseUrl=$BaseUrl.Trim();Token=$Token.Trim();AllowInsecureTransport=[bool]$AllowInsecureTransport;RequestedAtUtc=[DateTime]::UtcNow.ToString('o')}
        Write-AutoRunnerJsonAtomic -InputObject $request -Path $requestPath -Depth 8
        $hash=Get-AutoRunnerFileHash -Path $requestPath
        if([string]::IsNullOrWhiteSpace($hash)){throw 'Não foi possível calcular o SHA-256 da matrícula.'}
        return Start-ChildPowerShell -ScriptPath $agentScript -Arguments @('-EnrollmentRequestPath',$requestPath,'-EnrollmentRequestSha256',$hash) -Elevated
    } finally { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }
}

function Invoke-RemoteAgentDisconnectCore {
    $agentScript=Get-RemoteAgentScriptPath
    if(-not $agentScript){throw 'Remote Agent não está disponível na instalação atual.'}
    return Start-ChildPowerShell -ScriptPath $agentScript -Arguments @('-UninstallTask') -Elevated
}

function Get-CurrentStatus {
    $state = Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
    $install = $null
    try { $install = Get-SqlBackupAndFTPInstall -AllowNotFound -Quick } catch { Write-ManagerLog $_.Exception.Message 'WARN' }
    if ($state.Config) {
        try {
            $migrationInstall = $install
            if (-not $migrationInstall) {
                $oldSql = Get-AutoRunnerPropertyValue -InputObject $state.Config -Name 'SqlBackupAndFTP'
                $migrationInstall = [pscustomobject]@{
                    InstallDir=[string](Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'InstallDir' -Default '')
                    CliPath=[string](Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'CliPath' -Default '')
                    CliVersion=Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'CliVersion'
                    AppPath=Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'AppPath'
                    AppVersion=Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'AppVersion'
                    ServiceName=Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'ServiceName'
                    ServiceDisplayName=Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'ServiceDisplayName'
                }
            }
            $state.Config = ConvertTo-AutoRunnerCurrentConfig -Config $state.Config -InstallInfo $migrationInstall
        }
        catch { $state.Errors += ('Normalização para exibição: ' + $_.Exception.Message) }
    }
    return [pscustomobject]@{ Installed=$state; SqlBak=$install }
}

function Read-ConsoleInteger {
    param([string]$Prompt,[int]$Default,[int]$Minimum,[int]$Maximum)
    while ($true) {
        $raw = Read-Host ("$Prompt [$Default]")
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $value = 0
        if ([int]::TryParse($raw, [ref]$value) -and $value -ge $Minimum -and $value -le $Maximum) { return $value }
        Write-Host "Informe um número entre $Minimum e $Maximum." -ForegroundColor Yellow
    }
}

function Read-ConsoleYesNo {
    param([string]$Prompt,[bool]$Default)
    $defaultText = if ($Default) { 'S' } else { 'N' }
    while ($true) {
        $raw = (Read-Host ("$Prompt [S/N; padrão $defaultText]")).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        if ($raw -match '(?i)^s(im)?$') { return $true }
        if ($raw -match '(?i)^n(ao|ão)?$') { return $false }
        Write-Host 'Responda S ou N.' -ForegroundColor Yellow
    }
}

function Invoke-ConsoleConfiguration {
    $install = Get-SqlBackupAndFTPInstall -AllowNotFound
    if (-not $install) { throw 'Localize o SQLBackupAndFTP antes de configurar a automação.' }
    $discovery = Get-SqlBakJobs -InstallInfo $install
    $installed = Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
    $existing = $installed.Config
    if ($existing) { $existing = ConvertTo-AutoRunnerCurrentConfig -Config $existing -InstallInfo $install }
    Write-Host ''
    Write-Host 'Seleção explícita de jobs' -ForegroundColor Cyan
    foreach($warningText in @($discovery.Errors)){Write-Host ('Aviso de descoberta: '+$warningText) -ForegroundColor Yellow}
    $jobs = @($discovery.Jobs)
    for ($index=0; $index -lt $jobs.Count; $index++) {
        $job=$jobs[$index]
        $scheduled=if($null -eq $job.IsScheduled){'desconhecido'}elseif($job.IsScheduled){'sim'}else{'não'}
        Write-Host ('[{0}] {1} | Tipo: {2} | Agendado: {3} | Confiança: {4}' -f ($index+1),$job.Name,$job.Type,$scheduled,$job.Confidence)
    }
    Write-Host '[M] Informar um nome manualmente'
    $raw = Read-Host 'Digite os números separados por vírgula ou M'
    $chosen = [System.Collections.Generic.List[object]]::new()
    if ($raw.Trim() -match '(?i)^m$') {
        $manual = Read-Host 'Nome exato do job'
        if ([string]::IsNullOrWhiteSpace($manual)) { throw 'Nome manual vazio.' }
        $confirm = Read-Host "Digite CONFIRMAR para incluir '$manual' sem identificação automática"
        if ($confirm -cne 'CONFIRMAR') { throw 'Inclusão manual cancelada.' }
        $manualBackupType = Read-Host 'Tipo [Default/Full/FullCopy/Diff/TranLog/TranLogCopy] (Enter=Default)'; if([string]::IsNullOrWhiteSpace($manualBackupType)){$manualBackupType='Default'}; if($manualBackupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')){throw "Tipo de backup inválido: $manualBackupType"}; $chosen.Add([pscustomobject]@{Name=$manual.Trim();Type='Desconhecido';IsScheduled=$null;LastRunAt=$null;Source='Manual';BackupType=$manualBackupType;ConfirmedByTechnician=$true;ConfirmedAtUtc=[DateTime]::UtcNow.ToString('o');ConfirmedBy=[Security.Principal.WindowsIdentity]::GetCurrent().Name;ConfirmationReason='Nome informado manualmente e confirmado com CONFIRMAR'})
    }
    else {
        $indices = @($raw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($indices.Count -eq 0) { throw 'Nenhum job selecionado.' }
        $seen=@{}
        foreach($text in $indices) {
            $number=0
            if(-not [int]::TryParse($text,[ref]$number) -or $number -lt 1 -or $number -gt $jobs.Count){throw "Índice inválido: $text"}
            $job=$jobs[$number-1]
            $key=([string]$job.Name).ToLowerInvariant(); if($seen.ContainsKey($key)){continue};$seen[$key]=$true
            if($job.IsBackup -eq $false){throw "O item '$($job.Name)' foi identificado como $($job.Type), não como backup."}
            if($job.IsScheduled -eq $false){$answer=Read-Host "'$($job.Name)' não está agendado. Digite INCLUIR para confirmar";if($answer -cne 'INCLUIR'){continue}}
            if($job.Confidence -ne 'High'){$answer=Read-Host "O tipo de '$($job.Name)' não foi confirmado por API pública. Digite CONFIRMAR para incluir";if($answer -cne 'CONFIRMAR'){continue}}
            $backupType = Read-Host "Tipo para '$($job.Name)' [Default/Full/FullCopy/Diff/TranLog/TranLogCopy] (Enter=Default)"; if([string]::IsNullOrWhiteSpace($backupType)){$backupType='Default'}; if($backupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')){throw "Tipo de backup inválido: $backupType"}; $chosen.Add([pscustomobject]@{Name=[string]$job.Name;Type=[string]$job.Type;IsScheduled=$job.IsScheduled;LastRunAt=$job.LastRunAt;Source=[string]$job.Source;BackupType=$backupType;ConfirmedByTechnician=$true;ConfirmedAtUtc=[DateTime]::UtcNow.ToString('o');ConfirmedBy=[Security.Principal.WindowsIdentity]::GetCurrent().Name;ConfirmationReason=$(if($job.IsScheduled -eq $false){'Job não agendado incluído explicitamente'}elseif($job.Confidence -ne 'High'){'Descoberta de baixa/média confiança confirmada'}else{'Job de backup selecionado explicitamente'})})
        }
    }
    if($chosen.Count -eq 0){throw 'Nenhum job foi confirmado.'}
    $stopOnFirst = Read-ConsoleYesNo 'Parar após a primeira falha' $(if($existing){[bool]$existing.Execution.StopOnFirstFailure}else{$false})
    $restartTask = Read-ConsoleYesNo 'Permitir que o Agendador reinicie a tarefa após falha' $(if($existing){[bool]$existing.Execution.TaskRestartOnFailure}else{$false})
    $retryCountValue=Read-ConsoleInteger 'Novas tentativas por job (0 é o padrão mais seguro)' $(if($existing){[int]$existing.Execution.RetryCount}else{0}) 0 10
    $retryCliDefault=if($existing){ConvertTo-AutoRunnerBoolean -Value $existing.Execution.RetryOnCliError -Default $false}else{$false}
    $retryOnCliError=$false
    if($retryCountValue -gt 0){
        $retryOnCliError=Read-ConsoleYesNo 'Repetir também quando a CLI retornar código de erro (pode gerar disparo duplicado)' $retryCliDefault
        if($retryOnCliError){Write-Host 'ATENÇÃO: use esta opção somente após validar o comportamento da versão da CLI.' -ForegroundColor Yellow}
    }
    $defaultSqlMode=if($existing){[string]$existing.Execution.SqlServiceWaitMode}else{'AnyAutomaticLocal'}
    do{$sqlMode=Read-Host "Modo de espera SQL [None/AnyAutomaticLocal/AllAutomaticLocal] [$defaultSqlMode]";if([string]::IsNullOrWhiteSpace($sqlMode)){$sqlMode=$defaultSqlMode}}while($sqlMode -notin @('None','AnyAutomaticLocal','AllAutomaticLocal'))
    $execution = [pscustomobject]@{
        StartupDelayMinutes=Read-ConsoleInteger 'Atraso após o boot, em minutos' $(if($existing){[int]$existing.Execution.StartupDelayMinutes}else{5}) 0 120
        MinimumIntervalHours=Read-ConsoleInteger 'Intervalo mínimo por job após retorno sem erro da CLI, em horas' $(if($existing){[int]$existing.Execution.MinimumIntervalHours}else{12}) 0 720
        RetryCount=$retryCountValue
        RetryDelayMinutes=Read-ConsoleInteger 'Espera entre tentativas, em minutos' $(if($existing){[int]$existing.Execution.RetryDelayMinutes}else{2}) 0 60
        RetryOnCliError=$retryOnCliError
        ServiceWaitSeconds=Read-ConsoleInteger 'Espera pelo serviço SQLBackupAndFTP, em segundos' $(if($existing){[int]$existing.Execution.ServiceWaitSeconds}else{300}) 0 1800
        SqlServiceWaitSeconds=Read-ConsoleInteger 'Espera pelos serviços SQL Server, em segundos' $(if($existing){[int]$existing.Execution.SqlServiceWaitSeconds}else{300}) 0 1800
        SqlServiceWaitMode=$sqlMode
        ExecutionTimeLimitHours=Read-ConsoleInteger 'Limite máximo da tarefa, em horas' $(if($existing){[int]$existing.Execution.ExecutionTimeLimitHours}else{24}) 1 168
        PostJobDelaySeconds=Read-ConsoleInteger 'Espera entre jobs, em segundos' $(if($existing){[int]$existing.Execution.PostJobDelaySeconds}else{5}) 0 600
        StopOnFirstFailure=$stopOnFirst
        TaskRestartOnFailure=$restartTask
        TaskRestartCount=Read-ConsoleInteger 'Quantidade máxima de reinícios da tarefa' $(if($existing){[int]$existing.Execution.TaskRestartCount}else{1}) 1 10
        TaskRestartIntervalMinutes=Read-ConsoleInteger 'Intervalo entre reinícios da tarefa, em minutos' $(if($existing){[int]$existing.Execution.TaskRestartIntervalMinutes}else{5}) 1 1440
    }
    if($execution.TaskRestartOnFailure -and [int]$execution.MinimumIntervalHours -eq 0){
        Write-Host 'ATENÇÃO: reiniciar a tarefa com intervalo mínimo 0 pode repetir jobs que já retornaram sem erro antes de uma falha posterior.' -ForegroundColor Yellow
        if(-not(Read-ConsoleYesNo 'Confirma esta combinação de risco' $false)){throw 'Configuração cancelada para evitar repetição involuntária.'}
    }
    $logging=[pscustomobject]@{
        MaxSizeMB=Read-ConsoleInteger 'Tamanho máximo de cada log, em MB' $(if($existing){[int]$existing.Logging.MaxSizeMB}else{10}) 1 1024
        KeepFiles=Read-ConsoleInteger 'Quantidade de arquivos rotacionados mantidos' $(if($existing){[int]$existing.Logging.KeepFiles}else{5}) 1 50
        RetentionDays=Read-ConsoleInteger 'Retenção de logs, em dias' $(if($existing){[int]$existing.Logging.RetentionDays}else{90}) 1 3650
    }
    $request=New-InstallRequest -Jobs @($chosen) -Execution $execution -Logging $logging
    $mode=if($installed.IsInstalled){'Reconfigure'}else{'Install'}
    $code=Invoke-InstallerRequest -Mode $mode -Request $request
    Write-Host "Operação finalizada com código $code."
    return $code
}

function Show-ConsoleMenu {
    do {
        Clear-Host
        $status = Get-CurrentStatus
        Write-Host ('SQLBackupAndFTP AutoRunner ' + (Get-AutoRunnerVersion)) -ForegroundColor Cyan
        Write-Host ('SQLBackupAndFTP: ' + $(if ($status.SqlBak) { 'Detectado ' + $status.SqlBak.CliVersion } else { 'Não detectado' }))
        Write-Host ('Automação: ' + $(if ($status.Installed.IsComplete) { 'Instalada' } elseif($status.Installed.HasConfiguration -or $status.Installed.HasTask) { 'Incompleta, reparo disponível' } else { 'Não instalada' }))
        if ($status.Installed.State) { Write-Host ('Último resultado: ' + $status.Installed.State.LastResult) }
        Write-Host ''
        Write-Host '[1] Instalar/Reconfigurar (modo console seguro)'
        Write-Host '[2] Testar agora'
        Write-Host '[3] Ver última execução'
        Write-Host '[4] Abrir logs'
        Write-Host '[5] Validar instalação'
        Write-Host '[6] Reparar'
        Write-Host '[7] Exportar diagnóstico'
        Write-Host '[8] Desinstalar'
        Write-Host '[0] Sair'
        $choice = Read-Host 'Opção'
        switch ($choice) {
            '1' { try { [void](Invoke-ConsoleConfiguration); pause } catch { Write-Host $_.Exception.Message -ForegroundColor Red; pause } }
            '2' { try { $code=Invoke-TestNow; Write-Host "Código: $code"; pause } catch { Write-Host $_.Exception.Message -ForegroundColor Red; pause } }
            '3' {
                $state=(Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath).State
                if($state){
                    Write-Host ("Início: {0}`nFim: {1}`nGatilho: {2}`nResultado: {3}`nCódigo: {4}" -f $state.LastRunStartedUtc,$state.LastRunCompletedUtc,$state.LastTrigger,$state.LastResult,$state.LastExitCode)
                    foreach($jobResult in @($state.Jobs)){Write-Host ("  - {0}: {1}; código={2}; tentativas={3}" -f $jobResult.Name,$jobResult.Result,$jobResult.ExitCode,$jobResult.Attempts)}
                }else{Write-Host 'Ainda não existe estado de execução.' -ForegroundColor Yellow}
                pause
            }
            '4' { $dir=Join-Path $SupportDir 'logs'; if(Test-Path -LiteralPath $dir){Start-Process explorer.exe -ArgumentList (ConvertTo-AutoRunnerProcessArgument -Value $dir)}else{Write-Host 'Pasta de logs ainda não existe.' -ForegroundColor Yellow}; pause }
            '5' { $validation=Invoke-ValidateCore -WriteConsole; Write-Host ("Código: {0}" -f $validation.ExitCode); pause }
            '6' { $code=Invoke-RepairCore; Write-Host "Código: $code"; pause }
            '7' { try { $zip=Export-AutoRunnerDiagnostics -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath; Write-Host $zip -ForegroundColor Green } catch { Write-Host $_.Exception.Message -ForegroundColor Red }; pause }
            '8' { $confirm=Read-Host 'Digite REMOVER para confirmar'; if ($confirm -eq 'REMOVER') { Invoke-UninstallCore -Keep; return } }
            '0' { return }
            default { Write-Host 'Opção inválida.' -ForegroundColor Yellow; Start-Sleep 1 }
        }
    } while ($true)
}

function Show-Gui {
    [CmdletBinding()]
    param([switch]$SmokeTest,[switch]$TutorialSmokeTest)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
try{[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)}catch{}
    if(-not ('AlphaSoftware.AutoRunner.NativeUi' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AlphaSoftware.AutoRunner {
[StructLayout(LayoutKind.Sequential, Pack=4)]
public struct AutoRunnerPropertyKey {
    public Guid formatId;
    public uint propertyId;
    public AutoRunnerPropertyKey(Guid formatId, uint propertyId) { this.formatId=formatId; this.propertyId=propertyId; }
}
[StructLayout(LayoutKind.Explicit)]
public struct AutoRunnerPropVariant {
    [FieldOffset(0)] public ushort valueType;
    [FieldOffset(8)] public IntPtr pointerValue;
}
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAutoRunnerPropertyStore {
    [PreserveSig] int GetCount(out uint cProps);
    [PreserveSig] int GetAt(uint iProp, out AutoRunnerPropertyKey pkey);
    [PreserveSig] int GetValue(ref AutoRunnerPropertyKey key, out AutoRunnerPropVariant pv);
    [PreserveSig] int SetValue(ref AutoRunnerPropertyKey key, ref AutoRunnerPropVariant pv);
    [PreserveSig] int Commit();
}
public static class NativeUi {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", EntryPoint="SetProcessDpiAwarenessContext")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shell32.dll", PreserveSig=true)] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IAutoRunnerPropertyStore propertyStore);
    [DllImport("ole32.dll", PreserveSig=true)] static extern int PropVariantClear(ref AutoRunnerPropVariant pvar);

    static AutoRunnerPropVariant StringVariant(string value) {
        AutoRunnerPropVariant pv=new AutoRunnerPropVariant();
        pv.valueType=31; // VT_LPWSTR
        pv.pointerValue=Marshal.StringToCoTaskMemUni(value ?? String.Empty);
        return pv;
    }
    static void SetString(IAutoRunnerPropertyStore store, Guid fmt, uint pid, string value) {
        AutoRunnerPropertyKey key=new AutoRunnerPropertyKey(fmt,pid);
        AutoRunnerPropVariant pv=StringVariant(value);
        try {
            int hr=store.SetValue(ref key,ref pv);
            if(hr<0) Marshal.ThrowExceptionForHR(hr);
        } finally { PropVariantClear(ref pv); }
    }
    public static void SetWindowAppIdentity(IntPtr hwnd,string appId,string relaunchCommand,string displayName,string iconResource) {
        Guid iid=new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IAutoRunnerPropertyStore store=null;
        int hr=SHGetPropertyStoreForWindow(hwnd,ref iid,out store);
        if(hr<0 || store==null) Marshal.ThrowExceptionForHR(hr);
        Guid fmt=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        try {
            // Em processo host (powershell.exe), o Shell precisa saber como relançar
            // e qual ícone representa a janela. A documentação do Windows exige que
            // essas propriedades sejam gravadas antes de PKEY_AppUserModel_ID.
            SetString(store,fmt,2,relaunchCommand); // PKEY_AppUserModel_RelaunchCommand
            SetString(store,fmt,4,displayName);     // PKEY_AppUserModel_RelaunchDisplayNameResource
            SetString(store,fmt,3,iconResource);    // PKEY_AppUserModel_RelaunchIconResource
            SetString(store,fmt,5,appId);           // PKEY_AppUserModel_ID
            hr=store.Commit();
            if(hr<0) Marshal.ThrowExceptionForHR(hr);
        } finally {
            if(store!=null) Marshal.ReleaseComObject(store);
        }
    }
}
}
'@ -ErrorAction Stop
    }

    try{[void][AlphaSoftware.AutoRunner.NativeUi]::SetCurrentProcessExplicitAppUserModelID('AlphaSoftware.SQLBackupAndFTPAutoRunner')}catch{}
    try{[void][AlphaSoftware.AutoRunner.NativeUi]::SetProcessDpiAwarenessContext([IntPtr](-4))}catch{try{[void][AlphaSoftware.AutoRunner.NativeUi]::SetProcessDPIAware()}catch{}}

    $form = New-Object Windows.Forms.Form
    $form.Text = 'SQLBackupAndFTP AutoRunner'
    $form.Size = [Drawing.Size]::new(1180,800)
    $form.MinimumSize = [Drawing.Size]::new(900,620)
    $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = New-Object Drawing.Font('Segoe UI',10)
    $form.BackColor = [Drawing.Color]::FromArgb(244,247,251)
    $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
    $form.ShowIcon = $true
    $form.Opacity = 1
    $mainIconPath = Join-Path $rootDir 'assets\AutoRunner.ico'
    if (-not (Test-Path -LiteralPath $mainIconPath)) { $mainIconPath = Join-Path $SupportDir 'assets\AutoRunner.ico' }
    if (Test-Path -LiteralPath $mainIconPath) {
        try { $form.Icon = [Drawing.Icon]::new($mainIconPath) }
        catch { Write-ManagerLog ("Não foi possível carregar o ícone da janela: " + $_.Exception.Message) 'WARN' }
    }
    $relaunchPath=Join-Path $rootDir 'SQLBackupAndFTP-AutoRunner.exe'
    if(-not(Test-Path -LiteralPath $relaunchPath -PathType Leaf)){$relaunchPath=Join-Path $SupportDir 'SQLBackupAndFTP-AutoRunner.exe'}
    $form.Add_Shown({
        try{
            if(Test-Path -LiteralPath $relaunchPath -PathType Leaf){
                $relaunchCommand='"'+$relaunchPath+'"'
                $relaunchIcon=$relaunchPath+',0'
                [AlphaSoftware.AutoRunner.NativeUi]::SetWindowAppIdentity(
                    $form.Handle,
                    'AlphaSoftware.SQLBackupAndFTPAutoRunner',
                    $relaunchCommand,
                    'SQLBackupAndFTP AutoRunner',
                    $relaunchIcon
                )
            }
        }catch{Write-ManagerLog ('Não foi possível aplicar a identidade visual da barra de tarefas: '+$_.Exception.Message) 'WARN'}
    })

    function Set-WindowOnActiveScreen {
        param(
            [Parameter(Mandatory=$true)][Windows.Forms.Form]$Window,
            [int]$PreferredWidth,
            [int]$PreferredHeight,
            [int]$MinimumWidth=680,
            [int]$MinimumHeight=480
        )
        try{
            $screen=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position)
            if($null -eq $screen){$screen=[Windows.Forms.Screen]::PrimaryScreen}
            $area=$screen.WorkingArea
            $availableWidth=[Math]::Max(480,$area.Width-32)
            $availableHeight=[Math]::Max(360,$area.Height-32)
            $width=[Math]::Min($PreferredWidth,$availableWidth)
            $height=[Math]::Min($PreferredHeight,$availableHeight)
            if($availableWidth -ge $MinimumWidth){$width=[Math]::Max($MinimumWidth,$width)}
            if($availableHeight -ge $MinimumHeight){$height=[Math]::Max($MinimumHeight,$height)}
            $Window.MinimumSize=[Drawing.Size]::new([Math]::Min($MinimumWidth,$availableWidth),[Math]::Min($MinimumHeight,$availableHeight))
            $Window.Size=[Drawing.Size]::new([int]$width,[int]$height)
            $Window.Location=[Drawing.Point]::new(
                [int]($area.Left+[Math]::Max(0,($area.Width-$width)/2)),
                [int]($area.Top+[Math]::Max(0,($area.Height-$height)/2))
            )
            $Window.WindowState=[Windows.Forms.FormWindowState]::Normal
        }catch{
            Write-ManagerLog ('Falha ao posicionar janela: '+$_.Exception.Message) 'WARN'
        }
    }

    $colorNavy = [Drawing.Color]::FromArgb(18,39,62)
    $colorNavyLight = [Drawing.Color]::FromArgb(28,57,86)
    $colorBlue = [Drawing.Color]::FromArgb(30,112,213)
    $colorBlueHover = [Drawing.Color]::FromArgb(20,92,188)
    $colorGreen = [Drawing.Color]::FromArgb(22,153,99)
    $colorAmber = [Drawing.Color]::FromArgb(220,145,20)
    $colorRed = [Drawing.Color]::FromArgb(204,62,68)
    $colorText = [Drawing.Color]::FromArgb(31,42,55)
    $colorMuted = [Drawing.Color]::FromArgb(101,113,128)
    $colorBorder = [Drawing.Color]::FromArgb(218,224,232)
    $colorCard = [Drawing.Color]::White

    function New-ModernButton {
        param(
            [Parameter(Mandatory=$true)][string]$Text,
            [ValidateSet('Primary','Secondary','Ghost','Danger')][string]$Kind='Secondary',
            [int]$Height=42
        )
        $button = New-Object Windows.Forms.Button
        $button.Text = $Text
        $button.Height = $Height
        $button.Dock = 'Fill'
        $button.Margin = New-Object Windows.Forms.Padding(6)
        $button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderSize = 1
        $button.Cursor = [Windows.Forms.Cursors]::Hand
        $button.Font = New-Object Drawing.Font('Segoe UI Semibold',9.5)
        switch($Kind){
            'Primary' {
                $button.BackColor=$colorBlue; $button.ForeColor=[Drawing.Color]::White
                $button.FlatAppearance.BorderColor=$colorBlue; $button.FlatAppearance.MouseOverBackColor=$colorBlueHover
            }
            'Danger' {
                $button.BackColor=[Drawing.Color]::FromArgb(255,245,246); $button.ForeColor=$colorRed
                $button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(240,190,194); $button.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(255,232,234)
            }
            'Ghost' {
                $button.BackColor=$colorNavy; $button.ForeColor=[Drawing.Color]::FromArgb(224,232,240)
                $button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(55,80,105); $button.FlatAppearance.MouseOverBackColor=$colorNavyLight
            }
            default {
                $button.BackColor=[Drawing.Color]::White; $button.ForeColor=$colorText
                $button.FlatAppearance.BorderColor=$colorBorder; $button.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(238,244,252)
            }
        }
        return $button
    }

    function New-StatusCard {
        param([string]$Caption)
        $card=New-Object Windows.Forms.Panel
        $card.Dock='Fill';$card.Margin=New-Object Windows.Forms.Padding(7);$card.Padding=New-Object Windows.Forms.Padding(16,12,16,10)
        $card.BackColor=$colorCard;$card.BorderStyle=[Windows.Forms.BorderStyle]::FixedSingle

        $layout=New-Object Windows.Forms.TableLayoutPanel
        $layout.Dock='Fill';$layout.Margin=0;$layout.Padding=0;$layout.ColumnCount=1;$layout.RowCount=3
        [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,24)))
        [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,38)))
        [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

        $captionLabel=New-Object Windows.Forms.Label
        $captionLabel.Text=$Caption.ToUpperInvariant();$captionLabel.Dock='Fill';$captionLabel.AutoEllipsis=$true
        $captionLabel.ForeColor=$colorMuted;$captionLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$captionLabel.TextAlign='MiddleLeft';$captionLabel.Margin=0

        $stateRow=New-Object Windows.Forms.TableLayoutPanel
        $stateRow.Dock='Fill';$stateRow.Margin=0;$stateRow.Padding=0;$stateRow.ColumnCount=2;$stateRow.RowCount=1
        [void]$stateRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,28)))
        [void]$stateRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        $dot=New-Object Windows.Forms.Label
        $dot.Text='●';$dot.Dock='Fill';$dot.Font=New-Object Drawing.Font('Segoe UI',12);$dot.ForeColor=$colorAmber;$dot.TextAlign='MiddleLeft';$dot.Margin=0
        $titleLabel=New-Object Windows.Forms.Label
        $titleLabel.Text='Carregando...';$titleLabel.Dock='Fill';$titleLabel.AutoEllipsis=$true;$titleLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',12.5)
        $titleLabel.ForeColor=$colorText;$titleLabel.TextAlign='MiddleLeft';$titleLabel.Margin=0
        [void]$stateRow.Controls.Add($dot,0,0);[void]$stateRow.Controls.Add($titleLabel,1,0)

        $detailLabel=New-Object Windows.Forms.Label
        $detailLabel.Text='Aguarde a leitura do ambiente.';$detailLabel.Dock='Fill';$detailLabel.AutoEllipsis=$true;$detailLabel.ForeColor=$colorMuted
        $detailLabel.TextAlign='TopLeft';$detailLabel.Margin=New-Object Windows.Forms.Padding(0,4,0,0)

        [void]$layout.Controls.Add($captionLabel,0,0);[void]$layout.Controls.Add($stateRow,0,1);[void]$layout.Controls.Add($detailLabel,0,2)
        $card.Controls.Add($layout)
        return [pscustomobject]@{Panel=$card;Dot=$dot;Title=$titleLabel;Detail=$detailLabel}
    }
    $rootGrid=New-Object Windows.Forms.TableLayoutPanel
    $rootGrid.Dock='Fill';$rootGrid.ColumnCount=2;$rootGrid.RowCount=1;$rootGrid.Margin=0;$rootGrid.Padding=0
    [void]$rootGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,272)))
    [void]$rootGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$rootGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    $form.Controls.Add($rootGrid)

    # Barra lateral totalmente baseada em TableLayout. Nenhum botão depende de
    # coordenadas fixas, então 125/150/175/200% de DPI não os empurra para fora.
    $sidebar=New-Object Windows.Forms.Panel
    $sidebar.Dock='Fill';$sidebar.BackColor=$colorNavy;$sidebar.Padding=New-Object Windows.Forms.Padding(18,18,18,16);$sidebar.AutoScroll=$true
    [void]$rootGrid.Controls.Add($sidebar,0,0)
    $sideGrid=New-Object Windows.Forms.TableLayoutPanel
    $sideGrid.Dock='Fill';$sideGrid.Margin=0;$sideGrid.Padding=0;$sideGrid.ColumnCount=1;$sideGrid.RowCount=13
    [void]$sideGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    foreach($h in @(82,1,34,52,48,48,16,34,48,48)){[void]$sideGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$h)))}
    [void]$sideGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$sideGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,80)))
    [void]$sideGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)))
    $sidebar.Controls.Add($sideGrid)

    $brandGrid=New-Object Windows.Forms.TableLayoutPanel
    $brandGrid.Dock='Fill';$brandGrid.Margin=0;$brandGrid.ColumnCount=2;$brandGrid.RowCount=1
    [void]$brandGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,56)))
    [void]$brandGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    $mainLogoPath=Join-Path $rootDir 'assets\AutoRunner.png'
    if(-not(Test-Path -LiteralPath $mainLogoPath)){$mainLogoPath=Join-Path $SupportDir 'assets\AutoRunner.png'}
    if(Test-Path -LiteralPath $mainLogoPath){
        try{
            $logo=New-Object Windows.Forms.PictureBox;$logo.Image=[Drawing.Image]::FromFile($mainLogoPath);$logo.SizeMode='Zoom';$logo.Dock='Fill';$logo.Margin=New-Object Windows.Forms.Padding(0,7,10,15)
            [void]$brandGrid.Controls.Add($logo,0,0)
        }catch{Write-ManagerLog ("Não foi possível carregar o logotipo: "+$_.Exception.Message) 'WARN'}
    }
    $brandTextGrid=New-Object Windows.Forms.TableLayoutPanel
    $brandTextGrid.Dock='Fill';$brandTextGrid.Margin=0;$brandTextGrid.ColumnCount=1;$brandTextGrid.RowCount=2
    [void]$brandTextGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,62)))
    [void]$brandTextGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,38)))
    $brand=New-Object Windows.Forms.Label;$brand.Text='AutoRunner';$brand.Dock='Fill';$brand.AutoEllipsis=$true;$brand.ForeColor=[Drawing.Color]::White;$brand.Font=New-Object Drawing.Font('Segoe UI Semibold',18);$brand.TextAlign='BottomLeft';$brand.Margin=0
    $brandSub=New-Object Windows.Forms.Label;$brandSub.Text=('SQLBackupAndFTP  •  '+(Get-AutoRunnerDisplayVersion));$brandSub.Dock='Fill';$brandSub.AutoEllipsis=$true;$brandSub.ForeColor=[Drawing.Color]::FromArgb(166,184,202);$brandSub.Font=New-Object Drawing.Font('Segoe UI',9);$brandSub.TextAlign='TopLeft';$brandSub.Margin=0
    [void]$brandTextGrid.Controls.Add($brand,0,0);[void]$brandTextGrid.Controls.Add($brandSub,0,1);[void]$brandGrid.Controls.Add($brandTextGrid,1,0)
    [void]$sideGrid.Controls.Add($brandGrid,0,0)

    $sideLine=New-Object Windows.Forms.Panel;$sideLine.Dock='Fill';$sideLine.BackColor=[Drawing.Color]::FromArgb(46,70,94);$sideLine.Margin=0;[void]$sideGrid.Controls.Add($sideLine,0,1)
    $sideLabel=New-Object Windows.Forms.Label;$sideLabel.Text='CONFIGURAÇÃO';$sideLabel.Dock='Fill';$sideLabel.ForeColor=[Drawing.Color]::FromArgb(134,158,181);$sideLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$sideLabel.TextAlign='MiddleLeft';$sideLabel.Margin=0;[void]$sideGrid.Controls.Add($sideLabel,0,2)

    $btnConfigure=New-ModernButton 'Configurar automação' 'Primary' 44;$btnConfigure.Margin=New-Object Windows.Forms.Padding(0,3,0,3);[void]$sideGrid.Controls.Add($btnConfigure,0,3)
    $btnLocate=New-ModernButton 'Localizar SQLBackupAndFTP' 'Ghost' 42;$btnLocate.Margin=New-Object Windows.Forms.Padding(0,3,0,3);[void]$sideGrid.Controls.Add($btnLocate,0,4)
    $btnDownloadSql=New-ModernButton 'Baixar SQLBackupAndFTP' 'Ghost' 42;$btnDownloadSql.Margin=New-Object Windows.Forms.Padding(0,3,0,3);[void]$sideGrid.Controls.Add($btnDownloadSql,0,5)

    $supportLabel=New-Object Windows.Forms.Label;$supportLabel.Text='SUPORTE';$supportLabel.Dock='Fill';$supportLabel.ForeColor=[Drawing.Color]::FromArgb(134,158,181);$supportLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',8.5);$supportLabel.TextAlign='MiddleLeft';$supportLabel.Margin=0;[void]$sideGrid.Controls.Add($supportLabel,0,7)
    $btnHelp=New-ModernButton 'Ajuda e tutorial' 'Ghost' 42;$btnHelp.Margin=New-Object Windows.Forms.Padding(0,3,0,3);[void]$sideGrid.Controls.Add($btnHelp,0,8)
    $btnUpdates=New-ModernButton 'Verificar atualizações' 'Ghost' 42;$btnUpdates.Margin=New-Object Windows.Forms.Padding(0,3,0,3);[void]$sideGrid.Controls.Add($btnUpdates,0,9)

    $sideNote=New-Object Windows.Forms.Label
    $sideNote.Text="Executa somente os jobs selecionados.`r`nNão altera bancos, credenciais, destinos ou retenção."
    $sideNote.Dock='Fill';$sideNote.AutoEllipsis=$true;$sideNote.ForeColor=[Drawing.Color]::FromArgb(154,174,194);$sideNote.Font=New-Object Drawing.Font('Segoe UI',9);$sideNote.TextAlign='BottomLeft';$sideNote.Margin=New-Object Windows.Forms.Padding(0,8,0,8)
    [void]$sideGrid.Controls.Add($sideNote,0,11)
    $btnClose=New-ModernButton 'Fechar aplicativo' 'Ghost' 40;$btnClose.Margin=0;[void]$sideGrid.Controls.Add($btnClose,0,12)

    # Área principal com viewport rolável. O conteúdo tem uma altura mínima
    # funcional e cresce junto com a janela; abaixo disso surge rolagem em vez
    # de achatar botões, grids e painéis.
    $mainHost=New-Object Windows.Forms.Panel
    $mainHost.Dock='Fill';$mainHost.AutoScroll=$true;$mainHost.Margin=0;$mainHost.Padding=0;$mainHost.BackColor=$form.BackColor
    [void]$rootGrid.Controls.Add($mainHost,1,0)

    $mainGrid=New-Object Windows.Forms.TableLayoutPanel
    $mainGrid.Dock='Top';$mainGrid.BackColor=$form.BackColor;$mainGrid.ColumnCount=1;$mainGrid.RowCount=5;$mainGrid.Padding=New-Object Windows.Forms.Padding(20,12,20,10)
    $mainGrid.Height=760
    [void]$mainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,82)))
    [void]$mainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,158)))
    [void]$mainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,220)))
    [void]$mainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$mainGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
    $mainHost.Controls.Add($mainGrid)
    $resizeMainContent={
        try{
            $dpiScale=1.0
            try{if($form.DeviceDpi -gt 96){$dpiScale=[double]$form.DeviceDpi/96.0}}catch{}
            $contentFloor=[int][Math]::Ceiling(760*$dpiScale)
            $mainGrid.Height=[Math]::Max($contentFloor,$mainHost.ClientSize.Height-2)
        }catch{}
    }
    $mainHost.Add_Resize($resizeMainContent)

    $header=New-Object Windows.Forms.TableLayoutPanel
    $header.Dock='Fill';$header.BackColor=$form.BackColor;$header.Margin=New-Object Windows.Forms.Padding(5,0,5,0);$header.ColumnCount=1;$header.RowCount=3
    [void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,42)))
    [void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,4)))
    $title=New-Object Windows.Forms.Label;$title.Text='Painel de automação';$title.ForeColor=$colorText;$title.Font=New-Object Drawing.Font('Segoe UI Semibold',21);$title.Dock='Fill';$title.AutoEllipsis=$true;$title.TextAlign='BottomLeft';$title.Margin=0
    $subtitle=New-Object Windows.Forms.Label;$subtitle.Text='Acompanhe o ambiente, configure os jobs e valide cada execução.';$subtitle.ForeColor=$colorMuted;$subtitle.Dock='Fill';$subtitle.AutoEllipsis=$true;$subtitle.TextAlign='TopLeft';$subtitle.Margin=New-Object Windows.Forms.Padding(2,2,0,0)
    $loadingBar=New-Object Windows.Forms.ProgressBar;$loadingBar.Style=[Windows.Forms.ProgressBarStyle]::Marquee;$loadingBar.MarqueeAnimationSpeed=28;$loadingBar.Dock='Fill';$loadingBar.Visible=$true;$loadingBar.Margin=0
    [void]$header.Controls.Add($title,0,0);[void]$header.Controls.Add($subtitle,0,1);[void]$header.Controls.Add($loadingBar,0,2);[void]$mainGrid.Controls.Add($header,0,0)

    $statusCards=New-Object Windows.Forms.TableLayoutPanel
    $statusCards.Dock='Fill';$statusCards.ColumnCount=3;$statusCards.RowCount=1;$statusCards.Margin=0
    1..3|ForEach-Object{[void]$statusCards.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,33.3333)))}
    [void]$statusCards.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    $sqlCard=New-StatusCard 'SQLBackupAndFTP';$automationCard=New-StatusCard 'Automação';$lastCard=New-StatusCard 'Última execução'
    [void]$statusCards.Controls.Add($sqlCard.Panel,0,0);[void]$statusCards.Controls.Add($automationCard.Panel,1,0);[void]$statusCards.Controls.Add($lastCard.Panel,2,0);[void]$mainGrid.Controls.Add($statusCards,0,1)

    $actionArea=New-Object Windows.Forms.TableLayoutPanel
    $actionArea.Dock='Fill';$actionArea.ColumnCount=2;$actionArea.RowCount=1;$actionArea.Margin=New-Object Windows.Forms.Padding(0,6,0,6)
    [void]$actionArea.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,54)))
    [void]$actionArea.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,46)))
    [void]$actionArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

    function New-ActionCard([string]$Caption,[int]$Rows,[int]$Columns){
        $panel=New-Object Windows.Forms.Panel;$panel.Dock='Fill';$panel.Margin=New-Object Windows.Forms.Padding(7);$panel.Padding=New-Object Windows.Forms.Padding(14,10,14,12);$panel.BackColor=$colorCard;$panel.BorderStyle='FixedSingle'
        $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.Margin=0;$layout.ColumnCount=1;$layout.RowCount=2
        [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,34)));[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        $captionLabel=New-Object Windows.Forms.Label;$captionLabel.Text=$Caption;$captionLabel.Dock='Fill';$captionLabel.AutoEllipsis=$true;$captionLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',11.5);$captionLabel.ForeColor=$colorText;$captionLabel.TextAlign='MiddleLeft';$captionLabel.Margin=0
        $grid=New-Object Windows.Forms.TableLayoutPanel;$grid.Dock='Fill';$grid.Margin=0;$grid.Padding=0;$grid.ColumnCount=$Columns;$grid.RowCount=$Rows
        for($c=0;$c -lt $Columns;$c++){[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,(100.0/$Columns))))}
        for($r=0;$r -lt $Rows;$r++){[void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,(100.0/$Rows))))}
        [void]$layout.Controls.Add($captionLabel,0,0);[void]$layout.Controls.Add($grid,0,1);$panel.Controls.Add($layout)
        return [pscustomobject]@{Panel=$panel;Grid=$grid}
    }

    $quick=New-ActionCard 'Ações rápidas' 2 2
    $btnTest=New-ModernButton '▶  Testar backup agora' 'Primary'
    $btnLast=New-ModernButton '◷  Ver última execução' 'Secondary'
    $btnLogs=New-ModernButton '▤  Abrir logs' 'Secondary'
    $btnValidate=New-ModernButton '✓  Validar instalação' 'Secondary'
    [void]$quick.Grid.Controls.Add($btnTest,0,0);[void]$quick.Grid.Controls.Add($btnLast,1,0);[void]$quick.Grid.Controls.Add($btnLogs,0,1);[void]$quick.Grid.Controls.Add($btnValidate,1,1)
    [void]$actionArea.Controls.Add($quick.Panel,0,0)

    $tools=New-ActionCard 'Ferramentas e manutenção' 3 2
    $btnRepair=New-ModernButton 'Reparar automação' 'Secondary' 38
    $btnDiag=New-ModernButton 'Exportar diagnóstico' 'Secondary' 38
    $btnApp=New-ModernButton 'Abrir SQLBackupAndFTP' 'Secondary' 38
    $btnOpenFolder=New-ModernButton 'Abrir pasta detectada' 'Secondary' 38
    $btnTask=New-ModernButton 'Abrir Agendador' 'Secondary' 38
    $btnUninstall=New-ModernButton 'Remover automação' 'Danger' 38
    [void]$tools.Grid.Controls.Add($btnRepair,0,0);[void]$tools.Grid.Controls.Add($btnDiag,1,0);[void]$tools.Grid.Controls.Add($btnApp,0,1);[void]$tools.Grid.Controls.Add($btnOpenFolder,1,1);[void]$tools.Grid.Controls.Add($btnTask,0,2);[void]$tools.Grid.Controls.Add($btnUninstall,1,2)
    [void]$actionArea.Controls.Add($tools.Panel,1,0);[void]$mainGrid.Controls.Add($actionArea,0,2)

    $statusGroup=New-Object Windows.Forms.Panel
    $statusGroup.Dock='Fill';$statusGroup.Margin=New-Object Windows.Forms.Padding(7,0,7,5);$statusGroup.Padding=New-Object Windows.Forms.Padding(14,10,14,10);$statusGroup.BackColor=$colorCard;$statusGroup.BorderStyle='FixedSingle'
    $detailLayout=New-Object Windows.Forms.TableLayoutPanel;$detailLayout.Dock='Fill';$detailLayout.Margin=0;$detailLayout.Padding=0;$detailLayout.ColumnCount=2;$detailLayout.RowCount=2
    [void]$detailLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,72)))
    [void]$detailLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,28)))
    [void]$detailLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
    [void]$detailLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
    $detailTitle=New-Object Windows.Forms.Label;$detailTitle.Text='Detalhes do ambiente';$detailTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',11);$detailTitle.ForeColor=$colorText;$detailTitle.Dock='Fill';$detailTitle.TextAlign='MiddleLeft';$detailTitle.Margin=0
    $maintenanceTitle=New-Object Windows.Forms.Label;$maintenanceTitle.Text='Aplicativo e Central';$maintenanceTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$maintenanceTitle.ForeColor=$colorMuted;$maintenanceTitle.Dock='Fill';$maintenanceTitle.TextAlign='MiddleLeft';$maintenanceTitle.Margin=New-Object Windows.Forms.Padding(10,0,0,0)
    $statusText=New-Object Windows.Forms.RichTextBox
    $statusText.ReadOnly=$true;$statusText.BorderStyle='None';$statusText.BackColor=$colorCard;$statusText.ForeColor=$colorMuted;$statusText.Dock='Fill';$statusText.DetectUrls=$false;$statusText.TabStop=$false;$statusText.Margin=New-Object Windows.Forms.Padding(0,4,8,0)
    $maintenanceGrid=New-Object Windows.Forms.TableLayoutPanel;$maintenanceGrid.Dock='Fill';$maintenanceGrid.Margin=New-Object Windows.Forms.Padding(8,4,0,0);$maintenanceGrid.ColumnCount=1;$maintenanceGrid.RowCount=4
    1..4|ForEach-Object{[void]$maintenanceGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,25)))}
    $btnConnectCentral=New-ModernButton 'Conectar à Central' 'Primary' 36
    $btnDisconnectCentral=New-ModernButton 'Desconectar da Central' 'Secondary' 36
    $btnRepairApp=New-ModernButton 'Reparar aplicativo' 'Secondary' 36
    $btnUninstallApp=New-ModernButton 'Desinstalar aplicativo' 'Danger' 36
    [void]$maintenanceGrid.Controls.Add($btnConnectCentral,0,0);[void]$maintenanceGrid.Controls.Add($btnDisconnectCentral,0,1);[void]$maintenanceGrid.Controls.Add($btnRepairApp,0,2);[void]$maintenanceGrid.Controls.Add($btnUninstallApp,0,3)
    [void]$detailLayout.Controls.Add($detailTitle,0,0);[void]$detailLayout.Controls.Add($maintenanceTitle,1,0);[void]$detailLayout.Controls.Add($statusText,0,1);[void]$detailLayout.Controls.Add($maintenanceGrid,1,1)
    $statusGroup.Controls.Add($detailLayout);[void]$mainGrid.Controls.Add($statusGroup,0,3)

    $footer=New-Object Windows.Forms.Label
    $footer.Text='Alpha Software  •  Confirme cada backup no histórico e no destino.';$footer.ForeColor=$colorMuted;$footer.Dock='Fill';$footer.TextAlign='MiddleLeft';$footer.Margin=New-Object Windows.Forms.Padding(7,0,7,0);$footer.AutoEllipsis=$true
    [void]$mainGrid.Controls.Add($footer,0,4)

    $script:guiSqlBak = $null


    function Show-AutoRunnerTutorial {
        [CmdletBinding()]
        param([switch]$Force,[switch]$SmokeTest)

        $settings = Get-AutoRunnerUserSettings
        if (-not $Force -and $settings.TutorialDoNotShowAgain -and $settings.TutorialVersion -eq (Get-AutoRunnerVersion)) { return }

        $pages = @(
            [pscustomobject]@{Title='Bem-vindo';Body="O AutoRunner executa os jobs selecionados quando o Windows inicia. Ele não altera bancos, destinos, credenciais nem o agendamento interno do SQLBackupAndFTP."},
            [pscustomobject]@{Title='1. Localize o SQLBackupAndFTP';Body="Use Localizar SQLBackupAndFTP. A busca verifica caminho salvo, Registro, serviços, processos, atalhos, App Paths e pastas padrão. Se necessário, selecione manualmente a pasta que contém SqlBak.Job.Cli.exe."},
            [pscustomobject]@{Title='2. Instale a automação';Body="Depois da detecção, clique em Instalar automação. Selecione somente os jobs de backup desejados e revise atraso, intervalo mínimo e política de tentativas."},
            [pscustomobject]@{Title='3. Teste e confira';Body="Use Testar backup agora. Retorno zero confirma a chamada da CLI, não o arquivo final. Confira o histórico do SQLBackupAndFTP e o destino do backup."},
            [pscustomobject]@{Title='4. Manutenção';Body="Validar instalação revisa arquivos, configuração, ACL e tarefa. Reparar preserva os jobs. Exportar diagnóstico reúne logs e evidências. Desinstalar não remove os jobs do SQLBackupAndFTP."}
        )

        $wizard=New-Object Windows.Forms.Form
        $wizard.Text='Ajuda do SQLBackupAndFTP AutoRunner'
        $wizard.ClientSize=[Drawing.Size]::new(820,520)
        $wizard.MinimumSize=[Drawing.Size]::new(680,460)
        $wizard.StartPosition=[Windows.Forms.FormStartPosition]::Manual
        $wizard.Font=$form.Font
        $wizard.ShowInTaskbar=$false
        $wizard.ShowIcon=$true
        $wizard.MaximizeBox=$false
        $wizard.MinimizeBox=$false
        $wizard.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
        $wizard.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
        $wizard.BackColor=[Drawing.Color]::FromArgb(246,248,252)
        if($form.Icon){$wizard.Icon=$form.Icon}

        # O estado fica em Form.Tag para não depender da atribuição de variáveis
        # escalares capturadas pelos callbacks do WinForms.
        $wizard.Tag=[pscustomobject]@{
            Index=0
            Pages=$pages
            SmokePassed=$false
            SmokeError=''
        }

        $wizardRoot=New-Object Windows.Forms.TableLayoutPanel
        $wizardRoot.Dock='Fill';$wizardRoot.ColumnCount=2;$wizardRoot.RowCount=1;$wizardRoot.Margin=0;$wizardRoot.Padding=0
        [void]$wizardRoot.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,220)))
        [void]$wizardRoot.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$wizardRoot.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        $wizard.Controls.Add($wizardRoot)

        $guideSide=New-Object Windows.Forms.TableLayoutPanel
        $guideSide.Dock='Fill';$guideSide.BackColor=$colorNavy;$guideSide.Padding=New-Object Windows.Forms.Padding(22,24,22,20)
        $guideSide.ColumnCount=1;$guideSide.RowCount=5;$guideSide.Margin=0
        [void]$guideSide.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$guideSide.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideSide.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideSide.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideSide.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$guideSide.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$wizardRoot.Controls.Add($guideSide,0,0)

        $guideBadge=New-Object Windows.Forms.Label
        $guideBadge.Text='GUIA RÁPIDO';$guideBadge.AutoSize=$true;$guideBadge.ForeColor=[Drawing.Color]::FromArgb(124,147,169);$guideBadge.Font=New-Object Drawing.Font('Segoe UI Semibold',8);$guideBadge.Margin=New-Object Windows.Forms.Padding(0,0,0,14)
        $guideTitle=New-Object Windows.Forms.Label
        $guideTitle.Text='Comece em poucos passos';$guideTitle.AutoSize=$true;$guideTitle.MaximumSize=[Drawing.Size]::new(176,0);$guideTitle.ForeColor=[Drawing.Color]::White;$guideTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',17);$guideTitle.Margin=New-Object Windows.Forms.Padding(0,0,0,24)
        $guideSteps=New-Object Windows.Forms.Label
        $guideSteps.Text="01  Localizar`r`n`r`n02  Configurar`r`n`r`n03  Testar`r`n`r`n04  Acompanhar";$guideSteps.AutoSize=$true;$guideSteps.ForeColor=[Drawing.Color]::FromArgb(213,225,236);$guideSteps.Font=New-Object Drawing.Font('Segoe UI',10.5);$guideSteps.Margin=0
        $guideSpacer=New-Object Windows.Forms.Panel;$guideSpacer.Dock='Fill';$guideSpacer.Margin=0
        $guideNote=New-Object Windows.Forms.Label
        $guideNote.Text='Você pode reabrir este guia a qualquer momento em “Ajuda e tutorial”.';$guideNote.AutoSize=$true;$guideNote.MaximumSize=[Drawing.Size]::new(176,0);$guideNote.ForeColor=[Drawing.Color]::FromArgb(145,164,183);$guideNote.Margin=New-Object Windows.Forms.Padding(0,12,0,0)
        [void]$guideSide.Controls.Add($guideBadge,0,0);[void]$guideSide.Controls.Add($guideTitle,0,1);[void]$guideSide.Controls.Add($guideSteps,0,2);[void]$guideSide.Controls.Add($guideSpacer,0,3);[void]$guideSide.Controls.Add($guideNote,0,4)

        $guideContent=New-Object Windows.Forms.TableLayoutPanel
        $guideContent.Dock='Fill';$guideContent.BackColor=[Drawing.Color]::White;$guideContent.Padding=New-Object Windows.Forms.Padding(34,28,34,22)
        $guideContent.ColumnCount=1;$guideContent.RowCount=6;$guideContent.Margin=0
        [void]$guideContent.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,10)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$guideContent.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$wizardRoot.Controls.Add($guideContent,1,0)

        $pageTitle=New-Object Windows.Forms.Label
        $pageTitle.AutoSize=$true;$pageTitle.MaximumSize=[Drawing.Size]::new(510,0);$pageTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',19);$pageTitle.ForeColor=$colorText;$pageTitle.Margin=New-Object Windows.Forms.Padding(0,0,0,14)

        $pageBody=New-Object Windows.Forms.TextBox
        $pageBody.Multiline=$true;$pageBody.ReadOnly=$true;$pageBody.BorderStyle='None';$pageBody.BackColor=[Drawing.Color]::White;$pageBody.ForeColor=$colorMuted
        $pageBody.Dock='Fill';$pageBody.Margin=New-Object Windows.Forms.Padding(2,0,0,10);$pageBody.Font=New-Object Drawing.Font('Segoe UI',11);$pageBody.TabStop=$false;$pageBody.ScrollBars='Vertical';$pageBody.WordWrap=$true

        $pageProgress=New-Object Windows.Forms.ProgressBar
        $pageProgress.Dock='Fill';$pageProgress.Height=6;$pageProgress.Margin=New-Object Windows.Forms.Padding(0,2,0,2);$pageProgress.Minimum=1;$pageProgress.Maximum=$pages.Count;$pageProgress.Value=1;$pageProgress.Style=[Windows.Forms.ProgressBarStyle]::Continuous

        $progress=New-Object Windows.Forms.Label
        $progress.AutoSize=$true;$progress.ForeColor=$colorMuted;$progress.Margin=New-Object Windows.Forms.Padding(0,7,0,7)

        $dontShow=New-Object Windows.Forms.CheckBox
        $dontShow.Text='Não mostrar novamente nesta versão';$dontShow.AutoSize=$true;$dontShow.Margin=New-Object Windows.Forms.Padding(0,0,0,12);$dontShow.Checked=[bool]$settings.TutorialDoNotShowAgain

        $buttonPanel=New-Object Windows.Forms.FlowLayoutPanel
        $buttonPanel.Dock='Fill';$buttonPanel.AutoSize=$true;$buttonPanel.WrapContents=$false;$buttonPanel.FlowDirection='RightToLeft';$buttonPanel.Margin=0;$buttonPanel.Padding=0
        $next=New-ModernButton 'Avançar' 'Primary' 38;$next.Dock='None';$next.Size=[Drawing.Size]::new(112,38);$next.Margin=New-Object Windows.Forms.Padding(8,0,0,0)
        $back=New-ModernButton 'Voltar' 'Secondary' 38;$back.Dock='None';$back.Size=[Drawing.Size]::new(92,38);$back.Margin=New-Object Windows.Forms.Padding(8,0,0,0)
        $skip=New-ModernButton 'Pular' 'Secondary' 38;$skip.Dock='None';$skip.Size=[Drawing.Size]::new(88,38);$skip.Margin=0
        $buttonPanel.Controls.AddRange(@($next,$back,$skip))

        [void]$guideContent.Controls.Add($pageTitle,0,0)
        [void]$guideContent.Controls.Add($pageBody,0,1)
        [void]$guideContent.Controls.Add($pageProgress,0,2)
        [void]$guideContent.Controls.Add($progress,0,3)
        [void]$guideContent.Controls.Add($dontShow,0,4)
        [void]$guideContent.Controls.Add($buttonPanel,0,5)
        $wizard.AcceptButton=$next
        $wizard.CancelButton=$skip
        $wizard.Add_Load({
            Set-WindowOnActiveScreen -Window $wizard -PreferredWidth 820 -PreferredHeight 520 -MinimumWidth 680 -MinimumHeight 460
        })
        $wizard.Add_Shown({
            try{
                $wizard.ShowInTaskbar=$false
                $wizard.WindowState=[Windows.Forms.FormWindowState]::Normal
                $wizard.Activate()
                $wizard.BringToFront()
            }catch{}
        })


        $showTutorialError={
            param([string]$Context,[System.Exception]$Exception)
            $detail=if($Exception){$Exception.ToString()}else{'Erro não especificado.'}
            Write-ManagerLog ("Tutorial: $Context`r`n$detail") 'ERROR'
            if(-not $SmokeTest){
                [Windows.Forms.MessageBox]::Show(("Não foi possível concluir esta ação do tutorial.`r`n`r`n"+$Exception.Message+"`r`n`r`nO detalhe foi salvo em:`r`n"+$managerLog),'Ajuda do AutoRunner','OK','Error')|Out-Null
            }
        }

        $saveTutorialSettings={
            param([bool]$Completed)
            try{
                Set-AutoRunnerUserSettings -TutorialCompleted $Completed -TutorialDoNotShowAgain $dontShow.Checked -TutorialVersion (Get-AutoRunnerVersion)
                return $true
            }catch{
                & $showTutorialError 'falha ao salvar a preferência' $_.Exception
                return $false
            }
        }

        $render={
            try{
                $state=$wizard.Tag
                if($null -eq $state -or $null -eq $state.Pages){throw 'Estado interno do tutorial não está disponível.'}
                $currentIndex=[int]$state.Index
                if($currentIndex -lt 0 -or $currentIndex -ge $state.Pages.Count){throw "Índice inválido do tutorial: $currentIndex"}
                $currentPage=$state.Pages[$currentIndex]
                $pageTitle.Text=[string]$currentPage.Title
                $pageBody.Text=[string]$currentPage.Body
                $progress.Text=('Etapa {0} de {1}' -f ($currentIndex+1),$state.Pages.Count)
                $pageProgress.Value=[Math]::Min($pageProgress.Maximum,[Math]::Max($pageProgress.Minimum,$currentIndex+1))
                $back.Enabled=($currentIndex -gt 0)
                $next.Text=if($currentIndex -eq $state.Pages.Count-1){'Concluir'}else{'Avançar'}
            }catch{
                $wizard.Tag.SmokeError=$_.Exception.ToString()
                & $showTutorialError 'falha ao renderizar uma página' $_.Exception
                if($SmokeTest){$wizard.Close()}
            }
        }

        $back.Add_Click({
            try{
                $state=$wizard.Tag
                if([int]$state.Index -gt 0){
                    $state.Index=[int]$state.Index-1
                    & $render
                }
            }catch{
                $wizard.Tag.SmokeError=$_.Exception.ToString()
                & $showTutorialError 'falha ao voltar' $_.Exception
                if($SmokeTest){$wizard.Close()}
            }
        })

        $next.Add_Click({
            try{
                $state=$wizard.Tag
                if([int]$state.Index -lt $state.Pages.Count-1){
                    $state.Index=[int]$state.Index+1
                    & $render
                    return
                }
                if (& $saveTutorialSettings $true){
                    $wizard.DialogResult=[Windows.Forms.DialogResult]::OK
                    $wizard.Close()
                }
            }catch{
                $wizard.Tag.SmokeError=$_.Exception.ToString()
                & $showTutorialError 'falha ao avançar' $_.Exception
                if($SmokeTest){$wizard.Close()}
            }
        })

        $skip.Add_Click({
            try{
                if (& $saveTutorialSettings $false){
                    $wizard.DialogResult=[Windows.Forms.DialogResult]::Cancel
                    $wizard.Close()
                }
            }catch{
                $wizard.Tag.SmokeError=$_.Exception.ToString()
                & $showTutorialError 'falha ao pular' $_.Exception
                if($SmokeTest){$wizard.Close()}
            }
        })

        & $render

        if($SmokeTest){
            $wizard.ShowInTaskbar=$false
            $wizard.Opacity=0
            $smokeState=[pscustomobject]@{Step=0}
            $smokeTimer=New-Object Windows.Forms.Timer
            $smokeTimer.Interval=150
            $smokeTimer.Add_Tick({
                try{
                    $state=$wizard.Tag
                    switch([int]$smokeState.Step){
                        0 { if([int]$state.Index -ne 0){throw 'Página inicial incorreta.'};$next.PerformClick() }
                        1 { if([int]$state.Index -ne 1){throw 'Avanço 1 falhou.'};$next.PerformClick() }
                        2 { if([int]$state.Index -ne 2){throw 'Avanço 2 falhou.'};$back.PerformClick() }
                        3 { if([int]$state.Index -ne 1){throw 'Retorno falhou.'};$next.PerformClick() }
                        4 { if([int]$state.Index -ne 2){throw 'Segundo avanço falhou.'};$next.PerformClick() }
                        5 { if([int]$state.Index -ne 3){throw 'Avanço 3 falhou.'};$next.PerformClick() }
                        6 { if([int]$state.Index -ne 4 -or $next.Text -ne 'Concluir'){throw 'Página final incorreta.'};$state.SmokePassed=$true;$next.PerformClick() }
                    }
                    $smokeState.Step=[int]$smokeState.Step+1
                }catch{
                    $wizard.Tag.SmokeError=$_.Exception.ToString()
                    $smokeTimer.Stop()
                    $wizard.Close()
                }
            })
            $wizard.Add_Shown({$smokeTimer.Start()})
            [void]$wizard.ShowDialog()
            $smokeTimer.Stop()
            $smokeTimer.Dispose()
            $smokePassed=[bool]$wizard.Tag.SmokePassed
            $smokeError=[string]$wizard.Tag.SmokeError
            $wizard.Dispose()
            if(-not $smokePassed){throw ('Smoke test do tutorial falhou. '+$smokeError)}
            return
        }

        [void]$wizard.ShowDialog($form)
        $wizard.Dispose()
        # Ao encerrar o assistente, restaure explicitamente a janela principal.
        # Isso evita que ela permaneça atrás de outras janelas ou sem foco após o
        # fechamento de uma caixa modal criada por um host PowerShell oculto.
        if(-not $form.IsDisposed){
            $form.Show()
            $form.WindowState=[Windows.Forms.FormWindowState]::Normal
            $form.Activate()
            $form.BringToFront()
            $form.TopMost=$true
            $form.TopMost=$false
        }
    }

    function Show-SqlBackupLocationDialog {
        $dialog=New-Object Windows.Forms.Form
        $dialog.Text='Localizar SQLBackupAndFTP';$dialog.Size=[Drawing.Size]::new(820,500);$dialog.MinimumSize=[Drawing.Size]::new(720,440);$dialog.StartPosition='CenterParent';$dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi;$dialog.AutoScroll=$true;$dialog.Font=$form.Font;if($form.Icon){$dialog.Icon=$form.Icon}
        $info=New-Object Windows.Forms.Label;$info.Text='Selecione uma instalação validada. A pasta precisa conter SqlBak.Job.Cli.exe.';$info.Location=[Drawing.Point]::new(20,20);$info.AutoSize=$true
        $list=New-Object Windows.Forms.ListBox;$list.Location=[Drawing.Point]::new(20,55);$list.Size=[Drawing.Size]::new(760,270);$list.Anchor='Top,Bottom,Left,Right';$list.HorizontalScrollbar=$true
        $auto=New-Object Windows.Forms.Button;$auto.Text='Procurar automaticamente';$auto.Location=[Drawing.Point]::new(20,345);$auto.Size=[Drawing.Size]::new(200,40);$auto.Anchor='Bottom,Left'
        $manual=New-Object Windows.Forms.Button;$manual.Text='Selecionar pasta';$manual.Location=[Drawing.Point]::new(230,345);$manual.Size=[Drawing.Size]::new(150,40);$manual.Anchor='Bottom,Left'
        $save=New-Object Windows.Forms.Button;$save.Text='Usar selecionada';$save.Location=[Drawing.Point]::new(530,395);$save.Size=[Drawing.Size]::new(140,40);$save.Anchor='Bottom,Right'
        $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancelar';$cancel.Location=[Drawing.Point]::new(680,395);$cancel.Size=[Drawing.Size]::new(100,40);$cancel.Anchor='Bottom,Right';$cancel.DialogResult='Cancel'
        $dialog.Controls.AddRange(@($info,$list,$auto,$manual,$save,$cancel));$dialog.CancelButton=$cancel
        $script:locationCandidates=@()
        $refreshList={
            $list.Items.Clear()
            foreach($candidate in @($script:locationCandidates)){
                $version=if($candidate.AppVersion){$candidate.AppVersion}else{$candidate.CliVersion}
                [void]$list.Items.Add(("{0} | versão {1} | {2}" -f $candidate.InstallDir,$version,(@($candidate.DetectionSources)[0])))
            }
            if($list.Items.Count -gt 0){$list.SelectedIndex=0}
        }
        $auto.Add_Click({
            try{$dialog.UseWaitCursor=$true;$script:locationCandidates=@(Find-SqlBackupAndFTPInstallations -DeepSearch);$dialog.UseWaitCursor=$false;&$refreshList;if($script:locationCandidates.Count -eq 0){[Windows.Forms.MessageBox]::Show('Nenhuma instalação válida foi localizada. Use Selecionar pasta.','Localização','OK','Warning')|Out-Null}}
            catch{$dialog.UseWaitCursor=$false;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro na busca','OK','Error')|Out-Null}
        })
        $manual.Add_Click({
            $folder=New-Object Windows.Forms.FolderBrowserDialog;$folder.Description='Selecione a pasta do SQLBackupAndFTP que contém SqlBak.Job.Cli.exe';$folder.ShowNewFolderButton=$false
            $settings=Get-AutoRunnerUserSettings;if($settings.PreferredSqlBackupPath -and (Test-Path -LiteralPath $settings.PreferredSqlBackupPath)){$folder.SelectedPath=$settings.PreferredSqlBackupPath}
            if($folder.ShowDialog($dialog) -eq 'OK'){
                $validated=Test-SqlBackupAndFTPDirectory -Path $folder.SelectedPath
                if(-not $validated){[Windows.Forms.MessageBox]::Show('A pasta não contém SqlBak.Job.Cli.exe ou não é uma instalação compatível.','Pasta inválida','OK','Error')|Out-Null;return}
                $candidate=Get-SqlBackupAndFTPInstall -PreferredPath $folder.SelectedPath
                $script:locationCandidates=@($candidate)+@($script:locationCandidates|Where-Object{$_.InstallDir -ine $candidate.InstallDir});&$refreshList
            }
        })
        $save.Add_Click({
            if($list.SelectedIndex -lt 0){[Windows.Forms.MessageBox]::Show('Selecione uma instalação.','Localização','OK','Warning')|Out-Null;return}
            $selected=$script:locationCandidates[$list.SelectedIndex]
            Set-AutoRunnerUserSettings -PreferredSqlBackupPath $selected.InstallDir -PreferredSqlBackupCliPath $selected.CliPath -PreferredSqlBackupAppPath $selected.AppPath -DetectionSource (@($selected.DetectionSources)-join '; ')
            $dialog.DialogResult='OK';$dialog.Close()
        })
        try{$script:locationCandidates=@(Find-SqlBackupAndFTPInstallations)}catch{$script:locationCandidates=@()}
        &$refreshList
        Set-WindowOnActiveScreen -Window $dialog -PreferredWidth 820 -PreferredHeight 500 -MinimumWidth 720 -MinimumHeight 440
        [void]$dialog.ShowDialog($form)
        Refresh-StatusUi
    }

    function Show-ControlPlaneEnrollmentDialog {
        $dialog=New-Object Windows.Forms.Form
        $dialog.Text='Conectar ao AutoRunner Control Plane';$dialog.StartPosition='CenterParent';$dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi;$dialog.MinimumSize=[Drawing.Size]::new(620,380);$dialog.Size=[Drawing.Size]::new(700,430);$dialog.Font=$form.Font;if($form.Icon){$dialog.Icon=$form.Icon}
        $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.Padding=New-Object Windows.Forms.Padding(22);$layout.ColumnCount=1;$layout.RowCount=8
        [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        foreach($h in @(46,28,42,28,42,38,42,52)){[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$h)))}
        $intro=New-Object Windows.Forms.Label;$intro.Text='Matricule esta instalação no servidor central. O token é de uso único e não fica salvo em texto puro.';$intro.Dock='Fill';$intro.ForeColor=$colorMuted;$intro.AutoEllipsis=$true
        $urlLabel=New-Object Windows.Forms.Label;$urlLabel.Text='URL pública do Control Plane';$urlLabel.Dock='Fill';$urlLabel.TextAlign='BottomLeft'
        $url=New-Object Windows.Forms.TextBox;$url.Dock='Fill';$url.Text='https://';$url.Font=New-Object Drawing.Font('Segoe UI',10)
        $tokenLabel=New-Object Windows.Forms.Label;$tokenLabel.Text='Token de enrollment';$tokenLabel.Dock='Fill';$tokenLabel.TextAlign='BottomLeft'
        $token=New-Object Windows.Forms.TextBox;$token.Dock='Fill';$token.UseSystemPasswordChar=$true;$token.Font=New-Object Drawing.Font('Consolas',10)
        $insecure=New-Object Windows.Forms.CheckBox;$insecure.Text='Permitir HTTP/WS sem TLS somente nesta homologação';$insecure.Dock='Fill';$insecure.ForeColor=$colorRed
        $warning=New-Object Windows.Forms.Label;$warning.Text='Produção deve usar HTTPS/WSS. Em rede de teste isolada, marque a opção acima apenas se a VM ainda não tiver certificado.';$warning.Dock='Fill';$warning.ForeColor=$colorMuted;$warning.AutoEllipsis=$true
        $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft';$buttons.WrapContents=$false
        $connect=New-ModernButton 'Conectar' 'Primary' 38;$connect.Width=130;$connect.Dock='None'
        $cancel=New-ModernButton 'Cancelar' 'Secondary' 38;$cancel.Width=110;$cancel.Dock='None';$cancel.DialogResult='Cancel'
        [void]$buttons.Controls.Add($connect);[void]$buttons.Controls.Add($cancel)
        @($intro,$urlLabel,$url,$tokenLabel,$token,$insecure,$warning,$buttons)|ForEach-Object{[void]$layout.Controls.Add($_,0,$layout.Controls.Count)}
        $dialog.Controls.Add($layout);$dialog.CancelButton=$cancel
        $connect.Add_Click({
            try{
                if([string]::IsNullOrWhiteSpace($url.Text) -or [string]::IsNullOrWhiteSpace($token.Text)){[Windows.Forms.MessageBox]::Show('Informe URL e token de enrollment.','Control Plane','OK','Warning')|Out-Null;return}
                if($insecure.Checked -and [Windows.Forms.MessageBox]::Show('HTTP/WS sem TLS permite interceptação do enrollment e dos comandos. Continuar somente porque este é um ambiente isolado de homologação?','Transporte inseguro','YesNo','Warning') -ne 'Yes'){return}
                $dialog.Enabled=$false;$code=Invoke-RemoteAgentEnrollmentCore -BaseUrl $url.Text -Token $token.Text -AllowInsecureTransport:$insecure.Checked;$dialog.Enabled=$true
                if($code -ne 0){throw "Enrollment terminou com código $code."}
                [Windows.Forms.MessageBox]::Show('Esta máquina foi conectada ao Control Plane e o agente SYSTEM foi iniciado.','Control Plane','OK','Information')|Out-Null
                $dialog.DialogResult='OK';$dialog.Close()
            }catch{$dialog.Enabled=$true;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Control Plane','OK','Error')|Out-Null}
        })
        Set-WindowOnActiveScreen -Window $dialog -PreferredWidth 700 -PreferredHeight 430 -MinimumWidth 620 -MinimumHeight 380
        [void]$dialog.ShowDialog($form);Refresh-StatusUi
    }

    function Refresh-StatusUi {
        $s=Get-CurrentStatus
        $script:guiSqlBak=$s.SqlBak
        $lines=[System.Collections.Generic.List[string]]::new()
        foreach($statusError in @($s.Installed.Errors)){ $lines.Add('Aviso: ' + $statusError) }
        if ($s.SqlBak) {
            $lines.Add('SQLBackupAndFTP: detectado e validado')
            $lines.Add("Pasta: $($s.SqlBak.InstallDir)")
            $lines.Add("Aplicativo/CLI: $($s.SqlBak.AppVersion) / $($s.SqlBak.CliVersion)")
            $lines.Add('Origem: ' + (@($s.SqlBak.DetectionSources) -join '; '))
            if($s.SqlBak.ServiceName){$lines.Add("Serviço: $($s.SqlBak.ServiceDisplayName) [$($s.SqlBak.ServiceState)]")}
        }
        else {
            $lines.Add('SQLBackupAndFTP: não detectado')
            $lines.Add('Ação: use “Localizar SQLBackupAndFTP”. A busca usa Registro, serviço, processos, App Paths, atalhos e, por último, uma busca limitada em discos locais.')
        }
        $remote=Get-RemoteAgentStatus
        $lines.Add('Central: ' + $(if($remote.IsEnrolled){('matriculada em '+$remote.BaseUrl+' | tarefa '+$remote.TaskState)}else{'não conectada'}))
        $lines.Add('Automação: ' + $(if ($s.Installed.IsComplete) {'instalada e com tarefa registrada'} elseif($s.Installed.HasConfiguration -or $s.Installed.HasTask) {'instalação incompleta, reparo disponível'} else {'não instalada'}))
        if ($s.Installed.Config) {
            $lines.Add('Jobs configurados: ' + ((@($s.Installed.Config.Jobs) | ForEach-Object { $_.Name }) -join ', '))
            $lines.Add("Boot: atraso $($s.Installed.Config.Execution.StartupDelayMinutes) min; intervalo mínimo $($s.Installed.Config.Execution.MinimumIntervalHours) h")
        }
        if ($s.Installed.State) {
            $lines.Add('Última execução: ' + $(if ($s.Installed.State.LastRunCompletedUtc) {$s.Installed.State.LastRunCompletedUtc} else {'nunca'}))
            $lines.Add('Resultado: ' + [string]$s.Installed.State.LastResult)
        }
        $statusText.Text=$lines -join [Environment]::NewLine
        $hasSqlBak=($null -ne $s.SqlBak)

        if($hasSqlBak){
            $sqlCard.Dot.ForeColor=$colorGreen
            $sqlCard.Title.Text='Detectado'
            $sqlCard.Detail.Text=if($s.SqlBak.AppVersion){'Versão '+$s.SqlBak.AppVersion+' • CLI '+$s.SqlBak.CliVersion}else{'CLI '+$s.SqlBak.CliVersion}
        }else{
            $sqlCard.Dot.ForeColor=$colorRed
            $sqlCard.Title.Text='Não localizado'
            $sqlCard.Detail.Text='Use a detecção automática ou baixe o SQLBackupAndFTP.'
        }
        if($s.Installed.IsComplete){
            $automationCard.Dot.ForeColor=$colorGreen
            $automationCard.Title.Text='Pronta'
            $automationCard.Detail.Text=(@($s.Installed.Config.Jobs).Count.ToString()+' job(s) • tarefa registrada')
        }elseif($s.Installed.HasConfiguration -or $s.Installed.HasTask){
            $automationCard.Dot.ForeColor=$colorAmber
            $automationCard.Title.Text='Reparo necessário'
            $automationCard.Detail.Text='Há configuração ou tarefa incompleta.'
        }else{
            $automationCard.Dot.ForeColor=$colorMuted
            $automationCard.Title.Text='Não instalada'
            $automationCard.Detail.Text=if($hasSqlBak){'Configure os jobs para ativar no boot.'}else{'Localize primeiro o SQLBackupAndFTP.'}
        }
        if($s.Installed.State -and $s.Installed.State.LastRunCompletedUtc){
            $lastResult=[string]$s.Installed.State.LastResult
            $lastCard.Dot.ForeColor=if($lastResult -match '(?i)success|sucesso|complete|conclu'){ $colorGreen }elseif($lastResult -match '(?i)fail|erro|falha'){ $colorRed }else{ $colorAmber }
            $lastCard.Title.Text=if([string]::IsNullOrWhiteSpace($lastResult)){'Registrada'}else{$lastResult}
            $lastCard.Detail.Text=([string]$s.Installed.State.LastRunCompletedUtc)
        }else{
            $lastCard.Dot.ForeColor=$colorMuted
            $lastCard.Title.Text='Ainda não executada'
            $lastCard.Detail.Text='Use “Testar backup agora” após configurar.'
        }
        $loadingBar.Visible=$false
        $hasAnyInstallState=($s.Installed.HasConfiguration -or $s.Installed.HasTask -or (Test-Path -LiteralPath $SupportDir -PathType Container))
        $btnConfigure.Enabled=$hasSqlBak
        $btnConfigure.Text=if(-not $hasSqlBak){'Localizar SQLBackupAndFTP'}elseif($s.Installed.IsInstalled){'Reconfigurar automação'}else{'Instalar automação'}
        $btnLocate.Enabled=$true
        $btnDownloadSql.Enabled=(-not $hasSqlBak)
        $btnDownloadSql.Text=if($hasSqlBak){'SQLBackupAndFTP detectado'}else{'Baixar SQLBackupAndFTP'}
        $btnTest.Enabled=$s.Installed.IsComplete
        $btnLast.Enabled=$s.Installed.HasConfiguration
        $btnLogs.Enabled=(Test-Path -LiteralPath (Join-Path $SupportDir 'logs'))
        $btnValidate.Enabled=$hasAnyInstallState
        $btnRepair.Enabled=$s.Installed.HasConfiguration
        $btnUninstall.Enabled=$s.Installed.HasConfiguration
        $btnApp.Enabled=($hasSqlBak -and -not [string]::IsNullOrWhiteSpace([string]$s.SqlBak.AppPath) -and (Test-Path -LiteralPath $s.SqlBak.AppPath -PathType Leaf))
        $btnOpenFolder.Enabled=$hasSqlBak
        $maintenanceAvailable=Test-AutoRunnerApplicationMaintenanceAvailable
        $btnRepairApp.Enabled=$maintenanceAvailable
        $btnUninstallApp.Enabled=$maintenanceAvailable
        $agentScriptAvailable=(-not [string]::IsNullOrWhiteSpace([string](Get-RemoteAgentScriptPath)))
        $btnConnectCentral.Enabled=($agentScriptAvailable -and -not $remote.IsEnrolled)
        $btnDisconnectCentral.Enabled=($agentScriptAvailable -and ($remote.IsEnrolled -or $remote.HasTask))
        $btnConnectCentral.Text=if($remote.IsEnrolled){'Central conectada'}else{'Conectar à Central'}
    }

    function Open-SqlBackupAndFTPDownload {
        $url=Get-SqlBackupAndFTPDownloadUrl
        $answer=[Windows.Forms.MessageBox]::Show(
            "O SQLBackupAndFTP não foi localizado.`r`n`r`nDeseja abrir o download oficial da versão mais recente? O navegador iniciará o download pelo site oficial.`r`n`r`n$url",
            'Baixar SQLBackupAndFTP',
            'YesNo',
            'Information'
        )
        if($answer -eq 'Yes'){
            try{Start-Process $url}
            catch{[Windows.Forms.MessageBox]::Show(('Não foi possível abrir o navegador.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message),'SQLBackupAndFTP','OK','Error')|Out-Null}
        }
    }

    $script:UpdateCheckProcess=$null
    $script:UpdateCheckOutput=''
    $script:UpdateCheckManual=$false
    $updatePollTimer=New-Object Windows.Forms.Timer
    $updatePollTimer.Interval=450

    function Start-AutoRunnerUpdateInstall([string]$Tag){
        if([string]::IsNullOrWhiteSpace($Tag)){return}
        $updater=Get-ChildScriptPath 'Update-AutoRunner.ps1'
        if(-not(Test-Path -LiteralPath $updater -PathType Leaf)){throw 'Updater integrado não encontrado. Use Reparar aplicativo.'}
        $ps=Get-AutoRunnerWindowsPowerShellPath
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$updater,'-Tag',$Tag)
        $line=Join-AutoRunnerProcessArguments -Arguments $args
        [void](Start-Process -FilePath $ps -ArgumentList $line -Verb RunAs -PassThru)
        $form.Close()
    }

    function Show-AutoRunnerUpdateResult($result,[bool]$Manual){
        if(-not $result.Success){
            if($Manual){[Windows.Forms.MessageBox]::Show(('Não foi possível verificar atualizações agora.'+[Environment]::NewLine+[Environment]::NewLine+[string]$result.Error),'Atualizações','OK','Warning')|Out-Null}
            else{Write-ManagerLog ('Verificação automática de atualização falhou: '+[string]$result.Error) 'WARN'}
            return
        }
        if(-not [bool]$result.IsUpdateAvailable){
            if($Manual){[Windows.Forms.MessageBox]::Show(('Você já está na versão mais recente disponível para este canal: '+[string]$result.Current+'.'),'Atualizações','OK','Information')|Out-Null}
            return
        }
        $settings=Get-AutoRunnerUserSettings
        if(-not $Manual -and [string]$settings.SkippedUpdateTag -eq [string]$result.Tag){return}
        $message="Nova versão disponível: $($result.DisplayVersion)`r`nAtual: $($result.Current)`r`n`r`nDeseja baixar e iniciar a atualização agora?`r`n`r`nSim = atualizar agora`r`nNão = lembrar depois`r`nCancelar = ignorar esta versão"
        $answer=[Windows.Forms.MessageBox]::Show($message,'Atualização do AutoRunner','YesNoCancel','Information')
        if($answer -eq 'Yes'){
            try{
                Set-AutoRunnerUserSettings -SkippedUpdateTag ''
                Start-AutoRunnerUpdateInstall -Tag ([string]$result.Tag)
            }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Atualização','OK','Error')|Out-Null}
        }elseif($answer -eq 'Cancel'){
            Set-AutoRunnerUserSettings -SkippedUpdateTag ([string]$result.Tag)
        }
    }

    function Start-AutoRunnerUpdateCheck([bool]$Manual){
        if($script:UpdateCheckProcess -and -not $script:UpdateCheckProcess.HasExited){
            if($Manual){[Windows.Forms.MessageBox]::Show('Já existe uma verificação de atualização em andamento.','Atualizações','OK','Information')|Out-Null}
            return
        }
        if(-not $Manual -and -not(Test-AutoRunnerShouldCheckUpdates)){return}
        $checker=Get-ChildScriptPath 'Check-Updates.ps1'
        if(-not(Test-Path -LiteralPath $checker -PathType Leaf)){
            if($Manual){[Windows.Forms.MessageBox]::Show('Componente de atualização ausente. Use Reparar aplicativo.','Atualizações','OK','Error')|Out-Null}
            return
        }
        $output=Join-Path $env:TEMP ('SQLBackupAndFTPAuto-update-'+$PID+'-'+[Guid]::NewGuid().ToString('N')+'.json')
        $ps=Get-AutoRunnerWindowsPowerShellPath
        $args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$checker,'-OutputPath',$output)
        if((Get-AutoRunnerReleaseChannel) -ne 'Stable'){$args+='-IncludePrerelease'}
        $line=Join-AutoRunnerProcessArguments -Arguments $args
        try{
            $script:UpdateCheckManual=$Manual
            $script:UpdateCheckOutput=$output
            $script:UpdateCheckProcess=Start-Process -FilePath $ps -ArgumentList $line -WindowStyle Hidden -PassThru
            $btnUpdates.Enabled=$false;$btnUpdates.Text='Verificando...'
            $updatePollTimer.Start()
        }catch{
            $btnUpdates.Enabled=$true;$btnUpdates.Text='Verificar atualizações'
            if($Manual){[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Atualizações','OK','Error')|Out-Null}
        }
    }

    $updatePollTimer.Add_Tick({
        try{
            $ready=(Test-Path -LiteralPath $script:UpdateCheckOutput -PathType Leaf)
            $finished=($script:UpdateCheckProcess -and $script:UpdateCheckProcess.HasExited)
            if(-not $ready -and -not $finished){return}
            $updatePollTimer.Stop()
            $btnUpdates.Enabled=$true;$btnUpdates.Text='Verificar atualizações'
            if($ready){
                $result=Read-AutoRunnerJson -Path $script:UpdateCheckOutput
                Show-AutoRunnerUpdateResult -result $result -Manual ([bool]$script:UpdateCheckManual)
            }elseif($script:UpdateCheckManual){
                [Windows.Forms.MessageBox]::Show('A verificação terminou sem produzir resultado. Consulte manager.log.','Atualizações','OK','Warning')|Out-Null
            }
        }catch{
            Write-ManagerLog ('Falha ao processar resultado de atualização: '+$_.Exception.Message) 'WARN'
            if($script:UpdateCheckManual){[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Atualizações','OK','Error')|Out-Null}
        }finally{
            if($script:UpdateCheckOutput){Remove-Item -LiteralPath $script:UpdateCheckOutput -Force -ErrorAction SilentlyContinue}
            if($script:UpdateCheckProcess){try{$script:UpdateCheckProcess.Dispose()}catch{}}
            $script:UpdateCheckProcess=$null;$script:UpdateCheckOutput='';$script:UpdateCheckManual=$false
        }
    })

    function Show-ConfigurationDialog {
        try {
            $install=Get-SqlBackupAndFTPInstall -AllowNotFound
            if(-not $install){Show-SqlBackupLocationDialog; $install=Get-SqlBackupAndFTPInstall -AllowNotFound; if(-not $install){return}}
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message,'SQLBackupAndFTP não localizado','OK','Error') | Out-Null
            return
        }

        $discovery=Get-SqlBakJobs -InstallInfo $install
        $installed=Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
        $existing=$installed.Config
        if ($existing) { $existing = ConvertTo-AutoRunnerCurrentConfig -Config $existing -InstallInfo $install }
        $defaults=New-AutoRunnerDefaultConfig -InstallInfo $install -Jobs @()
        $userSettings=Get-AutoRunnerUserSettings
        $useAdvanced=[bool]$userSettings.UseAdvancedSettings

        $dialog=New-Object Windows.Forms.Form
        $dialog.Text='Configurar SQLBackupAndFTP AutoRunner'
        $dialog.Size=[Drawing.Size]::new(980,720)
        $dialog.MinimumSize=[Drawing.Size]::new(760,560)
        $dialog.StartPosition='CenterParent'
        $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
        $dialog.AutoScroll=$true
        $dialog.Font=$form.Font
        $dialog.BackColor=[Drawing.Color]::FromArgb(246,248,252)
        if ($form.Icon) { $dialog.Icon = $form.Icon }

        # O layout usa um conteúdo vertical com altura mínima. Em janelas menores
        # o Form fornece scroll; em janelas maiores o grid ganha o espaço extra.
        # Isso evita achatar botões/tabs em 125-200% de DPI ou ao maximizar.
        $root=New-Object Windows.Forms.TableLayoutPanel
        $root.Dock='Top';$root.ColumnCount=1;$root.RowCount=6;$root.Padding=New-Object Windows.Forms.Padding(16);$root.Margin=0
        [void]$root.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,0)))
        [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,54)))
        $dialog.Controls.Add($root)

        $info=New-Object Windows.Forms.Label
        $warningText=if(@($discovery.Errors).Count -gt 0){'  Avisos de descoberta: '+($discovery.Errors -join ' | ')}else{''}
        $info.Text='Marque os jobs que deseja executar automaticamente quando o Windows iniciar. Nenhuma configuração do SQLBackupAndFTP será alterada.'+$warningText
        $info.AutoSize=$true;$info.Dock='Fill';$info.MaximumSize=[Drawing.Size]::new(0,72);$info.ForeColor=$colorMuted;$info.Margin=New-Object Windows.Forms.Padding(2,0,2,10)
        [void]$root.Controls.Add($info,0,0)

        $grid=New-Object Windows.Forms.DataGridView
        $grid.Dock='Fill';$grid.Margin=New-Object Windows.Forms.Padding(0,0,0,8);$grid.MinimumSize=[Drawing.Size]::new(0,220)
        $grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToResizeRows=$false
        $grid.AutoSizeColumnsMode='Fill';$grid.SelectionMode='FullRowSelect';$grid.RowHeadersVisible=$false;$grid.MultiSelect=$false
        $grid.BackgroundColor=[Drawing.Color]::White;$grid.BorderStyle='FixedSingle';$grid.ColumnHeadersHeightSizeMode='AutoSize'
        $selectColumn=New-Object Windows.Forms.DataGridViewCheckBoxColumn
        $selectColumn.Name='Selected';$selectColumn.HeaderText='Executar';$selectColumn.FillWeight=45
        [void]$grid.Columns.Add($selectColumn)
        [void]$grid.Columns.Add('Name','Nome do job')
        [void]$grid.Columns.Add('Status','Situação')
        [void]$grid.Columns.Add('Type','Tipo')
        [void]$grid.Columns.Add('Scheduled','Agendado')
        [void]$grid.Columns.Add('LastRun','Última execução')
        [void]$grid.Columns.Add('Source','Origem')
        $backupColumn=New-Object Windows.Forms.DataGridViewComboBoxColumn
        $backupColumn.Name='BackupType';$backupColumn.HeaderText='Tipo de backup';$backupColumn.FlatStyle='Flat'
        foreach($backupOption in @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')){[void]$backupColumn.Items.Add($backupOption)}
        [void]$grid.Columns.Add($backupColumn)
        $grid.Columns['Name'].FillWeight=210;$grid.Columns['Status'].FillWeight=110;$grid.Columns['Source'].FillWeight=100;$grid.Columns['BackupType'].FillWeight=90
        [void]$root.Controls.Add($grid,0,1)

        $existingNames=@{}
        if ($existing) { foreach($j in @($existing.Jobs)){$existingNames[[string]$j.Name]=$j} }

        function Add-AutoRunnerJobGridRow {
            param($Job,[bool]$Selected,[string]$BackupType='Default',[switch]$ConfiguredMissing)
            $index=$grid.Rows.Add()
            $row=$grid.Rows[$index]
            $row.Cells['Selected'].Value=$Selected
            $row.Cells['Name'].Value=[string]$Job.Name
            $isKnownNonBackup=($Job.IsBackup -eq $false)
            $status=if($ConfiguredMissing){'Configurado, não localizado'}elseif($isKnownNonBackup){'Não é job de backup'}elseif($Job.IsScheduled -eq $true){'Backup agendado'}elseif($Job.IsScheduled -eq $false){'Backup não agendado'}elseif([string]$Job.Source -eq 'CliListJobsUndocumented'){'Encontrado pela CLI'}else{'Disponível'}
            $row.Cells['Status'].Value=$status
            $row.Cells['Type'].Value=[string]$Job.Type
            $row.Cells['Scheduled'].Value=$(if($null -eq $Job.IsScheduled){'Desconhecido'}elseif($Job.IsScheduled){'Sim'}else{'Não'})
            $row.Cells['LastRun'].Value=[string]$Job.LastRunAt
            $row.Cells['Source'].Value=[string]$Job.Source
            $row.Cells['BackupType'].Value=if([string]::IsNullOrWhiteSpace($BackupType)){'Default'}else{$BackupType}
            $row.Tag=$Job
            if($isKnownNonBackup){
                $row.Cells['Selected'].ReadOnly=$true;$row.Cells['Selected'].Value=$false;$row.DefaultCellStyle.ForeColor=[Drawing.Color]::Gray
            }elseif($ConfiguredMissing){
                $row.DefaultCellStyle.BackColor=[Drawing.Color]::MistyRose
            }elseif([string]$Job.Confidence -ne 'High'){
                $row.DefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(255,250,225)
            }
            return $row
        }

        foreach($job in @($discovery.Jobs)) {
            $selected=$false;$backupType='Default'
            if($existingNames.ContainsKey([string]$job.Name)){$selected=$true;if($existingNames[[string]$job.Name].BackupType){$backupType=[string]$existingNames[[string]$job.Name].BackupType}}
            [void](Add-AutoRunnerJobGridRow -Job $job -Selected $selected -BackupType $backupType)
        }
        $discoveredNameSet=@{};foreach($discoveredJob in @($discovery.Jobs)){$discoveredNameSet[[string]$discoveredJob.Name]=$true}
        if($existing){
            foreach($existingJob in @($existing.Jobs)){
                $existingName=[string]$existingJob.Name
                if([string]::IsNullOrWhiteSpace($existingName) -or $discoveredNameSet.ContainsKey($existingName)){continue}
                $missing=[pscustomobject]@{Name=$existingName;Type='Desconhecido';IsBackup=$null;IsScheduled=$null;LastRunAt=[string]$existingJob.LastRunAt;Confidence='Low';Source='ConfiguredMissing'}
                [void](Add-AutoRunnerJobGridRow -Job $missing -Selected $true -BackupType $(if($existingJob.BackupType){[string]$existingJob.BackupType}else{'Default'}) -ConfiguredMissing)
            }
        }

        $simpleBar=New-Object Windows.Forms.TableLayoutPanel
        $simpleBar.Dock='Fill';$simpleBar.AutoSize=$true;$simpleBar.ColumnCount=4;$simpleBar.RowCount=1;$simpleBar.Margin=New-Object Windows.Forms.Padding(0,0,0,8)
        [void]$simpleBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$simpleBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::AutoSize)))
        [void]$simpleBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$simpleBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::AutoSize)))
        $btnSelectAll=New-ModernButton 'Marcar todos' 'Secondary' 36;$btnSelectAll.Dock='None';$btnSelectAll.Width=120;$btnSelectAll.Margin=New-Object Windows.Forms.Padding(0,0,8,0)
        $btnClearJobs=New-ModernButton 'Desmarcar todos' 'Secondary' 36;$btnClearJobs.Dock='None';$btnClearJobs.Width=130;$btnClearJobs.Margin=0
        $simpleHint=New-Object Windows.Forms.Label;$simpleHint.Text='Modo simples: executa os jobs marcados em cada inicialização, sem retentativas automáticas e usando o tipo Default do SQLBackupAndFTP.';$simpleHint.Dock='Fill';$simpleHint.ForeColor=$colorMuted;$simpleHint.TextAlign='MiddleLeft';$simpleHint.AutoEllipsis=$true;$simpleHint.Margin=New-Object Windows.Forms.Padding(12,0,8,0)
        [void]$simpleBar.Controls.Add($btnSelectAll,0,0);[void]$simpleBar.Controls.Add($btnClearJobs,1,0);[void]$simpleBar.Controls.Add($simpleHint,2,0)
        [void]$root.Controls.Add($simpleBar,0,2)
        $btnSelectAll.Add_Click({foreach($row in $grid.Rows){if(-not $row.Cells['Selected'].ReadOnly){$row.Cells['Selected'].Value=$true}}})
        $btnClearJobs.Add_Click({foreach($row in $grid.Rows){if(-not $row.Cells['Selected'].ReadOnly){$row.Cells['Selected'].Value=$false}}})

        $advancedToggle=New-Object Windows.Forms.CheckBox
        $advancedToggle.Text='Usar configurações avançadas';$advancedToggle.AutoSize=$true;$advancedToggle.Checked=$useAdvanced;$advancedToggle.Font=New-Object Drawing.Font('Segoe UI Semibold',9.5);$advancedToggle.Margin=New-Object Windows.Forms.Padding(2,2,0,8)
        [void]$root.Controls.Add($advancedToggle,0,3)

        $advancedPanel=New-Object Windows.Forms.TableLayoutPanel
        $advancedPanel.Dock='Fill';$advancedPanel.ColumnCount=1;$advancedPanel.RowCount=2;$advancedPanel.Margin=0;$advancedPanel.Padding=0
        [void]$advancedPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,44)))
        [void]$advancedPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
        $manualBar=New-Object Windows.Forms.TableLayoutPanel;$manualBar.Dock='Fill';$manualBar.ColumnCount=3;$manualBar.RowCount=1;$manualBar.Margin=0
        [void]$manualBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,120)))
        [void]$manualBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
        [void]$manualBar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,110)))
        $manualLabel=New-Object Windows.Forms.Label;$manualLabel.Text='Job por nome:';$manualLabel.Dock='Fill';$manualLabel.TextAlign='MiddleLeft'
        $manualText=New-Object Windows.Forms.TextBox;$manualText.Dock='Fill';$manualText.Margin=New-Object Windows.Forms.Padding(0,6,8,6)
        $manualAdd=New-ModernButton 'Adicionar' 'Secondary' 34;$manualAdd.Margin=New-Object Windows.Forms.Padding(0,4,0,4)
        [void]$manualBar.Controls.Add($manualLabel,0,0);[void]$manualBar.Controls.Add($manualText,1,0);[void]$manualBar.Controls.Add($manualAdd,2,0)
        [void]$advancedPanel.Controls.Add($manualBar,0,0)

        $settingsTabs=New-Object Windows.Forms.TabControl;$settingsTabs.Dock='Fill';$settingsTabs.Margin=0
        $settings=New-Object Windows.Forms.TabPage;$settings.Text='Execução e resiliência';$settings.AutoScroll=$true
        $loggingGroup=New-Object Windows.Forms.TabPage;$loggingGroup.Text='Logs';$loggingGroup.AutoScroll=$true
        [void]$settingsTabs.TabPages.Add($settings);[void]$settingsTabs.TabPages.Add($loggingGroup)
        [void]$advancedPanel.Controls.Add($settingsTabs,0,1)
        [void]$root.Controls.Add($advancedPanel,0,4)

        $executionGrid=New-Object Windows.Forms.TableLayoutPanel
        $executionGrid.Dock='Top';$executionGrid.AutoSize=$true;$executionGrid.ColumnCount=4;$executionGrid.RowCount=7;$executionGrid.Padding=New-Object Windows.Forms.Padding(10);$executionGrid.Margin=0
        [void]$executionGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,31)))
        [void]$executionGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,19)))
        [void]$executionGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,31)))
        [void]$executionGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,19)))
        1..7|ForEach-Object{[void]$executionGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,34)))}
        $settings.Controls.Add($executionGrid)

        function Add-AdvancedNumeric([string]$Label,[int]$Row,[int]$Pair,[int]$Min,[int]$Max,[int]$Value){
            $baseCol=$Pair*2
            $l=New-Object Windows.Forms.Label;$l.Text=$Label;$l.Dock='Fill';$l.TextAlign='MiddleLeft';$l.AutoEllipsis=$true
            $n=New-Object Windows.Forms.NumericUpDown;$n.Dock='Fill';$n.Minimum=$Min;$n.Maximum=$Max;$n.Value=[Math]::Min($Max,[Math]::Max($Min,$Value));$n.Margin=New-Object Windows.Forms.Padding(4,4,10,4)
            [void]$executionGrid.Controls.Add($l,$baseCol,$Row);[void]$executionGrid.Controls.Add($n,$baseCol+1,$Row)
            return $n
        }
        $execSource=if($existing){$existing.Execution}else{$defaults.Execution}
        $numDelay=Add-AdvancedNumeric 'Atraso após boot (min)' 0 0 0 120 ([int]$execSource.StartupDelayMinutes)
        $numInterval=Add-AdvancedNumeric 'Intervalo mínimo por job (h)' 0 1 0 720 ([int]$execSource.MinimumIntervalHours)
        $numRetries=Add-AdvancedNumeric 'Novas tentativas' 1 0 0 10 ([int]$execSource.RetryCount)
        $numRetryDelay=Add-AdvancedNumeric 'Espera entre tentativas (min)' 1 1 0 60 ([int]$execSource.RetryDelayMinutes)
        $numService=Add-AdvancedNumeric 'Espera serviço SQLBak (seg)' 2 0 0 1800 ([int]$execSource.ServiceWaitSeconds)
        $numSqlService=Add-AdvancedNumeric 'Espera SQL Server (seg)' 2 1 0 1800 ([int]$execSource.SqlServiceWaitSeconds)
        $numPostDelay=Add-AdvancedNumeric 'Espera entre jobs (seg)' 3 0 0 600 ([int]$execSource.PostJobDelaySeconds)
        $numLimit=Add-AdvancedNumeric 'Limite da tarefa (h)' 3 1 1 168 ([int]$execSource.ExecutionTimeLimitHours)
        $numRestartCount=Add-AdvancedNumeric 'Reinícios da tarefa' 4 0 1 10 ([int]$execSource.TaskRestartCount)
        $numRestartInterval=Add-AdvancedNumeric 'Intervalo de reinício (min)' 4 1 1 1440 ([int]$execSource.TaskRestartIntervalMinutes)
        $sqlModeLabel=New-Object Windows.Forms.Label;$sqlModeLabel.Text='Espera SQL local';$sqlModeLabel.Dock='Fill';$sqlModeLabel.TextAlign='MiddleLeft'
        $sqlModeCombo=New-Object Windows.Forms.ComboBox;$sqlModeCombo.Dock='Fill';$sqlModeCombo.DropDownStyle='DropDownList';$sqlModeCombo.Margin=New-Object Windows.Forms.Padding(4,4,10,4)
        foreach($m in @('None','AnyAutomaticLocal','AllAutomaticLocal')){[void]$sqlModeCombo.Items.Add($m)}
        $sqlModeCombo.SelectedItem=[string]$execSource.SqlServiceWaitMode;if($sqlModeCombo.SelectedIndex -lt 0){$sqlModeCombo.SelectedItem='AnyAutomaticLocal'}
        [void]$executionGrid.Controls.Add($sqlModeLabel,0,5);[void]$executionGrid.Controls.Add($sqlModeCombo,1,5)
        $chkRetryCli=New-Object Windows.Forms.CheckBox;$chkRetryCli.Text='Repetir após erro da CLI';$chkRetryCli.Dock='Fill';$chkRetryCli.Checked=ConvertTo-AutoRunnerBoolean -Value $execSource.RetryOnCliError -Default $false
        [void]$executionGrid.Controls.Add($chkRetryCli,2,5);$executionGrid.SetColumnSpan($chkRetryCli,2)
        $chkStop=New-Object Windows.Forms.CheckBox;$chkStop.Text='Parar após a primeira falha';$chkStop.Dock='Fill';$chkStop.Checked=[bool]$execSource.StopOnFirstFailure
        $chkTaskRestart=New-Object Windows.Forms.CheckBox;$chkTaskRestart.Text='Agendador reinicia a tarefa após falha';$chkTaskRestart.Dock='Fill';$chkTaskRestart.Checked=[bool]$execSource.TaskRestartOnFailure
        [void]$executionGrid.Controls.Add($chkStop,0,6);$executionGrid.SetColumnSpan($chkStop,2);[void]$executionGrid.Controls.Add($chkTaskRestart,2,6);$executionGrid.SetColumnSpan($chkTaskRestart,2)

        $logGrid=New-Object Windows.Forms.TableLayoutPanel;$logGrid.Dock='Top';$logGrid.AutoSize=$true;$logGrid.ColumnCount=6;$logGrid.RowCount=2;$logGrid.Padding=New-Object Windows.Forms.Padding(10)
        foreach($pct in @(22,11,22,11,22,12)){[void]$logGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,$pct)))}
        1..2|ForEach-Object{[void]$logGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,38)))}
        $loggingGroup.Controls.Add($logGrid)
        $logSource=if($existing){$existing.Logging}else{$defaults.Logging}
        function Add-LogNumeric([string]$Label,[int]$Pair,[int]$Min,[int]$Max,[int]$Value){
            $c=$Pair*2;$l=New-Object Windows.Forms.Label;$l.Text=$Label;$l.Dock='Fill';$l.TextAlign='MiddleLeft';$l.AutoEllipsis=$true
            $n=New-Object Windows.Forms.NumericUpDown;$n.Dock='Fill';$n.Minimum=$Min;$n.Maximum=$Max;$n.Value=[Math]::Min($Max,[Math]::Max($Min,$Value));$n.Margin=New-Object Windows.Forms.Padding(4)
            [void]$logGrid.Controls.Add($l,$c,0);[void]$logGrid.Controls.Add($n,$c+1,0);return $n
        }
        $numLogMax=Add-LogNumeric 'Tamanho por log (MB)' 0 1 1024 ([int]$logSource.MaxSizeMB)
        $numLogKeep=Add-LogNumeric 'Arquivos mantidos' 1 1 50 ([int]$logSource.KeepFiles)
        $numLogRetention=Add-LogNumeric 'Retenção (dias)' 2 1 3650 ([int]$logSource.RetentionDays)
        $logHint=New-Object Windows.Forms.Label;$logHint.Text='Esses valores só controlam os logs do AutoRunner; não alteram retenção ou destino dos backups.';$logHint.Dock='Fill';$logHint.ForeColor=$colorMuted;$logHint.TextAlign='MiddleLeft';$logHint.AutoEllipsis=$true
        [void]$logGrid.Controls.Add($logHint,0,1);$logGrid.SetColumnSpan($logHint,6)

        $manualAdd.Add_Click({
            if([string]::IsNullOrWhiteSpace($manualText.Text)){return}
            $manualName=$manualText.Text.Trim();$exists=$false
            foreach($r in $grid.Rows){if(([string]$r.Cells['Name'].Value).Trim() -ieq $manualName){$exists=$true;break}}
            if($exists){[Windows.Forms.MessageBox]::Show('Este job já está na lista.','Validação','OK','Warning')|Out-Null;return}
            $manualJob=[pscustomobject]@{Name=$manualName;Type='Desconhecido';IsBackup=$null;IsScheduled=$null;LastRunAt='';Confidence='Low';Source='Manual'}
            [void](Add-AutoRunnerJobGridRow -Job $manualJob -Selected $true -BackupType 'Default')
            $manualText.Clear()
        })

        $buttonPanel=New-Object Windows.Forms.FlowLayoutPanel;$buttonPanel.Dock='Fill';$buttonPanel.FlowDirection='RightToLeft';$buttonPanel.WrapContents=$false;$buttonPanel.Margin=0;$buttonPanel.Padding=New-Object Windows.Forms.Padding(0,8,0,0)
        $save=New-ModernButton 'Salvar configuração' 'Primary' 38;$save.Dock='None';$save.Width=165
        $cancel=New-ModernButton 'Cancelar' 'Secondary' 38;$cancel.Dock='None';$cancel.Width=100;$cancel.DialogResult='Cancel'
        [void]$buttonPanel.Controls.Add($save);[void]$buttonPanel.Controls.Add($cancel);[void]$root.Controls.Add($buttonPanel,0,5);$dialog.CancelButton=$cancel

        $applyAdvancedUi={
            $enabled=[bool]$advancedToggle.Checked
            $dpiScale=1.0
            try{if($dialog.DeviceDpi -gt 96){$dpiScale=[double]$dialog.DeviceDpi/96.0}}catch{}
            $advancedPanel.Visible=$enabled
            $root.RowStyles[4].Height=if($enabled){[int][Math]::Ceiling(300*$dpiScale)}else{0}
            foreach($columnName in @('Type','Scheduled','LastRun','Source','BackupType')){$grid.Columns[$columnName].Visible=$enabled}
            $baseHeight=if($enabled){760}else{590}
            $minHeight=[int][Math]::Ceiling($baseHeight*$dpiScale)
            $root.Height=[Math]::Max($minHeight,$dialog.ClientSize.Height-4)
            if($enabled -and $dialog.Height -lt [int][Math]::Ceiling(760*$dpiScale)){
                $target=[int][Math]::Ceiling(800*$dpiScale)
                $dialog.Height=[Math]::Min($target,[Windows.Forms.Screen]::FromControl($dialog).WorkingArea.Height-24)
            }
        }
        $advancedToggle.Add_CheckedChanged({& $applyAdvancedUi})
        $dialog.Add_Resize({& $applyAdvancedUi})

        $save.Add_Click({
            try {
                $chosen=[System.Collections.Generic.List[object]]::new()
                $needsTechnicalConfirmation=[System.Collections.Generic.List[string]]::new()
                foreach($row in $grid.Rows){
                    if(-not [bool]$row.Cells['Selected'].Value){continue}
                    $name=([string]$row.Cells['Name'].Value).Trim();if([string]::IsNullOrWhiteSpace($name)){continue}
                    $job=$row.Tag;$confidence=if($job){[string]$job.Confidence}else{'Low'}
                    if($row.Cells['Scheduled'].Value -ne 'Sim' -or $row.Cells['Source'].Value -eq 'Manual' -or $confidence -ne 'High'){
                        [void]$needsTechnicalConfirmation.Add($name)
                    }
                    $backupType=if($advancedToggle.Checked){[string]$row.Cells['BackupType'].Value}else{'Default'}
                    if([string]::IsNullOrWhiteSpace($backupType)){$backupType='Default'}
                    [void]$chosen.Add([pscustomobject][ordered]@{
                        Name=$name
                        Type=[string]$row.Cells['Type'].Value
                        IsScheduled=if($row.Cells['Scheduled'].Value -eq 'Sim'){$true}elseif($row.Cells['Scheduled'].Value -eq 'Não'){$false}else{$null}
                        LastRunAt=[string]$row.Cells['LastRun'].Value
                        Source=[string]$row.Cells['Source'].Value
                        BackupType=$backupType
                        ConfirmedByTechnician=$true
                        ConfirmedAtUtc=[DateTime]::UtcNow.ToString('o')
                        ConfirmedBy=[Security.Principal.WindowsIdentity]::GetCurrent().Name
                        ConfirmationReason=$(if($advancedToggle.Checked){'Selecionado explicitamente com configurações avançadas'}else{'Selecionado explicitamente no modo simples'})
                    })
                }
                if($chosen.Count -eq 0){[Windows.Forms.MessageBox]::Show('Selecione ao menos um job para executar no boot.','Validação','OK','Warning')|Out-Null;return}
                if($needsTechnicalConfirmation.Count -gt 0){
                    $names=($needsTechnicalConfirmation.ToArray() | Select-Object -First 8) -join ', '
                    $extra=if($needsTechnicalConfirmation.Count -gt 8){" e mais $($needsTechnicalConfirmation.Count-8)"}else{''}
                    $message="Alguns itens selecionados não puderam ser confirmados como backups agendados pela descoberta local: $names$extra.`r`n`r`nO AutoRunner apenas chamará os nomes que você marcou e não alterará os jobs no SQLBackupAndFTP. Deseja continuar?"
                    if([Windows.Forms.MessageBox]::Show($message,'Confirmar jobs selecionados','YesNo','Warning') -ne 'Yes'){return}
                }

                if($advancedToggle.Checked){
                    if([int]$numRetries.Value -gt 0 -and $chkRetryCli.Checked){
                        if([Windows.Forms.MessageBox]::Show('Repetir após erro da CLI pode disparar o mesmo job novamente se a primeira chamada tiver sido aceita parcialmente. Continuar?','Configuração avançada','YesNo','Warning') -ne 'Yes'){return}
                    }
                    if($chkTaskRestart.Checked -and [int]$numInterval.Value -eq 0){
                        $risk='Risco de repetição: reiniciar a tarefa com intervalo mínimo 0 pode executar novamente jobs que já terminaram antes de uma falha posterior. Confirma esta combinação de risco?'
                        if([Windows.Forms.MessageBox]::Show($risk,'Risco de repetição','YesNo','Warning') -ne 'Yes'){return}
                    }
                    $execution=[pscustomobject][ordered]@{
                        StartupDelayMinutes=[int]$numDelay.Value;MinimumIntervalHours=[int]$numInterval.Value;RetryCount=[int]$numRetries.Value;RetryDelayMinutes=[int]$numRetryDelay.Value
                        RetryOnCliError=[bool]$chkRetryCli.Checked;ServiceWaitSeconds=[int]$numService.Value;SqlServiceWaitSeconds=[int]$numSqlService.Value;SqlServiceWaitMode=[string]$sqlModeCombo.SelectedItem
                        ExecutionTimeLimitHours=[int]$numLimit.Value;PostJobDelaySeconds=[int]$numPostDelay.Value;StopOnFirstFailure=[bool]$chkStop.Checked;TaskRestartOnFailure=[bool]$chkTaskRestart.Checked
                        TaskRestartCount=[int]$numRestartCount.Value;TaskRestartIntervalMinutes=[int]$numRestartInterval.Value
                    }
                    $logging=[pscustomobject][ordered]@{MaxSizeMB=[int]$numLogMax.Value;KeepFiles=[int]$numLogKeep.Value;RetentionDays=[int]$numLogRetention.Value}
                }else{
                    # Modo simples: comportamento previsível, sem retries e sem
                    # knobs técnicos. Os defaults são os mesmos validados pelo
                    # instalador/runner e não dependem do estado da interface.
                    $execution=$defaults.Execution | Select-Object *
                    # No modo simples, cada boot representa uma execução nova.
                    # O intervalo anti-repetição é um ajuste avançado e não deve
                    # fazer uma reinicialização legítima parecer uma falha.
                    $execution.MinimumIntervalHours=0
                    $execution.RetryCount=0
                    $execution.RetryOnCliError=$false
                    $execution.TaskRestartOnFailure=$false
                    $logging=$defaults.Logging | Select-Object *
                }

                Set-AutoRunnerUserSettings -UseAdvancedSettings ([bool]$advancedToggle.Checked)
                $request=New-InstallRequest -Jobs $chosen.ToArray() -Execution $execution -Logging $logging
                $mode=if($installed.IsInstalled){'Reconfigure'}else{'Install'}
                $dialog.Enabled=$false;$code=Invoke-InstallerRequest -Mode $mode -Request $request;$dialog.Enabled=$true
                if($code -eq 0){
                    [Windows.Forms.MessageBox]::Show('Configuração aplicada com sucesso. Use “Testar backup agora” e confirme o resultado no histórico/destino.','AutoRunner','OK','Information')|Out-Null
                    $dialog.DialogResult='OK';$dialog.Close()
                }else{
                    [Windows.Forms.MessageBox]::Show("A operação falhou (código $code). Consulte install.log.",'AutoRunner','OK','Error')|Out-Null
                }
            }catch{
                $dialog.Enabled=$true
                [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null
            }
        })

        Set-WindowOnActiveScreen -Window $dialog -PreferredWidth 980 -PreferredHeight $(if($useAdvanced){780}else{650}) -MinimumWidth 760 -MinimumHeight 560
        & $applyAdvancedUi
        [void]$dialog.ShowDialog($form)
        Refresh-StatusUi
    }

    $btnConfigure.Add_Click({if($script:guiSqlBak){Show-ConfigurationDialog}else{Show-SqlBackupLocationDialog}})
    $btnLocate.Add_Click({Show-SqlBackupLocationDialog})
    $btnDownloadSql.Add_Click({Open-SqlBackupAndFTPDownload})
    $btnUpdates.Add_Click({Start-AutoRunnerUpdateCheck $true})
    $btnTest.Add_Click({try{$form.Enabled=$false;$code=Invoke-TestNow;$form.Enabled=$true;[Windows.Forms.MessageBox]::Show("Teste finalizado com código $code. Consulte o histórico do SQLBackupAndFTP e runner.log.",'Teste','OK',$(if($code -eq 0){'Information'}else{'Warning'}))|Out-Null;Refresh-StatusUi}catch{$form.Enabled=$true;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null}})
    $btnLast.Add_Click({$s=Get-AutoRunnerInstalledState -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath;if($s.State){$jobLines=@($s.State.Jobs|ForEach-Object{"$($_.Name): $($_.Result) | código $($_.ExitCode) | tentativas $($_.Attempts)"});$message="Início: $($s.State.LastRunStartedUtc)`r`nFim: $($s.State.LastRunCompletedUtc)`r`nGatilho: $($s.State.LastTrigger)`r`nResultado: $($s.State.LastResult)`r`nCódigo: $($s.State.LastExitCode)`r`n`r`n"+($jobLines -join "`r`n");[Windows.Forms.MessageBox]::Show($message,'Última execução','OK','Information')|Out-Null}})
    $btnLogs.Add_Click({$dir=Join-Path $SupportDir 'logs';if(Test-Path -LiteralPath $dir){Start-Process explorer.exe -ArgumentList (ConvertTo-AutoRunnerProcessArgument -Value $dir)}})
    $btnValidate.Add_Click({try{$result=Invoke-ValidateCore;$failed=@($result.Validation.Checks|Where-Object{-not $_.Ok});$detail=if($failed.Count -eq 0){'Todos os controles disponíveis foram aprovados.'}else{($failed|ForEach-Object{"$($_.Name): $($_.Detail)"}) -join "`r`n"};[Windows.Forms.MessageBox]::Show($detail,'Validação da instalação','OK',$(if($failed.Count -eq 0){'Information'}else{'Warning'}))|Out-Null;Refresh-StatusUi}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null}})
    $btnRepair.Add_Click({$answer=[Windows.Forms.MessageBox]::Show('O reparo preserva jobs e configurações e recria arquivos, ACL e tarefa. Continuar?','Reparar','YesNo','Question');if($answer -eq 'Yes'){$form.Enabled=$false;$code=Invoke-RepairCore;$form.Enabled=$true;[Windows.Forms.MessageBox]::Show("Reparo finalizado com código $code.",'Reparar','OK',$(if($code -eq 0){'Information'}else{'Error'}))|Out-Null;Refresh-StatusUi}})
    $btnDiag.Add_Click({try{$zip=Export-AutoRunnerDiagnostics -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath;[Windows.Forms.MessageBox]::Show("Diagnóstico criado em:`r`n$zip",'Diagnóstico','OK','Information')|Out-Null}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null}})
    $btnApp.Add_Click({try{$s=Get-SqlBackupAndFTPInstall -AllowNotFound -Quick;if($s -and $s.AppPath){Start-Process -FilePath $s.AppPath}else{throw 'Executável principal do SQLBackupAndFTP não localizado.'}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null}})
    $btnOpenFolder.Add_Click({try{$s=Get-SqlBackupAndFTPInstall -AllowNotFound -Quick;if($s){Start-Process explorer.exe -ArgumentList (ConvertTo-AutoRunnerProcessArgument -Value $s.InstallDir)}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro','OK','Error')|Out-Null}})
    $btnTask.Add_Click({Start-Process taskschd.msc})
    $btnHelp.Add_Click({try{Show-AutoRunnerTutorial -Force}catch{Write-ManagerLog $_.Exception.ToString() 'ERROR';[Windows.Forms.MessageBox]::Show(('Falha ao abrir a ajuda. Consulte o log do Manager.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message),'Ajuda do AutoRunner','OK','Error')|Out-Null}})
    $btnUninstall.Add_Click({$answer=[Windows.Forms.MessageBox]::Show('Remover somente a automação de inicialização? O aplicativo continuará instalado e os jobs do SQLBackupAndFTP serão preservados.','Remover automação','YesNo','Warning');if($answer -eq 'Yes'){$code=Invoke-UninstallCore -Keep;if($code -eq 0){[Windows.Forms.MessageBox]::Show('Automação removida. O aplicativo permanece instalado.','Remover automação','OK','Information')|Out-Null;Refresh-StatusUi}else{[Windows.Forms.MessageBox]::Show("Falha na remoção. Código $code.",'Remover automação','OK','Error')|Out-Null}}})
    $btnConnectCentral.Add_Click({Show-ControlPlaneEnrollmentDialog})
    $btnDisconnectCentral.Add_Click({try{if([Windows.Forms.MessageBox]::Show('Desconectar este AutoRunner do Control Plane? A automação local de backups não será removida.','Control Plane','YesNo','Warning') -eq 'Yes'){$code=Invoke-RemoteAgentDisconnectCore;if($code -ne 0){throw "Desconexão terminou com código $code."};Refresh-StatusUi;[Windows.Forms.MessageBox]::Show('Remote Agent removido desta máquina.','Control Plane','OK','Information')|Out-Null}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Control Plane','OK','Error')|Out-Null}})
    $btnRepairApp.Add_Click({try{[void](Start-AutoRunnerApplicationMaintenance -Action Repair);$form.Close()}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Reparar aplicativo','OK','Error')|Out-Null}})
    $btnUninstallApp.Add_Click({try{if([Windows.Forms.MessageBox]::Show('Desinstalar o aplicativo e remover a automação? Os jobs do SQLBackupAndFTP não serão apagados.','Desinstalar aplicativo','YesNo','Warning') -eq 'Yes'){[void](Start-AutoRunnerApplicationMaintenance -Action Uninstall);$form.Close()}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Desinstalar aplicativo','OK','Error')|Out-Null}})
    $btnClose.Add_Click({$form.Close()})
    if ($SmokeTest) {
        # Smoke test não interativo: constrói a interface real, atualiza o status,
        # valida os controles essenciais e fecha automaticamente. Nenhuma ação de
        # instalação, backup ou remoção é disparada.
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
        $smokeTimer = New-Object Windows.Forms.Timer
        $smokeTimer.Interval = 1200
        $smokeTimer.Add_Tick({
            $smokeTimer.Stop()
            $form.Close()
        })
        $form.Add_Shown({
            Refresh-StatusUi
            $requiredButtons = @($btnConfigure,$btnLocate,$btnDownloadSql,$btnUpdates,$btnTest,$btnLast,$btnLogs,$btnValidate,$btnRepair,$btnDiag,$btnApp,$btnOpenFolder,$btnTask,$btnUninstall,$btnConnectCentral,$btnDisconnectCentral,$btnRepairApp,$btnUninstallApp,$btnClose,$btnHelp)
            if ($requiredButtons.Count -ne 20 -or @($requiredButtons | Where-Object { $null -eq $_ -or [string]::IsNullOrWhiteSpace($_.Text) }).Count -gt 0) {
                throw 'Smoke test da GUI detectou botão obrigatório ausente ou sem texto.'
            }
            if (-not $form.Controls.Contains($rootGrid) -or -not $rootGrid.Controls.Contains($mainHost) -or -not $mainHost.Controls.Contains($mainGrid) -or -not $statusGroup.Controls.Contains($statusText)) {
                throw 'Smoke test da GUI detectou estrutura visual incompleta.'
            }
            if($sqlCard.Title.Text -eq '' -or $automationCard.Title.Text -eq '' -or $lastCard.Title.Text -eq ''){
                throw 'Smoke test da GUI detectou cartões de status incompletos.'
            }
            $smokeTimer.Start()
        })
        [void]$form.ShowDialog()
        $smokeTimer.Dispose()
        $form.Dispose()
        return
    }
    if($TutorialSmokeTest){
        Show-AutoRunnerTutorial -Force -SmokeTest
        $form.Dispose()
        return
    }
    $startupTutorialTimer=New-Object Windows.Forms.Timer
    $startupTutorialTimer.Interval=350
    $startupTutorialTimer.Add_Tick({
        $startupTutorialTimer.Stop()
        try{Show-AutoRunnerTutorial}
        catch{Write-ManagerLog $_.Exception.ToString() 'ERROR';[Windows.Forms.MessageBox]::Show(('O tutorial encontrou uma falha e foi encerrado. A interface principal continuará aberta.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message+[Environment]::NewLine+[Environment]::NewLine+'Log: '+$managerLog),'Ajuda do AutoRunner','OK','Error')|Out-Null}
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
        }catch{Write-ManagerLog $_.Exception.Message 'WARN'}
    })
    $startupStatusTimer=New-Object Windows.Forms.Timer
    $startupStatusTimer.Interval=650
    $startupStatusTimer.Add_Tick({
        $startupStatusTimer.Stop()
        try{
            Refresh-StatusUi
            Start-AutoRunnerUpdateCheck $false
            $settings=Get-AutoRunnerUserSettings
            if(-not $settings.TutorialDoNotShowAgain -or $settings.TutorialVersion -ne (Get-AutoRunnerVersion)){$startupTutorialTimer.Start()}
        }catch{
            Write-ManagerLog $_.Exception.ToString() 'ERROR'
            [Windows.Forms.MessageBox]::Show(('Falha ao atualizar o estado inicial. A interface permanecerá disponível.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message+[Environment]::NewLine+[Environment]::NewLine+'Log: '+$managerLog),'SQLBackupAndFTP AutoRunner','OK','Error')|Out-Null
        }
    })
    $form.Add_Load({
        Set-WindowOnActiveScreen -Window $form -PreferredWidth 1180 -PreferredHeight 800 -MinimumWidth 900 -MinimumHeight 620
    })
    $form.Add_Shown({
        Write-ManagerLog 'Janela principal exibida.'
        $form.ShowInTaskbar=$true
        $form.WindowState=[Windows.Forms.FormWindowState]::Normal
        $form.TopMost=$true
        $form.Activate()
        $form.BringToFront()
        [Windows.Forms.Application]::DoEvents()
        $startupForegroundTimer.Start()
        $startupStatusTimer.Start()
    })
    $form.Add_FormClosed({
        try{$startupForegroundTimer.Stop();$startupForegroundTimer.Dispose()}catch{}
        try{$startupStatusTimer.Stop();$startupStatusTimer.Dispose()}catch{}
        try{$startupTutorialTimer.Stop();$startupTutorialTimer.Dispose()}catch{}
        try{$updatePollTimer.Stop();$updatePollTimer.Dispose()}catch{}
        try{if($script:UpdateCheckProcess -and -not $script:UpdateCheckProcess.HasExited){$script:UpdateCheckProcess.Kill()}}catch{}
        if($script:UpdateCheckOutput){Remove-Item -LiteralPath $script:UpdateCheckOutput -Force -ErrorAction SilentlyContinue}
        Write-ManagerLog 'Janela principal encerrada.'
    })
    # Application.Run cria o loop de mensagens principal da aplicação. ShowDialog
    # funcionava como uma caixa modal solta e podia deixar a janela sem foco após o
    # tutorial quando o host PowerShell era iniciado oculto.
    [Windows.Forms.Application]::Run($form)
    $form.Dispose()
}

try {
    switch ($Action) {
        'Repair' { exit (Invoke-RepairCore) }
        'Validate' { $result=Invoke-ValidateCore -WriteConsole; exit $result.ExitCode }
        'Test' { exit (Invoke-TestNow) }
        'Diagnostics' { $zip=Export-AutoRunnerDiagnostics -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath; Write-Output $zip; exit 0 }
        'Uninstall' { exit (Invoke-UninstallCore -Keep) }
        'GuiSmoke' { Show-Gui -SmokeTest; Write-Output 'GUI_SMOKE_PASS'; exit 0 }
        'TutorialSmoke' { Show-Gui -TutorialSmokeTest; Write-Output 'TUTORIAL_SMOKE_PASS'; exit 0 }
        'Help' { Show-Gui; exit 0 }
        'Locate' { Show-Gui; exit 0 }
    }
    if ($Console) { Show-ConsoleMenu }
    else { try { Show-Gui } catch { Write-ManagerLog $_.Exception.ToString() 'ERROR'; try { Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show(('Não foi possível abrir a interface. Consulte o log do Manager.'+[Environment]::NewLine+[Environment]::NewLine+$_.Exception.Message),'SQLBackupAndFTP AutoRunner','OK','Error')|Out-Null } catch {}; exit 1 } }
    exit 0
}
catch {
    Write-ManagerLog $_.Exception.ToString() 'ERROR'
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
