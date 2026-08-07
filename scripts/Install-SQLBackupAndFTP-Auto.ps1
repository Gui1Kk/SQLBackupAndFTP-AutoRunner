#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Reconfigure','Repair','Validate')][string]$Mode = 'Install',
    [string]$RequestFile,
    [string]$RequestSha256,
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$TaskName = 'SQLBackupAndFTP AutoRunner',
    [string]$TaskPath = '\SQLBackupAndFTPAuto\',
    [switch]$DevelopmentMode,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$scriptPath = $PSCommandPath
$packageRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$modulePath = Join-Path $packageRoot 'modules\AutoRunner.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { throw "Módulo principal não encontrado: $modulePath" }
Import-Module $modulePath -Force -DisableNameChecking

if (Test-AutoRunnerTreeHasReparsePoint -Path $packageRoot) { throw "Pacote contém junction ou link simbólico: $packageRoot" }
if (-not (Test-AutoRunnerAdministrator)) { throw 'Execute o instalador como administrador.' }
if (-not (Test-AutoRunnerSupportPath -Path $SupportDir)) { throw "Diretório de suporte inseguro: $SupportDir" }
if ((Test-Path -LiteralPath $SupportDir -PathType Container) -and (Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir)) { throw "Diretório de suporte contém junction ou link simbólico: $SupportDir" }

# Validação é estritamente somente leitura: não cria staging, não altera tarefa, ACL ou registro.
if ($Mode -eq 'Validate') {
    $validation = Test-AutoRunnerInstallation -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
    $validation | ConvertTo-Json -Depth 10
    if (-not $validation.IsValid) { exit 2 }
    exit 0
}

$logDir = Join-Path $SupportDir 'logs'
$logPath = Join-Path $logDir 'install.log'
function Write-InstallLog {
    param([string]$Message, [ValidateSet('TRACE','INFO','WARN','ERROR','SUCCESS')][string]$Level='INFO')
    try { Write-AutoRunnerLog -Path $logPath -Message $Message -Level $Level -Component 'Installer' -NoConsole:$Quiet }
    catch { if (-not $Quiet) { Write-Host $Message } }
}

function Save-InstallFailureEvidence {
    param([Parameter(Mandatory = $true)][string]$ExceptionText)
    try {
        $failureRoot = Join-Path $env:ProgramData 'SQLBackupAndFTPAuto-InstallFailures'
        New-Item -ItemType Directory -Path $failureRoot -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $failurePath = Join-Path $failureRoot ("InstallFailure_${stamp}.log")
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('SQLBackupAndFTP AutoRunner - falha de instalação/reparo')
        $lines.Add('Data: ' + (Get-Date).ToString('s'))
        $lines.Add('Modo: ' + $Mode)
        $lines.Add('Pacote: ' + $packageRoot)
        $lines.Add('Destino: ' + $SupportDir)
        $lines.Add('Erro: ' + $ExceptionText)
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $lines.Add('')
            $lines.Add('--- install.log ---')
            foreach($line in @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)){ $lines.Add([string]$line) }
        }
        [IO.File]::WriteAllLines($failurePath,$lines,(New-Object Text.UTF8Encoding($false)))
        try {
            $icacls=Join-Path $env:SystemRoot 'System32\icacls.exe'
            & $icacls $failureRoot '/inheritance:r' | Out-Null
            & $icacls $failureRoot '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
            foreach($sid in @('*S-1-1-0','*S-1-5-11','*S-1-5-32-545','*S-1-5-4')) {
                & $icacls $failureRoot '/remove:g' $sid '/T' '/C' '/Q' | Out-Null
            }
        } catch {}
        return $failurePath
    } catch { return $null }
}

$rollbackRoot = $null
$stagingRoot = $null
$taskBackupPath = $null
try {
    $rollbackRoot = New-AutoRunnerPrivilegedScratchDirectory -Prefix 'AlphaAutoRunner-AutomationRollback-'
    $stagingRoot = New-AutoRunnerPrivilegedScratchDirectory -Prefix 'AlphaAutoRunner-AutomationStage-'
    $taskBackupPath = Join-Path $rollbackRoot 'task.xml'
}
catch {
    if ($rollbackRoot) { try { Remove-AutoRunnerPrivilegedScratchDirectory -Path $rollbackRoot -AllowedPrefixes @('AlphaAutoRunner-AutomationRollback-') } catch {} }
    throw
}
$hadTask = $false
$existingSupport = Test-Path -LiteralPath $SupportDir

function Copy-TreeFile {
    param([string]$RelativePath)
    $source = Join-Path $packageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Arquivo do pacote ausente: $RelativePath" }
    $target = Join-Path $stagingRoot $RelativePath
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}

function Restore-Rollback {
    $rollbackLog = Join-Path $rollbackRoot 'rollback.log'
    function Write-RollbackLog([string]$Text) {
        try { Add-Content -LiteralPath $rollbackLog -Value ((Get-Date -Format 's') + ' ' + $Text) -Encoding UTF8 } catch {}
    }
    Write-RollbackLog 'Iniciando rollback.'
    try { Remove-AutoRunnerIntegration -TaskName $TaskName -TaskPath $TaskPath } catch { Write-RollbackLog ('Falha ao limpar integrações atuais: ' + $_.Exception.Message) }
    try {
        if (Test-Path -LiteralPath (Join-Path $rollbackRoot 'support')) {
            if (Test-Path -LiteralPath $SupportDir) { Remove-Item -LiteralPath $SupportDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $SupportDir -Force | Out-Null
            Copy-AutoRunnerTreeSafe -Source (Join-Path $rollbackRoot 'support') -Destination $SupportDir
            try { Protect-AutoRunnerDirectory -Path $SupportDir | Out-Null } catch { Write-RollbackLog ('Falha ao restaurar ACL: ' + $_.Exception.Message) }
        }
        elseif (-not $existingSupport -and (Test-Path -LiteralPath $SupportDir)) {
            Remove-Item -LiteralPath $SupportDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { Write-RollbackLog ('Falha ao restaurar arquivos: ' + $_.Exception.Message) }

    try {
        if ($hadTask -and (Test-Path -LiteralPath $taskBackupPath)) {
            Ensure-AutoRunnerTaskFolder -TaskPath $TaskPath
            $xml = Get-Content -LiteralPath $taskBackupPath -Raw
            Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml $xml -Force | Out-Null
        }
    } catch { Write-RollbackLog ('Falha ao restaurar tarefa: ' + $_.Exception.Message) }

    if ($existingSupport -and (Test-Path -LiteralPath (Join-Path $SupportDir 'config.json'))) {
        try { Register-AutoRunnerUninstallEntry -SupportDir $SupportDir } catch { Write-RollbackLog ('Falha ao restaurar entrada de programas: ' + $_.Exception.Message) }
        try { New-AutoRunnerShortcut -SupportDir $SupportDir | Out-Null } catch { Write-RollbackLog ('Falha ao restaurar atalho: ' + $_.Exception.Message) }
    }
    Write-RollbackLog 'Rollback finalizado.'
}


try {
    New-Item -ItemType Directory -Path $SupportDir -Force | Out-Null
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-InstallLog ("Início. Modo=$Mode; Pacote=$packageRoot; Destino=$SupportDir")
    $checksumResult = Test-AutoRunnerPackageChecksums -RootPath $packageRoot
    if ($checksumResult.IsPresent) {
        if (-not $checksumResult.IsValid) { throw ('Falha de integridade do pacote: ' + ($checksumResult.Issues -join '; ')) }
        Write-InstallLog 'SHA256SUMS.txt validado; pacote sem divergências detectadas.' 'SUCCESS'
    }
    else {
        $sourceIsInstalled = ([IO.Path]::GetFullPath($packageRoot).TrimEnd('\') -ieq [IO.Path]::GetFullPath($SupportDir).TrimEnd('\'))
        $installedManifest = Join-Path $SupportDir 'manifest.json'
        if($sourceIsInstalled -and (Test-Path -LiteralPath $installedManifest -PathType Leaf)){
            $installedManifestTest=Test-AutoRunnerManifest -RootPath $SupportDir -ManifestPath $installedManifest
            if(-not $installedManifestTest.IsValid){throw ('Fonte instalada sem checksum e com manifesto inválido: '+($installedManifestTest.Issues -join '; '))}
            Write-InstallLog 'Fonte instalada validada pelo manifesto para reparo/reconfiguração.' 'SUCCESS'
        }
        elseif($DevelopmentMode){Write-InstallLog 'SHA256SUMS.txt ausente; DevelopmentMode foi informado explicitamente. Não use este modo em clientes.' 'WARN'}
        else{throw 'SHA256SUMS.txt ausente. Use um pacote oficial íntegro; DevelopmentMode é exclusivo para desenvolvimento controlado.'}
    }

    try {
        Export-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop | Out-File -LiteralPath $taskBackupPath -Encoding UTF8
        $hadTask = $true
        Write-InstallLog 'Definição da tarefa existente preservada para rollback.' 'TRACE'
    } catch { $hadTask = $false }

    if ($existingSupport) {
        $backupSupport = Join-Path $rollbackRoot 'support'
        Copy-AutoRunnerTreeSafe -Source $SupportDir -Destination $backupSupport
        Write-InstallLog 'Cópia integral e segura do estado anterior criada para rollback.' 'TRACE'
    }

    $runtimeFiles = @(
        'modules\AutoRunner.Core.psm1',
        'scripts\Run-SQLBackupAndFTPJob.ps1',
        'scripts\Manager.ps1',
        'scripts\Install-SQLBackupAndFTP-Auto.ps1',
        'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1',
        'scripts\Export-Diagnostics.ps1',
        'scripts\Invoke-QA.ps1',
        'README.md',
        'CHANGELOG.md',
        'docs\GUIA_DE_USO.md',
        'docs\DOCUMENTACAO_TECNICA.md',
        'docs\SEGURANCA.md',
        'docs\PLANO_DE_TESTES.md',
        'docs\PLANO_DE_USO_E_NEGOCIO.md',
        'docs\RELATORIO_QA.md',
        'docs\MATRIZ_RASTREABILIDADE.md',
        'docs\NOTAS_DA_VERSAO.md',
        'docs\CHECKLIST_PRINTS_PDF.md'
    )
    if (Test-Path -LiteralPath (Join-Path $packageRoot 'assets\AutoRunner.ico')) { $runtimeFiles += 'assets\AutoRunner.ico' }
    if (Test-Path -LiteralPath (Join-Path $packageRoot 'SQLBackupAndFTP-AutoRunner.exe')) { $runtimeFiles += 'SQLBackupAndFTP-AutoRunner.exe' }
    foreach ($file in $runtimeFiles) { Copy-TreeFile -RelativePath $file }

    $userSettings=Get-AutoRunnerUserSettings
    $installInfo = Get-SqlBackupAndFTPInstall -PreferredPath ([string]$userSettings.PreferredSqlBackupPath) -SavePreference
    $cliSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath $installInfo.CliPath
    if(-not $cliSecurity.IsSafe){throw ('Instalação do SQLBackupAndFTP recusada por segurança: '+($cliSecurity.Issues -join '; '))}
    Write-InstallLog ("SQLBackupAndFTP detectado: $($installInfo.InstallDir); CLI=$($installInfo.CliVersion); Serviço=$($installInfo.ServiceName)") 'SUCCESS'
    $discovery = Get-SqlBakJobs -InstallInfo $installInfo
    foreach ($errorText in @($discovery.Errors)) { Write-InstallLog ("Aviso de descoberta: $errorText") 'WARN' }

    $existingConfigPath = Join-Path $SupportDir 'config.json'
    $existingConfig = Read-AutoRunnerJson -Path $existingConfigPath -AllowMissing
    $config = $null

    if ($Mode -eq 'Repair') {
        if ($null -eq $existingConfig) { throw 'Não existe configuração para reparar. Use Instalar/Reconfigurar.' }
        $config = ConvertTo-AutoRunnerCurrentConfig -Config $existingConfig -InstallInfo $installInfo
        $config.SqlBackupAndFTP.InstallDir = $installInfo.InstallDir
        $config.SqlBackupAndFTP.CliPath = $installInfo.CliPath
        $config.SqlBackupAndFTP.CliVersion = $installInfo.CliVersion
        $config.SqlBackupAndFTP.AppPath = $installInfo.AppPath
        $config.SqlBackupAndFTP.AppVersion = $installInfo.AppVersion
        $config.SqlBackupAndFTP.ServiceName = $installInfo.ServiceName
        $config.SqlBackupAndFTP.ServiceDisplayName = $installInfo.ServiceDisplayName
        if ($discovery.ConfigRootExists) { $config.SqlBackupAndFTP.ConfigRoot = $discovery.ConfigRoot }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$config.SqlBackupAndFTP.ConfigRoot)) { Write-InstallLog ('ConfigRoot anterior preservado; descoberta atual não encontrou context.db: ' + [string]$config.SqlBackupAndFTP.ConfigRoot) 'WARN' }
        $config.AppVersion = Get-AutoRunnerVersion
        $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        if ($discovery.DiscoverySucceeded) {
            $availableNames = @($discovery.Jobs | ForEach-Object { [string]$_.Name })
            $missingNames = @($config.Jobs | Where-Object { [string]$_.Name -notin $availableNames } | ForEach-Object { [string]$_.Name })
            if ($missingNames.Count -gt 0) {
                Write-InstallLog ('Jobs configurados não encontrados na descoberta atual e preservados sem remoção automática: ' + ($missingNames -join ', ')) 'WARN'
                Write-InstallLog 'Use Reconfigurar para confirmar nomes novos ou remover jobs antigos.' 'WARN'
            }
        }
        Write-InstallLog 'Configuração anterior preservada durante o reparo.' 'SUCCESS'
    }
    else {
        if ([string]::IsNullOrWhiteSpace($RequestFile) -or -not (Test-Path -LiteralPath $RequestFile)) {
            throw 'Arquivo de solicitação não informado. A seleção explícita dos jobs é obrigatória.'
        }
        if ([string]::IsNullOrWhiteSpace($RequestSha256) -or $RequestSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw 'SHA-256 da solicitação de instalação não foi informado ou é inválido.'
        }
        # O arquivo nasce no contexto não elevado da interface. Leia os bytes uma única
        # vez, valide o hash recebido pela linha de comando e só então interprete o JSON.
        # Assim uma troca do arquivo entre UAC, hashing e parsing não altera a solicitação.
        $requestBytes=[IO.File]::ReadAllBytes($RequestFile)
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$actualRequestSha=([BitConverter]::ToString($sha.ComputeHash($requestBytes))).Replace('-','')}finally{$sha.Dispose()}
        if($actualRequestSha -ine $RequestSha256){throw 'A solicitação de instalação foi alterada depois da confirmação; operação recusada.'}
        $requestText=(New-Object Text.UTF8Encoding($false,$true)).GetString($requestBytes)
        if([string]::IsNullOrWhiteSpace($requestText)){throw 'Arquivo de solicitação vazio.'}
        try{$request=$requestText|ConvertFrom-Json}catch{throw ('Solicitação JSON inválida: '+$_.Exception.Message)}
        if ([string](Get-AutoRunnerPropertyValue -InputObject $request -Name 'Product' -Default '') -ne 'SQLBackupAndFTP AutoRunner') { throw 'Arquivo de solicitação não pertence ao AutoRunner.' }
        $selectedJobs = @($request.Jobs)
        if ($selectedJobs.Count -eq 0) { throw 'Selecione ao menos um job.' }

        $normalizedJobs = New-Object System.Collections.Generic.List[object]
        $seenJobNames = @{}
        foreach ($job in $selectedJobs) {
            $name = ([string]$job.Name).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { throw 'Existe job com nome vazio.' }
            if ($name.Length -gt 250) { throw "O nome do job excede 250 caracteres: '$name'." }
            if ($name -match '[\x00-\x1F\x7F]') { throw "O nome do job contém caractere de controle: '$name'." }
            $nameKey = $name.ToLowerInvariant()
            if ($seenJobNames.ContainsKey($nameKey)) { throw "Job duplicado na seleção: '$name'." }
            $seenJobNames[$nameKey] = $true
            $backupType = [string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'BackupType' -Default 'Default')
            if ($backupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')) { throw "Tipo de backup inválido para '$name': $backupType" }
            $confirmed = ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmedByTechnician') -Default $false -Name 'ConfirmedByTechnician'
            if (-not $confirmed) { throw "O job '$name' não foi confirmado pelo técnico." }
            $sourceText=[string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'Source' -Default 'Manual')
            $typeText=[string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'Type' -Default 'Desconhecido')
            if($sourceText.Length -gt 100 -or $sourceText -match '[\x00-\x1F\x7F]'){throw "Origem inválida para '$name'."}
            if($typeText.Length -gt 100 -or $typeText -match '[\x00-\x1F\x7F]'){throw "Tipo descritivo inválido para '$name'."}
            $scheduledValue=Get-AutoRunnerPropertyValue -InputObject $job -Name 'IsScheduled'
            $normalizedJobs.Add([pscustomobject][ordered]@{
                Name = $name
                BackupType = $backupType
                Source = $sourceText
                Type = $typeText
                IsScheduled = if ($null -ne $scheduledValue) { ConvertTo-AutoRunnerBoolean -Value $scheduledValue -Name 'IsScheduled' } else { $null }
                LastRunAt = Get-AutoRunnerPropertyValue -InputObject $job -Name 'LastRunAt'
                ConfirmedByTechnician = $true
                ConfirmedAtUtc = [string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmedAtUtc' -Default ([DateTime]::UtcNow.ToString('o')))
                ConfirmedBy = [string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmedBy' -Default ([Security.Principal.WindowsIdentity]::GetCurrent().Name))
                ConfirmationReason = [string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmationReason' -Default 'Seleção explícita na interface')
            })
        }

        $config = New-AutoRunnerDefaultConfig -InstallInfo $installInfo -Jobs @($normalizedJobs)
        $existingInstallId = if ($existingConfig) { Get-AutoRunnerPropertyValue -InputObject $existingConfig -Name 'InstallId' } else { $null }
        if ($existingInstallId) {
            $config.InstallId = [string]$existingInstallId
            $existingInstalledAt = Get-AutoRunnerPropertyValue -InputObject $existingConfig -Name 'InstalledAtUtc'
            if ($existingInstalledAt) { $config.InstalledAtUtc = [string]$existingInstalledAt }
        }
        if ($discovery.ConfigRootExists) { $config.SqlBackupAndFTP.ConfigRoot = $discovery.ConfigRoot }
        elseif ($existingConfig) {
            $oldSql = Get-AutoRunnerPropertyValue -InputObject $existingConfig -Name 'SqlBackupAndFTP'
            $oldRoot = Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'ConfigRoot'
            if ($oldRoot) { $config.SqlBackupAndFTP.ConfigRoot = [string]$oldRoot }
        }
        $requestExecution = Get-AutoRunnerPropertyValue -InputObject $request -Name 'Execution'
        $requestLogging = Get-AutoRunnerPropertyValue -InputObject $request -Name 'Logging'
        foreach ($name in @('StartupDelayMinutes','MinimumIntervalHours','RetryCount','RetryDelayMinutes','ServiceWaitSeconds','SqlServiceWaitSeconds','ExecutionTimeLimitHours','PostJobDelaySeconds','TaskRestartCount','TaskRestartIntervalMinutes')) {
            $value = Get-AutoRunnerPropertyValue -InputObject $requestExecution -Name $name
            if ($null -ne $value) { $config.Execution.$name = [int]$value }
        }
        foreach ($name in @('RetryOnCliError','StopOnFirstFailure','TaskRestartOnFailure')) {
            $value = Get-AutoRunnerPropertyValue -InputObject $requestExecution -Name $name
            if ($null -ne $value) { $config.Execution.$name = ConvertTo-AutoRunnerBoolean -Value $value -Name $name }
        }
        $sqlWaitMode = [string](Get-AutoRunnerPropertyValue -InputObject $requestExecution -Name 'SqlServiceWaitMode' -Default $config.Execution.SqlServiceWaitMode)
        if ($sqlWaitMode -notin @('None','AnyAutomaticLocal','AllAutomaticLocal')) { throw "Modo de espera do SQL Server inválido: $sqlWaitMode" }
        $config.Execution.SqlServiceWaitMode = $sqlWaitMode
        foreach ($name in @('MaxSizeMB','KeepFiles','RetentionDays')) {
            $value = Get-AutoRunnerPropertyValue -InputObject $requestLogging -Name $name
            if ($null -ne $value) { $config.Logging.$name = [int]$value }
        }
        $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    $configuredNameSet = @{}
    foreach ($configuredJob in @($config.Jobs)) {
        $configuredName = ([string]$configuredJob.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($configuredName)) { throw 'A configuração resultante contém job vazio.' }
        $configuredKey = $configuredName.ToLowerInvariant()
        if ($configuredNameSet.ContainsKey($configuredKey)) { throw "A configuração resultante contém job duplicado: '$configuredName'." }
        $configuredNameSet[$configuredKey] = $true
        $configuredBackupType = [string](Get-AutoRunnerPropertyValue -InputObject $configuredJob -Name 'BackupType' -Default 'Default')
        if ($configuredBackupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')) { throw "Tipo de backup inválido na configuração de '$configuredName': $configuredBackupType" }
        $configuredConfirmed = ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $configuredJob -Name 'ConfirmedByTechnician') -Default $false -Name 'ConfirmedByTechnician'
        if (-not $configuredConfirmed) { throw "O job '$configuredName' não possui confirmação técnica registrada." }
    }

    # Validações de faixa, independentes da interface.
    if ([int]$config.Execution.StartupDelayMinutes -lt 0 -or [int]$config.Execution.StartupDelayMinutes -gt 120) { throw 'Atraso inicial deve estar entre 0 e 120 minutos.' }
    if ([int]$config.Execution.MinimumIntervalHours -lt 0 -or [int]$config.Execution.MinimumIntervalHours -gt 720) { throw 'Intervalo mínimo deve estar entre 0 e 720 horas.' }
    if ([int]$config.Execution.RetryCount -lt 0 -or [int]$config.Execution.RetryCount -gt 10) { throw 'Quantidade de novas tentativas deve estar entre 0 e 10.' }
    if ([int]$config.Execution.RetryDelayMinutes -lt 0 -or [int]$config.Execution.RetryDelayMinutes -gt 60) { throw 'Espera entre tentativas deve estar entre 0 e 60 minutos.' }
    if ([int]$config.Execution.ServiceWaitSeconds -lt 0 -or [int]$config.Execution.ServiceWaitSeconds -gt 1800) { throw 'Espera pelo serviço do SQLBackupAndFTP deve estar entre 0 e 1800 segundos.' }
    if ([int]$config.Execution.SqlServiceWaitSeconds -lt 0 -or [int]$config.Execution.SqlServiceWaitSeconds -gt 1800) { throw 'Espera pelos serviços SQL deve estar entre 0 e 1800 segundos.' }
    if ([string]$config.Execution.SqlServiceWaitMode -notin @('None','AnyAutomaticLocal','AllAutomaticLocal')) { throw 'Modo de espera do SQL Server inválido.' }
    $config.Execution.RetryOnCliError = ConvertTo-AutoRunnerBoolean -Value $config.Execution.RetryOnCliError -Default $false -Name 'RetryOnCliError'
    $config.Execution.StopOnFirstFailure = ConvertTo-AutoRunnerBoolean -Value $config.Execution.StopOnFirstFailure -Default $false -Name 'StopOnFirstFailure'
    $config.Execution.TaskRestartOnFailure = ConvertTo-AutoRunnerBoolean -Value $config.Execution.TaskRestartOnFailure -Default $false -Name 'TaskRestartOnFailure'
    if ([int]$config.Execution.PostJobDelaySeconds -lt 0 -or [int]$config.Execution.PostJobDelaySeconds -gt 600) { throw 'Espera entre jobs deve estar entre 0 e 600 segundos.' }
    if ([int]$config.Execution.ExecutionTimeLimitHours -lt 1 -or [int]$config.Execution.ExecutionTimeLimitHours -gt 168) { throw 'Limite de execução deve estar entre 1 e 168 horas.' }
    if ([int]$config.Execution.TaskRestartCount -lt 1 -or [int]$config.Execution.TaskRestartCount -gt 10) { throw 'Quantidade de reinícios da tarefa deve estar entre 1 e 10.' }
    if ([int]$config.Execution.TaskRestartIntervalMinutes -lt 1 -or [int]$config.Execution.TaskRestartIntervalMinutes -gt 1440) { throw 'Intervalo de reinício da tarefa deve estar entre 1 e 1440 minutos.' }
    if ([int]$config.Logging.MaxSizeMB -lt 1 -or [int]$config.Logging.MaxSizeMB -gt 1024) { throw 'Tamanho máximo de log deve estar entre 1 e 1024 MB.' }
    if ([int]$config.Logging.KeepFiles -lt 1 -or [int]$config.Logging.KeepFiles -gt 50) { throw 'Quantidade de logs mantidos deve estar entre 1 e 50.' }
    if ([int]$config.Logging.RetentionDays -lt 1 -or [int]$config.Logging.RetentionDays -gt 3650) { throw 'Retenção de logs deve estar entre 1 e 3650 dias.' }

    # Remove somente diretórios de runtime previamente preservados no rollback. Isso evita
    # scripts obsoletos após atualização, sem tocar em configuração, estados ou logs.
    foreach($runtimeDirectory in @('scripts','modules','assets','docs')){
        $targetRuntimeDirectory=Join-Path $SupportDir $runtimeDirectory
        if(Test-Path -LiteralPath $targetRuntimeDirectory){
            if(Test-AutoRunnerTreeHasReparsePoint -Path $targetRuntimeDirectory){throw "Runtime existente contém reparse point: $targetRuntimeDirectory"}
            Remove-Item -LiteralPath $targetRuntimeDirectory -Recurse -Force
        }
    }
    foreach ($relative in $runtimeFiles) {
        $source = Join-Path $stagingRoot $relative
        $target = Join-Path $SupportDir $relative
        Copy-AutoRunnerFileAtomic -Source $source -Destination $target
    }

    $runnerTarget = Join-Path $SupportDir 'scripts\Run-SQLBackupAndFTPJob.ps1'
    $coreTarget = Join-Path $SupportDir 'modules\AutoRunner.Core.psm1'
    $config.Security.RunnerSha256 = Get-AutoRunnerFileHash -Path $runnerTarget
    $config.Security.CoreModuleSha256 = Get-AutoRunnerFileHash -Path $coreTarget
    try { $config.Security.SignatureStatus = [string](Get-AuthenticodeSignature -LiteralPath $runnerTarget).Status } catch { $config.Security.SignatureStatus = 'NotChecked' }
    $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $configPath = Join-Path $SupportDir 'config.json'
    Write-AutoRunnerJsonAtomic -InputObject $config -Path $configPath -CreateBackup -Depth 30
    $statePath = Join-Path $SupportDir 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        Write-AutoRunnerJsonAtomic -InputObject (Get-AutoRunnerStateTemplate) -Path $statePath -Depth 20
    }

    $manifestFiles = @(
        'modules\AutoRunner.Core.psm1',
        'scripts\Run-SQLBackupAndFTPJob.ps1',
        'scripts\Manager.ps1',
        'scripts\Install-SQLBackupAndFTP-Auto.ps1',
        'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1',
        'scripts\Export-Diagnostics.ps1',
        'scripts\Invoke-QA.ps1'
    )
    $installedManifestPath=Join-Path $SupportDir 'manifest.json'
    New-AutoRunnerManifest -RootPath $SupportDir -RelativePaths $manifestFiles -OutputPath $installedManifestPath | Out-Null
    $config.Security.ManifestSha256=Get-AutoRunnerFileHash -Path $installedManifestPath
    Write-AutoRunnerJsonAtomic -InputObject $config -Path $configPath -CreateBackup -Depth 30

    Protect-AutoRunnerDirectory -Path $SupportDir | Out-Null
    Register-AutoRunnerScheduledTask -SupportDir $SupportDir -Config $config -TaskName $TaskName -TaskPath $TaskPath | Out-Null
    Register-AutoRunnerUninstallEntry -SupportDir $SupportDir
    New-AutoRunnerShortcut -SupportDir $SupportDir | Out-Null

    $validation = Test-AutoRunnerInstallation -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
    foreach ($check in $validation.Checks) {
        Write-InstallLog ("[{0}] {1}: {2}" -f $(if ($check.Ok) {'OK'} else {'FALHA'}), $check.Name, $check.Detail) $(if ($check.Ok) {'TRACE'} else {'ERROR'})
    }
    if (-not $validation.IsValid) { throw 'Validação final encontrou falhas.' }

    Write-InstallLog ("$Mode concluído com sucesso. Jobs: $((@($config.Jobs) | ForEach-Object { $_.Name }) -join ', ')") 'SUCCESS'
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'SQLBackupAndFTP AutoRunner instalado e validado com sucesso.' -ForegroundColor Green
        Write-Host ('Jobs: ' + ((@($config.Jobs) | ForEach-Object { $_.Name }) -join ', '))
        Write-Host ('Tarefa: ' + $TaskPath + $TaskName)
        Write-Host ('Logs: ' + (Join-Path $SupportDir 'logs'))
    }
    exit 0
}
catch {
    $failureText=$_.Exception.ToString()
    try { Write-InstallLog $failureText 'ERROR' } catch {}
    $failureEvidence=Save-InstallFailureEvidence -ExceptionText $failureText
    Restore-Rollback
    if($failureEvidence -and (Test-Path -LiteralPath $SupportDir -PathType Container)){
        try{New-Item -ItemType Directory -Path (Join-Path $SupportDir 'logs') -Force|Out-Null;Copy-Item -LiteralPath $failureEvidence -Destination (Join-Path $SupportDir 'logs') -Force;Protect-AutoRunnerDirectory -Path $SupportDir|Out-Null}catch{}
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'A instalação não foi concluída. O estado anterior foi restaurado quando possível.' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        if($failureEvidence){Write-Host ('Evidência preservada em: '+$failureEvidence) -ForegroundColor Yellow}
    }
    exit 1
}
finally {
    if ($rollbackRoot) { try { Remove-AutoRunnerPrivilegedScratchDirectory -Path $rollbackRoot -AllowedPrefixes @('AlphaAutoRunner-AutomationRollback-') } catch {} }
    if ($stagingRoot) { try { Remove-AutoRunnerPrivilegedScratchDirectory -Path $stagingRoot -AllowedPrefixes @('AlphaAutoRunner-AutomationStage-') } catch {} }
}
