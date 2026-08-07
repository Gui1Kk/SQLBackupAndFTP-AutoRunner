#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Startup','Manual','Task','Test')][string]$Trigger = 'Manual',
    [switch]$Force,
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$ConfigPath,
    [string]$StatePath,
    [string]$LogPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$exitCode = 99
$mutex = $null
$hasMutex = $false

if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $SupportDir 'config.json' }
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $SupportDir 'state.json' }
if ([string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = Join-Path $SupportDir 'runner.log' }
$modulePath = Join-Path $SupportDir 'modules\AutoRunner.Core.psm1'
$manifestPath = Join-Path $SupportDir 'manifest.json'

function Write-BootstrapLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $directory = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        if ((Test-Path -LiteralPath $LogPath -PathType Leaf) -and (Get-Item -LiteralPath $LogPath).Length -gt 20MB) {
            Move-Item -LiteralPath $LogPath -Destination ($LogPath+'.bootstrap-old') -Force -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $LogPath -Value ('{0} [{1}] [RunnerBootstrap] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message) -Encoding UTF8
    } catch {}
}

try {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Modulo principal ausente: $modulePath" }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Configuração ausente: $ConfigPath" }

    # Verificação bootstrap antes de importar o módulo. A ACL continua sendo a primeira
    # barreira; esta checagem impede executar um módulo alterado acidentalmente depois da instalação.
    $bootstrapRaw=(Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8)|ConvertFrom-Json
    $bootstrapProductProperty=$bootstrapRaw.PSObject.Properties['Product']
    $bootstrapProduct=if($bootstrapProductProperty){[string]$bootstrapProductProperty.Value}else{''}
    if($bootstrapProduct -ne 'SQLBackupAndFTP AutoRunner'){throw 'Configuração bootstrap pertence a outro produto ou está incompleta.'}
    $bootstrapSchemaProperty=$bootstrapRaw.PSObject.Properties['SchemaVersion']
    $bootstrapSchema=if($bootstrapSchemaProperty){[int]$bootstrapSchemaProperty.Value}else{0}
    if($bootstrapSchema -gt 4){throw "Schema bootstrap $bootstrapSchema é mais novo que o runner suporta."}
    $bootstrapSecurityProperty=$bootstrapRaw.PSObject.Properties['Security']
    $bootstrapSecurity=if($bootstrapSecurityProperty){$bootstrapSecurityProperty.Value}else{$null}
    $expectedCoreHash=''
    if($bootstrapSecurity -and $bootstrapSecurity.PSObject.Properties['CoreModuleSha256']){$expectedCoreHash=[string]$bootstrapSecurity.CoreModuleSha256}
    if($bootstrapSchema -ge 4 -and $expectedCoreHash -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Hash bootstrap do módulo principal ausente ou inválido.'}
    if(-not [string]::IsNullOrWhiteSpace($expectedCoreHash)){
        $actualCoreHash=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToUpperInvariant()
        if($actualCoreHash -ne $expectedCoreHash.ToUpperInvariant()){throw 'Hash do módulo principal diverge da configuração; execução recusada antes da importação.'}
    }
    Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
    if(-not(Test-AutoRunnerSupportPath -Path $SupportDir)){throw "Diretório de suporte inseguro: $SupportDir"}
    foreach($runtimePath in @($ConfigPath,$StatePath,$LogPath,$modulePath,$manifestPath)){
        if(-not(Test-AutoRunnerPathIsWithin -ChildPath $runtimePath -ParentPath $SupportDir)){throw "Caminho operacional fora da instalação: $runtimePath"}
        if(Test-AutoRunnerPathHasReparsePoint -Path $runtimePath -StopAtPath $SupportDir){throw "Caminho operacional contém reparse point: $runtimePath"}
    }
    $rawConfig = Read-AutoRunnerJson -Path $ConfigPath
    $rawSchema = [int](Get-AutoRunnerPropertyValue -InputObject $rawConfig -Name 'SchemaVersion' -Default 0)
    if ($rawSchema -gt (Get-AutoRunnerSchemaVersion)) { throw "Schema de configuração $rawSchema é mais novo que o suportado. Atualize o AutoRunner." }
    $rawSql = Get-AutoRunnerPropertyValue -InputObject $rawConfig -Name 'SqlBackupAndFTP'
    $configInstall = [pscustomobject]@{
        InstallDir=[string](Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'InstallDir' -Default '')
        CliPath=[string](Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'CliPath' -Default '')
        CliVersion=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'CliVersion'
        AppPath=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'AppPath'
        AppVersion=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'AppVersion'
        ServiceName=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'ServiceName'
        ServiceDisplayName=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'ServiceDisplayName'
        ConfigRoot=Get-AutoRunnerPropertyValue -InputObject $rawSql -Name 'ConfigRoot'
    }
    $config = ConvertTo-AutoRunnerCurrentConfig -Config $rawConfig -InstallInfo $configInstall
    if ([string]$config.Product -ne 'SQLBackupAndFTP AutoRunner') { throw 'Configuração não pertence ao SQLBackupAndFTP AutoRunner.' }
    $configValidation=Test-AutoRunnerConfiguration -Config $config -RequireSecurityHashes -RequireExistingCli
    if(-not $configValidation.IsValid){throw ('Configuração operacional inválida: '+($configValidation.Issues -join '; '))}
    if ([string]::IsNullOrWhiteSpace([string]$config.InstallId)) { $config.InstallId = Get-AutoRunnerStringHash -Value $SupportDir -Length 24 }
    if ($rawSchema -ne (Get-AutoRunnerSchemaVersion)) {
        Write-AutoRunnerJsonAtomic -InputObject $config -Path $ConfigPath -CreateBackup -Depth 30
        Write-BootstrapLog -Message "Configuração migrada do schema $rawSchema para $(Get-AutoRunnerSchemaVersion)." -Level 'WARN'
    }
    $logging = $config.Logging
    $jobLogDir = Join-Path $SupportDir 'logs\jobs'
    $jobStateDir = Join-Path $SupportDir 'state\jobs'
    New-Item -ItemType Directory -Path $jobLogDir -Force | Out-Null
    New-Item -ItemType Directory -Path $jobStateDir -Force | Out-Null

    # Limpa logs de jobs que deixaram de existir e artefatos corrompidos antigos.
    $retentionCutoff=(Get-Date).AddDays(-[int]$logging.RetentionDays)
    foreach($cleanupDir in @($jobLogDir,$jobStateDir)){
        Get-ChildItem -LiteralPath $cleanupDir -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $retentionCutoff -and ($_.Name -match '\.(log|corrupt\.|json\.bak)') } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Write-RunnerLog {
        param([string]$Message, [ValidateSet('TRACE','INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO')
        Write-AutoRunnerLog -Path $LogPath -Message $Message -Level $Level -Component 'Runner' -MaxSizeMB ([int]$logging.MaxSizeMB) -KeepFiles ([int]$logging.KeepFiles) -RetentionDays ([int]$logging.RetentionDays)
    }

    function Write-JobLog {
        param([string]$JobName,[string]$Message,[string]$Level='INFO')
        $artifact = Get-AutoRunnerJobArtifactName -JobName $JobName
        $path = Join-Path $jobLogDir ($artifact + '.log')
        Write-AutoRunnerLog -Path $path -Message $Message -Level $Level -Component ('Job:' + $JobName) -NoConsole -MaxSizeMB ([int]$logging.MaxSizeMB) -KeepFiles ([int]$logging.KeepFiles) -RetentionDays ([int]$logging.RetentionDays)
    }

    function Read-JobStateSafe {
        param([Parameter(Mandatory = $true)][string]$Path,[string]$JobName)
        try { return Read-AutoRunnerJson -Path $Path -AllowMissing }
        catch {
            $corruptPath = $Path + '.corrupt.' + (Get-Date -Format 'yyyyMMdd_HHmmss')
            try { Move-Item -LiteralPath $Path -Destination $corruptPath -Force -ErrorAction SilentlyContinue } catch {}
            Write-RunnerLog ("Estado individual inválido para '$JobName'; será tratado como não executado anteriormente. Arquivo preservado em '$corruptPath'. Erro: $($_.Exception.Message)") 'WARN'
            return $null
        }
    }

    Write-RunnerLog ('Inicio. Trigger={0}; Force={1}; AutoRunner={2}; PID={3}; Usuario={4}' -f $Trigger, [bool]$Force, (Get-AutoRunnerVersion), $PID, [Security.Principal.WindowsIdentity]::GetCurrent().Name)

    if (ConvertTo-AutoRunnerBoolean -Value $config.Security.EnforceManifest -Default $false -Name 'EnforceManifest') {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-RunnerLog 'Manifesto de integridade ausente.' 'ERROR'
            exit 21
        }
        $expectedManifestHash=[string](Get-AutoRunnerPropertyValue -InputObject $config.Security -Name 'ManifestSha256' -Default '')
        if($expectedManifestHash -notmatch '^[A-Fa-f0-9]{64}$'){Write-RunnerLog 'Hash do manifesto ausente ou inválido.' 'ERROR';exit 21}
        if(-not [string]::IsNullOrWhiteSpace($expectedManifestHash)){
            $actualManifestHash=Get-AutoRunnerFileHash -Path $manifestPath
            if($actualManifestHash -ne $expectedManifestHash.ToUpperInvariant()){
                Write-RunnerLog 'Hash do manifesto diverge do valor registrado na configuração.' 'ERROR'
                exit 21
            }
        }
        $manifestTest = Test-AutoRunnerManifest -RootPath $SupportDir -ManifestPath $manifestPath
        if (-not $manifestTest.IsValid) {
            Write-RunnerLog ('Falha de integridade: ' + ($manifestTest.Issues -join '; ')) 'ERROR'
            exit 21
        }
        Write-RunnerLog 'Manifesto de integridade validado.' 'TRACE'
    }

    $expectedRunnerHash=[string](Get-AutoRunnerPropertyValue -InputObject $config.Security -Name 'RunnerSha256' -Default '')
    if($expectedRunnerHash -notmatch '^[A-Fa-f0-9]{64}$'){Write-RunnerLog 'Hash do runner ausente ou inválido.' 'ERROR';exit 21}
    if(-not [string]::IsNullOrWhiteSpace($expectedRunnerHash)){
        $actualRunnerHash=Get-AutoRunnerFileHash -Path $PSCommandPath
        if($actualRunnerHash -ne $expectedRunnerHash.ToUpperInvariant()){
            Write-RunnerLog 'Hash do runner diverge do valor registrado na configuração.' 'ERROR'
            exit 21
        }
    }

    $mutexName = 'Global\SQLBackupAndFTPAutoRunner-' + ([string]$config.InstallId -replace '[^A-Za-z0-9-]','')
    $createdNew = $false
    $mutex = New-Object Threading.Mutex($false, $mutexName, [ref]$createdNew)
    try {
        $hasMutex = $mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $hasMutex = $true
        Write-RunnerLog 'Mutex abandonado recuperado; a execucao anterior foi interrompida abruptamente.' 'WARN'
    }
    if (-not $hasMutex) {
        Write-RunnerLog 'Outra execução já está ativa. Esta instância não executará jobs.' 'WARN'
        # No boot isso é condição normal; em teste manual, devolve código informativo para
        # não comunicar falsamente que um backup foi disparado.
        if($Trigger -in @('Startup','Task')){exit 0}else{exit 13}
    }

    $state = Read-AutoRunnerState -Path $StatePath
    $configuredJobs = @($config.Jobs)
    if ($configuredJobs.Count -eq 0) {
        Write-RunnerLog 'Nenhum job configurado.' 'ERROR'
        $exitCode = 20
        throw 'Configuração sem jobs.'
    }
    $runtimeJobNames = @{}
    foreach ($configuredJob in $configuredJobs) {
        $runtimeName = ([string](Get-AutoRunnerPropertyValue -InputObject $configuredJob -Name 'Name' -Default '')).Trim()
        if ([string]::IsNullOrWhiteSpace($runtimeName) -or $runtimeName.Length -gt 250 -or $runtimeName -match '[\x00-\x1F\x7F]') { throw "Nome de job inválido na configuração: '$runtimeName'." }
        $runtimeKey = $runtimeName.ToLowerInvariant()
        if ($runtimeJobNames.ContainsKey($runtimeKey)) { throw "Job duplicado na configuração: '$runtimeName'." }
        $runtimeJobNames[$runtimeKey] = $true
        $runtimeBackupType = [string](Get-AutoRunnerPropertyValue -InputObject $configuredJob -Name 'BackupType' -Default 'Default')
        if ($runtimeBackupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')) { throw "Tipo de backup inválido para '$runtimeName': $runtimeBackupType" }
        if (-not (ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $configuredJob -Name 'ConfirmedByTechnician') -Default $false -Name 'ConfirmedByTechnician')) { throw "Job sem confirmação técnica: '$runtimeName'." }
    }
    # Pré-checagem individual. Evita aguardar serviços quando TODOS os jobs ainda estão
    # dentro do intervalo, mas não bloqueia um job novo ou um job que falhou anteriormente.
    if (-not $Force -and $Trigger -eq 'Startup' -and [int]$config.Execution.MinimumIntervalHours -gt 0) {
        $allWithinInterval = $true
        $preflightMessages = New-Object System.Collections.Generic.List[string]
        $preflightResults = New-Object System.Collections.Generic.List[object]
        foreach ($configuredJob in $configuredJobs) {
            $configuredName = [string]$configuredJob.Name
            if ([string]::IsNullOrWhiteSpace($configuredName)) { $allWithinInterval = $false; break }
            $artifact = Get-AutoRunnerJobArtifactName -JobName $configuredName
            $jobStatePath = Join-Path $jobStateDir ($artifact + '.json')
            $jobState = Read-JobStateSafe -Path $jobStatePath -JobName $configuredName
            if ($null -eq $jobState) { $allWithinInterval = $false; break }
            $jobInterval = Test-AutoRunnerMinimumInterval -State $jobState -MinimumIntervalHours ([int]$config.Execution.MinimumIntervalHours)
            if ($jobInterval.ShouldRun) { $allWithinInterval = $false; break }
            $preflightMessages.Add(("{0}: {1:hh\:mm\:ss}" -f $configuredName, $jobInterval.Remaining))
            $preflightResults.Add([pscustomobject][ordered]@{Name=$configuredName;BackupType=if($configuredJob.BackupType){[string]$configuredJob.BackupType}else{'Default'};Result='Ignorado pelo intervalo mínimo';ExitCode=12;Attempts=0;DurationSeconds=0;Message=('Restante aproximado {0:hh\:mm\:ss}.' -f $jobInterval.Remaining);CompletedAtUtc=[DateTime]::UtcNow.ToString('o');LastSuccessfulRunUtc=(Get-AutoRunnerPropertyValue -InputObject $jobState -Name 'LastSuccessfulRunUtc')})
        }
        if ($allWithinInterval) {
            Write-RunnerLog ('Todos os jobs foram ignorados pelo intervalo mínimo individual. Restante: ' + ($preflightMessages -join '; ')) 'INFO'
            $state.LastRunStartedUtc = [DateTime]::UtcNow.ToString('o')
            $state.LastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
            $state.LastResult = 'Todos os jobs ignorados pelo intervalo mínimo individual'
            $state.LastExitCode = 12
            $state.LastTrigger = $Trigger
            $state.Jobs = @($preflightResults)
            Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20
            exit 0
        }
    }

    $state.LastRunStartedUtc = [DateTime]::UtcNow.ToString('o')
    $state.LastRunCompletedUtc = $null
    $state.LastResult = 'Em execução'
    $state.LastExitCode = $null
    $state.LastTrigger = $Trigger
    $state.Jobs = @()
    Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20

    $cliPath = [string]$config.SqlBackupAndFTP.CliPath
    if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
        Write-RunnerLog ("CLI não encontrada: $cliPath") 'ERROR'
        $exitCode = 22
        throw 'Dependência ausente.'
    }
    $cliSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath $cliPath
    if(-not $cliSecurity.IsSafe){
        Write-RunnerLog ('CLI recusada por segurança: '+($cliSecurity.Issues -join '; ')) 'ERROR'
        $exitCode=23
        throw 'Diretório da CLI é gravável por identidade ampla ou contém reparse point.'
    }

    $serviceName = [string]$config.SqlBackupAndFTP.ServiceName
    if(-not [string]::IsNullOrWhiteSpace($serviceName) -and -not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)){
        try{
            $redetected=Get-SqlBackupAndFTPService -InstallDir ([string]$config.SqlBackupAndFTP.InstallDir)
            if($redetected){Write-RunnerLog ("Serviço configurado '$serviceName' não existe; usando detecção atual '$($redetected.Name)'.") 'WARN';$serviceName=[string]$redetected.Name}
            else{$serviceName=$null}
        }catch{$serviceName=$null}
    }
    if (-not [string]::IsNullOrWhiteSpace($serviceName)) {
        Write-RunnerLog ("Aguardando serviço SQLBackupAndFTP: $serviceName") 'INFO'
        if (-not (Wait-AutoRunnerService -Name $serviceName -TimeoutSeconds ([int]$config.Execution.ServiceWaitSeconds))) {
            Write-RunnerLog ("Serviço '$serviceName' não ficou disponível no prazo. Os jobs ainda serão tentados.") 'WARN'
        }
        else { Write-RunnerLog ("Serviço '$serviceName' em execução.") 'SUCCESS' }
    }
    else { Write-RunnerLog 'Serviço do SQLBackupAndFTP não foi identificado; prosseguindo pela CLI.' 'WARN' }

    $sqlWaitMode=[string]$config.Execution.SqlServiceWaitMode
    Write-RunnerLog ("Espera por SQL Server local: modo $sqlWaitMode.") 'INFO'
    if (-not (Wait-AutoRunnerSqlServices -TimeoutSeconds ([int]$config.Execution.SqlServiceWaitSeconds) -Mode $sqlWaitMode)) {
        Write-RunnerLog 'Os serviços SQL Server locais não atenderam ao modo configurado no prazo. Os jobs ainda serão tentados.' 'WARN'
    }

    try {
        $runtimeInstall = [pscustomobject]@{
            InstallDir = [string]$config.SqlBackupAndFTP.InstallDir
            CliPath = [string]$config.SqlBackupAndFTP.CliPath
            CliVersion = [string]$config.SqlBackupAndFTP.CliVersion
            AppPath = [string]$config.SqlBackupAndFTP.AppPath
            AppVersion = [string]$config.SqlBackupAndFTP.AppVersion
            ServiceName = [string]$config.SqlBackupAndFTP.ServiceName
            ServiceDisplayName = [string]$config.SqlBackupAndFTP.ServiceDisplayName
            ConfigRoot = [string]$config.SqlBackupAndFTP.ConfigRoot
        }
        $currentDiscovery = Get-SqlBakJobs -InstallInfo $runtimeInstall -DisableCliFallback
        if ($currentDiscovery.DiscoverySucceeded) {
            $currentNames = @($currentDiscovery.Jobs | ForEach-Object { [string]$_.Name })
            foreach ($configured in $configuredJobs) {
                if ([string]$configured.Name -notin $currentNames) {
                    Write-RunnerLog ("O job configurado '$($configured.Name)' não apareceu na descoberta atual. Ele pode ter sido renomeado ou removido; a CLI ainda será tentada.") 'WARN'
                }
            }
        }
        else { Write-RunnerLog ('Não foi possível validar os nomes atuais dos jobs: ' + ($currentDiscovery.Errors -join '; ')) 'WARN' }
    }
    catch { Write-RunnerLog ('Falha não bloqueante ao validar jobs atuais: ' + $_.Exception.Message) 'WARN' }

    if ($configuredJobs.Count -eq 0) {
        Write-RunnerLog 'Nenhum job configurado.' 'ERROR'
        $exitCode = 20
        throw 'Configuração sem jobs.'
    }

    $results = New-Object System.Collections.Generic.List[object]
    $processedJobKeys = @{}
    $retryCount = [int]$config.Execution.RetryCount
    $retryDelay = [int]$config.Execution.RetryDelayMinutes
    $retryOnCliError = ConvertTo-AutoRunnerBoolean -Value $config.Execution.RetryOnCliError -Default $false -Name 'RetryOnCliError'
    $stopOnFailure = ConvertTo-AutoRunnerBoolean -Value $config.Execution.StopOnFirstFailure -Default $false -Name 'StopOnFirstFailure'
    $postDelay = [int]$config.Execution.PostJobDelaySeconds

    Write-RunnerLog ("Política de repetição: novas tentativas=$retryCount; repetir em código não zero=$retryOnCliError; espera=$retryDelay min.") 'INFO'

    foreach ($job in $configuredJobs) {
        $jobName = [string]$job.Name
        if (-not [string]::IsNullOrWhiteSpace($jobName)) { $processedJobKeys[$jobName.Trim().ToLowerInvariant()] = $true }
        $backupType = if ($job.BackupType) { [string]$job.BackupType } else { 'Default' }
        if ([string]::IsNullOrWhiteSpace($jobName)) {
            $invalid = [pscustomobject]@{ Name='(vazio)'; Result='Falha'; ExitCode=20; Attempts=0; Message='Nome de job vazio'; CompletedAtUtc=[DateTime]::UtcNow.ToString('o') }
            $results.Add($invalid)
            Write-RunnerLog 'Job com nome vazio ignorado.' 'ERROR'
            if ($stopOnFailure) { break }
            continue
        }

        $jobArtifact = Get-AutoRunnerJobArtifactName -JobName $jobName
        $individualStatePath = Join-Path $jobStateDir ($jobArtifact + '.json')
        $previousJobState = Read-JobStateSafe -Path $individualStatePath -JobName $jobName
        if (-not $Force -and $Trigger -eq 'Startup' -and $previousJobState) {
            $jobInterval = Test-AutoRunnerMinimumInterval -State $previousJobState -MinimumIntervalHours ([int]$config.Execution.MinimumIntervalHours)
            if (-not $jobInterval.ShouldRun) {
                $skippedItem = [pscustomobject][ordered]@{
                    Name=$jobName; BackupType=$backupType; Result='Ignorado pelo intervalo mínimo'; ExitCode=12; Attempts=0; DurationSeconds=0
                    Message=('Último sucesso deste job ainda está dentro do intervalo; restante aproximado {0:hh\:mm\:ss}.' -f $jobInterval.Remaining)
                    CompletedAtUtc=[DateTime]::UtcNow.ToString('o'); LastSuccessfulRunUtc=(Get-AutoRunnerPropertyValue -InputObject $previousJobState -Name 'LastSuccessfulRunUtc')
                }
                $results.Add($skippedItem)
                Write-RunnerLog ("Job '$jobName' ignorado pelo intervalo mínimo individual. $($skippedItem.Message)") 'INFO'
                Write-AutoRunnerJsonAtomic -InputObject $skippedItem -Path $individualStatePath -CreateBackup -Depth 10
                $state.Jobs=@($results);Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20
                continue
            }
        }

        Write-RunnerLog ("Iniciando job '$jobName'. Tipo de backup: $backupType.") 'INFO'
        Write-JobLog -JobName $jobName -Message ("Início. Tipo de backup: $backupType.") -Level 'INFO'
        $success = $false
        $lastResult = $null
        $attempts = 0
        for ($attempt = 1; $attempt -le ($retryCount + 1); $attempt++) {
            $attempts = $attempt
            if ($attempt -gt 1) {
                Write-RunnerLog ("Nova tentativa $attempt para '$jobName' após $retryDelay minuto(s).") 'WARN'
                Start-Sleep -Seconds ($retryDelay * 60)
            }
            try {
                $lastResult = Invoke-SqlBakJobCli -CliPath $cliPath -JobName $jobName -BackupType $backupType
                foreach ($line in @($lastResult.Output)) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) { Write-RunnerLog ("[$jobName] $line") 'TRACE'; Write-JobLog -JobName $jobName -Message $line -Level 'TRACE' }
                }
                if ([int]$lastResult.ExitCode -eq 0) {
                    $success = $true
                    Write-RunnerLog ("CLI concluiu/aceitou o job '$jobName' sem erro. Confirme o resultado final no histórico do SQLBackupAndFTP.") 'SUCCESS'
                    Write-JobLog -JobName $jobName -Message 'CLI retornou código 0. Confirmar resultado definitivo no histórico do SQLBackupAndFTP.' -Level 'SUCCESS'
                    break
                }
                Write-RunnerLog ("CLI retornou código $($lastResult.ExitCode) para '$jobName'.") 'ERROR'
                Write-JobLog -JobName $jobName -Message ("CLI retornou código $($lastResult.ExitCode).") -Level 'ERROR'
                if(-not $retryOnCliError){
                    Write-RunnerLog ("Nova tentativa não será feita para '$jobName', pois RetryOnCliError está desabilitado. Isso reduz o risco de disparo duplicado após aceitação parcial pela CLI.") 'WARN'
                    break
                }
            }
            catch {
                Write-RunnerLog ("Exceção ao executar '$jobName': $($_.Exception.Message)") 'ERROR'
                Write-JobLog -JobName $jobName -Message $_.Exception.ToString() -Level 'ERROR'
                $lastResult = [pscustomobject]@{ ExitCode=98; Output=@($_.Exception.ToString()); DurationSeconds=0 }
            }
        }

        $resultItem = [pscustomobject][ordered]@{
            Name = $jobName
            BackupType = $backupType
            Result = if ($success) { 'CLI sem erro' } else { 'Falha' }
            ExitCode = if ($lastResult) { [int]$lastResult.ExitCode } else { 98 }
            Attempts = $attempts
            DurationSeconds = if ($lastResult) { $lastResult.DurationSeconds } else { 0 }
            Message = if ($success) { 'Consultar histórico do SQLBackupAndFTP para confirmação definitiva.' } else { 'Todas as tentativas falharam.' }
            CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
            LastSuccessfulRunUtc = if ($success) { [DateTime]::UtcNow.ToString('o') } elseif ($previousJobState) { Get-AutoRunnerPropertyValue -InputObject $previousJobState -Name 'LastSuccessfulRunUtc' } else { $null }
        }
        $results.Add($resultItem)
        Write-AutoRunnerJsonAtomic -InputObject $resultItem -Path $individualStatePath -CreateBackup -Depth 10
        $state.Jobs = @($results)
        Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20

        if (-not $success -and $stopOnFailure) {
            Write-RunnerLog 'Execução interrompida pela opção Parar após primeira falha.' 'WARN'
            break
        }
        if ($postDelay -gt 0) { Start-Sleep -Seconds $postDelay }
    }

    if ($stopOnFailure -and @($results | Where-Object { $_.Result -eq 'Falha' }).Count -gt 0) {
        foreach ($pendingJob in $configuredJobs) {
            $pendingName = ([string]$pendingJob.Name).Trim()
            if ([string]::IsNullOrWhiteSpace($pendingName)) { continue }
            if (-not $processedJobKeys.ContainsKey($pendingName.ToLowerInvariant())) {
                $results.Add([pscustomobject][ordered]@{
                    Name=$pendingName; BackupType=if($pendingJob.BackupType){[string]$pendingJob.BackupType}else{'Default'}
                    Result='Não executado após falha anterior'; ExitCode=14; Attempts=0; DurationSeconds=0
                    Message='Execução interrompida pela política Parar após primeira falha.'
                    CompletedAtUtc=[DateTime]::UtcNow.ToString('o'); LastSuccessfulRunUtc=$null
                })
            }
        }
    }

    $successCount = @($results | Where-Object { $_.Result -eq 'CLI sem erro' }).Count
    $failureCount = @($results | Where-Object { $_.Result -eq 'Falha' }).Count
    $skippedCount = @($results | Where-Object { $_.Result -eq 'Ignorado pelo intervalo mínimo' }).Count
    $notRunCount = @($results | Where-Object { $_.Result -eq 'Não executado após falha anterior' }).Count
    $state.Jobs = @($results)
    $state.LastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
    $state.LastTrigger = $Trigger

    if ($failureCount -eq 0 -and $successCount -gt 0) {
        $state.LastSuccessfulRunUtc = [DateTime]::UtcNow.ToString('o')
        $state.LastResult = "CLI sem erro em $successCount job(s); $skippedCount ignorado(s) por intervalo"
        $state.LastExitCode = 0
        $exitCode = 0
        Write-RunnerLog ("Execução finalizada. $successCount job(s) sem erro de CLI e $skippedCount ignorado(s) por intervalo. Verifique o histórico do SQLBackupAndFTP.") 'SUCCESS'
    }
    elseif ($failureCount -eq 0 -and $successCount -eq 0 -and $skippedCount -gt 0) {
        $state.LastResult = "Todos os $skippedCount job(s) foram ignorados pelo intervalo mínimo"
        $state.LastExitCode = 12
        $exitCode = 0
        Write-RunnerLog ($state.LastResult) 'INFO'
    }
    elseif ($successCount -gt 0 -and $failureCount -gt 0) {
        $state.LastResult = "Falha parcial: $successCount sucesso(s), $failureCount falha(s), $notRunCount não executado(s)"
        $state.LastExitCode = 10
        $exitCode = 10
        Write-RunnerLog ($state.LastResult) 'ERROR'
    }
    else {
        $state.LastResult = "Falha: $failureCount job(s), $notRunCount não executado(s)"
        $state.LastExitCode = 11
        $exitCode = 11
        Write-RunnerLog ($state.LastResult) 'ERROR'
    }
    Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20
}
catch {
    Write-BootstrapLog -Message $_.Exception.ToString() -Level 'ERROR'
    try {
        if (Get-Command Write-RunnerLog -ErrorAction SilentlyContinue) { Write-RunnerLog $_.Exception.ToString() 'ERROR' }
        if (Get-Variable state -ErrorAction SilentlyContinue) {
            $state.LastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
            $state.LastResult = 'Erro inesperado: ' + $_.Exception.Message
            $state.LastExitCode = $exitCode
            Write-AutoRunnerJsonAtomic -InputObject $state -Path $StatePath -CreateBackup -Depth 20
        }
    } catch {}
    if ($exitCode -eq 99) { $exitCode = 99 }
}
finally {
    if ($hasMutex -and $mutex) { try { $mutex.ReleaseMutex() } catch {} }
    if ($mutex) { $mutex.Dispose() }
}
exit $exitCode
