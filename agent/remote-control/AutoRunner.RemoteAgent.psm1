Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AgentRegistry = 'HKLM:\SOFTWARE\Alpha Software\SQLBackupAndFTP AutoRunner\RemoteAgent'
$script:AgentTaskName = 'SQLBackupAndFTP AutoRunner Remote Agent'
$script:AgentTaskPath = '\Alpha Software\'
$script:ProtocolVersion = 1
$script:MaxMessageBytes = 1024 * 1024
$script:CommandCacheLimit = 200

function Get-RemoteAgentRoot {
    $root = Join-Path $env:ProgramData 'SQLBackupAndFTPAuto\remote-agent'
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    return $root
}

function Get-RemoteAgentConfigPath { Join-Path (Get-RemoteAgentRoot) 'agent.json' }
function Get-RemoteAgentCommandCachePath { Join-Path (Get-RemoteAgentRoot) 'command-cache.json' }

function Protect-RemoteAgentIdentityRegistry {
    if (-not (Test-Path -LiteralPath $script:AgentRegistry)) { New-Item -Path $script:AgentRegistry -Force | Out-Null }
    $acl = Get-Acl -LiteralPath $script:AgentRegistry -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    try { $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))) } catch {}
    foreach ($existing in @($acl.Access)) { try { [void]$acl.RemoveAccessRuleSpecific($existing) } catch {} }
    foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.RegistryAccessRule(
            $sid,
            [Security.AccessControl.RegistryRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:AgentRegistry -AclObject $acl -ErrorAction Stop
}

function Assert-AgentEndpointSecurity {
    param([string]$BaseUrl, [switch]$AllowInsecureTransport)
    try { $uri = New-Object Uri $BaseUrl } catch { throw 'URL do Control Plane inválida.' }
    if (-not $uri.IsAbsoluteUri) { throw 'URL do Control Plane deve ser absoluta.' }
    $isLocal = ($uri.Host -in @('localhost', '127.0.0.1', '::1'))
    if ($uri.Scheme -notin @('https', 'http')) { throw 'URL do Control Plane deve usar http:// ou https://.' }
    if ($uri.Scheme -ne 'https' -and -not $isLocal -and -not $AllowInsecureTransport) {
        throw 'O Control Plane exige HTTPS fora de localhost. Use -AllowInsecureTransport somente em homologação isolada.'
    }
    return $uri
}

function Test-AgentWebSocketUrl {
    param([string]$WsUrl, [switch]$AllowInsecureTransport)
    try { $uri = New-Object Uri $WsUrl } catch { throw 'URL WebSocket retornada pelo Control Plane é inválida.' }
    $isLocal = ($uri.Host -in @('localhost', '127.0.0.1', '::1'))
    if ($uri.Scheme -notin @('wss', 'ws')) { throw 'URL do agente deve usar ws:// ou wss://.' }
    if ($uri.Scheme -ne 'wss' -and -not $isLocal -and -not $AllowInsecureTransport) { throw 'WebSocket do agente exige WSS fora de localhost.' }
    return $uri
}

function Get-RemoteAgentCoreModule { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'modules\AutoRunner.Core.psm1' }
function Import-RemoteAgentCore {
    $path = Get-RemoteAgentCoreModule
    if (-not (Test-Path -LiteralPath $path)) { throw "AutoRunner.Core.psm1 não encontrado: $path" }
    Import-Module $path -Force -DisableNameChecking
}

function ConvertTo-AgentBase64Url([byte[]]$Bytes) { [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function ConvertFrom-AgentBase64Url([string]$Text) {
    $value = $Text.Replace('-', '+').Replace('_', '/')
    switch ($value.Length % 4) { 2 { $value += '==' } 3 { $value += '=' } }
    [Convert]::FromBase64String($value)
}
function Protect-AgentSecret([string]$Plain) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Plain)
    $protected = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    ConvertTo-AgentBase64Url $protected
}
function Unprotect-AgentSecret([string]$Cipher) {
    $bytes = ConvertFrom-AgentBase64Url $Cipher
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [Text.Encoding]::UTF8.GetString($plain)
}

function Get-RemoteAgentIdentity {
    if (-not (Test-Path -LiteralPath $script:AgentRegistry)) { return $null }
    $row = Get-ItemProperty -Path $script:AgentRegistry -ErrorAction SilentlyContinue
    if (-not $row) { return $null }
    $secret = ''
    try { $secret = Unprotect-AgentSecret ([string]$row.SecretProtected) } catch {}
    if ([string]::IsNullOrWhiteSpace($secret)) { return $null }
    [pscustomobject]@{
        AgentId = [string]$row.AgentId
        Secret = $secret
        InstallId = [string]$row.InstallId
        BaseUrl = [string]$row.BaseUrl
        WsUrl = [string]$row.WsUrl
        MachineId = [string]$row.MachineId
        AllowInsecureTransport = ([string]$row.AllowInsecureTransport -eq '1')
    }
}

function Save-RemoteAgentIdentity($Identity) {
    New-Item -Path $script:AgentRegistry -Force | Out-Null
    Protect-RemoteAgentIdentityRegistry
    $values = @{
        AgentId = [string]$Identity.AgentId
        SecretProtected = Protect-AgentSecret ([string]$Identity.Secret)
        InstallId = [string]$Identity.InstallId
        BaseUrl = [string]$Identity.BaseUrl
        WsUrl = [string]$Identity.WsUrl
        MachineId = [string]$Identity.MachineId
        AllowInsecureTransport = $(if ($Identity.AllowInsecureTransport) { '1' } else { '0' })
    }
    foreach ($name in $values.Keys) { New-ItemProperty -Path $script:AgentRegistry -Name $name -Value $values[$name] -PropertyType String -Force | Out-Null }
    Protect-RemoteAgentIdentityRegistry
}

function Get-OrCreateRemoteInstallId {
    try {
        $row = Get-ItemProperty -Path $script:AgentRegistry -Name InstallId -ErrorAction Stop
        if ($row.InstallId) { return [string]$row.InstallId }
    } catch {}
    $value = [Guid]::NewGuid().ToString()
    New-Item -Path $script:AgentRegistry -Force | Out-Null
    Protect-RemoteAgentIdentityRegistry
    New-ItemProperty -Path $script:AgentRegistry -Name InstallId -Value $value -PropertyType String -Force | Out-Null
    return $value
}

function Get-AgentStableMachineKey {
    try {
        $guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($guid) { return [string]$guid }
    } catch {}
    return ($env:COMPUTERNAME + '-' + (Get-OrCreateRemoteInstallId))
}

function Get-AgentCapabilities {
    [ordered]@{
        jobList = $true; jobRun = $true; jobRunBackupType = $true; inventoryRefresh = $true
        diagnostics = $true; commandCancel = $true; agentUpdate = $false
        jobCreate = $false; jobUpdate = $false; jobDelete = $false
    }
}

function Get-AgentMachineInfo {
    [ordered]@{
        stableKey = Get-AgentStableMachineKey
        displayName = $env:COMPUTERNAME
        hostname = $env:COMPUTERNAME
        osName = [Environment]::OSVersion.Platform.ToString()
        osVersion = [Environment]::OSVersion.VersionString
        architecture = $env:PROCESSOR_ARCHITECTURE
        metadata = @{ domain = $env:USERDOMAIN }
    }
}

function Convert-AgentConfidence($Value) {
    switch -Regex ([string]$Value) { 'High' { 90 } 'Medium' { 65 } 'Low' { 35 } default { 50 } }
}

function Get-RemoteAgentInventory {
    Import-RemoteAgentCore
    $install = $null; $discovery = $null; $jobs = @()
    try {
        $all = @(Find-SqlBackupAndFTPInstallations -Quick)
        if ($all.Count -eq 0) { $all = @(Find-SqlBackupAndFTPInstallations -DeepSearch) }
        if ($all.Count -gt 0) { $install = $all[0] }
    } catch {}
    if ($install) { try { $discovery = Get-SqlBakJobs -InstallInfo $install; $jobs = @($discovery.Jobs) } catch {} }
    $mapped = @()
    foreach ($job in $jobs) {
        $stable = if ($job.Id) { [string]$job.Id } else { [string]$job.Name }
        $mapped += [ordered]@{
            stableKey = $stable; nativeJobId = $(if ($job.Id) { [string]$job.Id } else { $null }); name = [string]$job.Name
            jobType = [string]$job.Type; isScheduled = $job.IsScheduled; scheduleState = $null; lastNativeRunAt = $job.LastRunAt
            source = [string]$job.Source; confidence = Convert-AgentConfidence $job.Confidence; databases = @(); destinations = @()
            metadata = @{ selectable = $job.Selectable; rawType = $job.RawType }
        }
    }
    $sqlBackup = [ordered]@{ present = $false }
    if ($install) {
        $sqlBackup = [ordered]@{
            present = $true; installPath = [string]$install.InstallDir; appVersion = [string]$install.AppVersion; cliVersion = [string]$install.CliVersion
            serviceName = [string]$install.ServiceName; serviceStatus = [string]$install.ServiceDisplayName
            discoverySource = [string](@($install.Sources) -join '; '); discoveryConfidence = [int]$install.Score
            raw = @{ configRoot = $(if ($discovery) { $discovery.ConfigRoot } else { $null }) }
        }
    }
    [ordered]@{ inventoryComplete = $true; machine = Get-AgentMachineInfo; capabilities = Get-AgentCapabilities; sqlBackup = $sqlBackup; jobs = $mapped }
}

function New-AgentEnvelope([string]$Type, $Payload, [string]$CorrelationId = $null) {
    [ordered]@{ protocolVersion = $script:ProtocolVersion; messageId = [Guid]::NewGuid().ToString(); type = $Type; sentAt = (Get-Date).ToUniversalTime().ToString('o'); correlationId = $CorrelationId; payload = $Payload }
}

function Send-AgentEnvelope($Socket, $Envelope, [int]$TimeoutMilliseconds = 15000) {
    $json = $Envelope | ConvertTo-Json -Depth 15 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    if ($bytes.Length -gt $script:MaxMessageBytes) { throw 'Envelope excede o limite local de tamanho.' }
    $segment = New-Object ArraySegment[byte] -ArgumentList (,$bytes)
    $cts = New-Object Threading.CancellationTokenSource
    $cts.CancelAfter($TimeoutMilliseconds)
    try { $Socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult() | Out-Null }
    finally { $cts.Dispose() }
}

function Receive-AgentEnvelope($Socket, [int]$TimeoutMilliseconds = 1000) {
    $buffer = New-Object byte[] 65536
    $stream = New-Object IO.MemoryStream
    $cts = New-Object Threading.CancellationTokenSource
    $cts.CancelAfter($TimeoutMilliseconds)
    try {
        do {
            $segment = New-Object ArraySegment[byte] -ArgumentList (,$buffer)
            try { $result = $Socket.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult() }
            catch [OperationCanceledException] { return $null }
            catch [Threading.Tasks.TaskCanceledException] { return $null }
            if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'WebSocket fechado pelo servidor.' }
            if (($stream.Length + $result.Count) -gt $script:MaxMessageBytes) { throw 'Mensagem WebSocket excede o limite local.' }
            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)
        $text = [Text.Encoding]::UTF8.GetString($stream.ToArray())
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } finally { $cts.Dispose(); $stream.Dispose() }
}

function Read-AgentCommandCache {
    $path = Get-RemoteAgentCommandCachePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    try { return @((Get-Content -LiteralPath $path -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop) } catch { return @() }
}

function Get-CachedAgentCommand([string]$CommandId) {
    $matches = @((Read-AgentCommandCache) | Where-Object { [string]$_.commandId -eq $CommandId })
    if ($matches.Count -eq 0) { return $null }
    return $matches[$matches.Count - 1]
}

function Save-CachedAgentCommand([string]$CommandId, [string]$Type, $CompletedPayload, $ExecutionPayload = $null) {
    $records = @(Read-AgentCommandCache | Where-Object { [string]$_.commandId -ne $CommandId })
    $records += [pscustomobject]@{ commandId = $CommandId; type = $Type; completedPayload = $CompletedPayload; executionPayload = $ExecutionPayload; completedAt = (Get-Date).ToUniversalTime().ToString('o') }
    if ($records.Count -gt $script:CommandCacheLimit) { $records = @($records | Select-Object -Last $script:CommandCacheLimit) }
    $path = Get-RemoteAgentCommandCachePath
    $temp = $path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp, ($records | ConvertTo-Json -Depth 15), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Replay-CachedAgentCommand($Socket, $Cached) {
    if (-not $Cached) { return $false }
    $commandId = [string]$Cached.commandId
    if ($Cached.executionPayload) { Send-AgentEnvelope $Socket (New-AgentEnvelope 'execution.completed' $Cached.executionPayload $commandId) }
    Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $Cached.completedPayload $commandId)
    return $true
}

function Invoke-AgentEnrollment {
    [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$BaseUrl, [Parameter(Mandatory = $true)][string]$Token, [switch]$AllowInsecureTransport)
    Import-RemoteAgentCore
    [void](Assert-AgentEndpointSecurity -BaseUrl $BaseUrl -AllowInsecureTransport:$AllowInsecureTransport)
    $installId = Get-OrCreateRemoteInstallId
    $base = $BaseUrl.TrimEnd('/')
    $body = [ordered]@{ token = $Token; installId = $installId; agentVersion = (Get-AutoRunnerDisplayVersion).Replace(' ', '-'); channel = Get-AutoRunnerReleaseChannel; protocolVersion = $script:ProtocolVersion; machine = Get-AgentMachineInfo; capabilities = Get-AgentCapabilities }
    $result = Invoke-RestMethod -Method Post -Uri ($base + '/api/v1/agent/enroll') -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 10 -Compress)
    $identity = [pscustomobject]@{ AgentId = [string]$result.agentId; Secret = [string]$result.secret; InstallId = $installId; BaseUrl = $base; WsUrl = [string]$result.wsUrl; MachineId = [string]$result.machineId; AllowInsecureTransport = [bool]$AllowInsecureTransport }
    [void](Test-AgentWebSocketUrl -WsUrl $identity.WsUrl -AllowInsecureTransport:$AllowInsecureTransport)
    Save-RemoteAgentIdentity $identity
    $cfg = [ordered]@{ schemaVersion = 1; agentId = $identity.AgentId; machineId = $identity.MachineId; baseUrl = $base; wsUrl = $identity.WsUrl; allowInsecureTransport = [bool]$AllowInsecureTransport; enrolledAt = (Get-Date).ToUniversalTime().ToString('o') }
    [IO.File]::WriteAllText((Get-RemoteAgentConfigPath), ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    return $identity
}

function Install-RemoteAgentTask {
    [CmdletBinding()] param()
    $scriptPath = Join-Path $PSScriptRoot 'AutoRunner.RemoteAgent.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '" -Run')
    $trigger = New-ScheduledTaskTrigger -AtStartup; $trigger.Delay = 'PT45S'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $script:AgentTaskName -TaskPath $script:AgentTaskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $script:AgentTaskName -TaskPath $script:AgentTaskPath -ErrorAction SilentlyContinue
}

function Uninstall-RemoteAgentTask {
    Unregister-ScheduledTask -TaskName $script:AgentTaskName -TaskPath $script:AgentTaskPath -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:AgentRegistry) { Remove-Item $script:AgentRegistry -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($path in @((Get-RemoteAgentConfigPath), (Get-RemoteAgentCommandCachePath))) { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
}

function Start-AgentJobExecution($Command) {
    Import-RemoteAgentCore
    $inventory = Get-RemoteAgentInventory
    if (-not $inventory.sqlBackup.present) { throw 'SQLBackupAndFTP não encontrado.' }
    $cli = Join-Path ([string]$inventory.sqlBackup.installPath) 'SqlBak.Job.Cli.exe'
    if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'SqlBak.Job.Cli.exe não encontrado.' }
    $payload = $Command.payload.payload
    $jobName = [string]$payload.jobName
    if ([string]::IsNullOrWhiteSpace($jobName)) { throw 'Nome do job ausente no comando.' }
    $backupType = [string]$payload.backupType
    if ([string]::IsNullOrWhiteSpace($backupType)) { $backupType = 'Default' }
    if ($backupType -notin @('Default', 'Full', 'FullCopy', 'Diff', 'TranLog', 'TranLogCopy')) { throw 'Tipo de backup inválido.' }
    return Start-Job -ScriptBlock {
        param($module, $cliPath, $name, $bt)
        Import-Module $module -Force -DisableNameChecking
        Invoke-SqlBakJobCli -CliPath $cliPath -JobName $name -BackupType $bt
    } -ArgumentList (Get-RemoteAgentCoreModule), $cli, $jobName, $backupType
}

function Complete-RunningAgentJobs($Socket, $Running) {
    foreach ($key in @($Running.Keys)) {
        $entry = $Running[$key]
        if ($entry.Job.State -notin @('Completed', 'Failed', 'Stopped')) { continue }
        $result = $null; $errorText = $null
        try { $result = Receive-Job $entry.Job -ErrorAction Stop | Select-Object -Last 1 } catch { $errorText = $_.Exception.Message }
        $status = 'failed'
        if ($entry.Job.State -eq 'Completed' -and $result -and [int]$result.ExitCode -eq 0) { $status = 'succeeded' }
        elseif ($entry.Job.State -eq 'Stopped') { $status = 'cancelled' }
        $completed = Get-Date
        $summary = if ($errorText) { $errorText } elseif ($result) { (@($result.Output) -join "`n") } else { $status }
        $executionPayload = [ordered]@{
            commandId = $key; executionId = $entry.ExecutionId; jobId = $entry.JobId; status = $status
            completedAt = $completed.ToUniversalTime().ToString('o'); durationSeconds = [math]::Round(($completed - $entry.Started).TotalSeconds, 2)
            exitCode = $(if ($result) { [int]$result.ExitCode } else { $null }); summary = $summary; cliOutput = $(if ($result) { @($result.Output) -join "`n" } else { '' })
        }
        $completedPayload = [ordered]@{
            commandId = $key; status = $status; success = ($status -eq 'succeeded')
            result = @{ executionId = $entry.ExecutionId; exitCode = $executionPayload.exitCode }
            errorCode = $(if ($status -eq 'succeeded') { $null } elseif ($status -eq 'cancelled') { 'COMMAND_CANCELLED' } else { 'SQLBAK_JOB_FAILED' })
            errorSummary = $(if ($status -eq 'succeeded') { $null } else { $summary })
        }
        Send-AgentEnvelope $Socket (New-AgentEnvelope 'execution.completed' $executionPayload $key)
        Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $completedPayload $key)
        Save-CachedAgentCommand -CommandId $key -Type 'executeJob' -CompletedPayload $completedPayload -ExecutionPayload $executionPayload
        Remove-Job $entry.Job -Force -ErrorAction SilentlyContinue
        $Running.Remove($key)
    }
}

function Process-AgentCommand($Socket, $Message, $Running) {
    $cmd = $Message.payload; $commandId = [string]$cmd.commandId
    if ([string]::IsNullOrWhiteSpace($commandId)) { return }
    if ($Running.ContainsKey($commandId)) {
        Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.accepted' @{ commandId = $commandId } $commandId)
        Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.progress' @{ commandId = $commandId; progress = $null; state = 'running' } $commandId)
        return
    }
    $cached = Get-CachedAgentCommand $commandId
    if ($cached) { [void](Replay-CachedAgentCommand $Socket $cached); return }
    try {
        switch ([string]$Message.type) {
            'command.executeJob' {
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.accepted' @{ commandId = $commandId } $commandId)
                $execId = [Guid]::NewGuid().ToString()
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'execution.started' @{ commandId = $commandId; executionId = $execId; jobId = $cmd.jobId; backupType = $cmd.payload.backupType; startedAt = (Get-Date).ToUniversalTime().ToString('o') } $commandId)
                $job = Start-AgentJobExecution $Message
                $Running[$commandId] = [pscustomobject]@{ Job = $job; ExecutionId = $execId; JobId = $cmd.jobId; Started = Get-Date }
            }
            'command.refreshInventory' {
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.accepted' @{ commandId = $commandId } $commandId)
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'inventory.snapshot' (Get-RemoteAgentInventory) $commandId)
                $done = [ordered]@{ commandId = $commandId; status = 'succeeded'; success = $true; result = @{ refreshed = $true } }
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $done $commandId)
                Save-CachedAgentCommand $commandId 'refreshInventory' $done
            }
            'command.collectDiagnostics' {
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.accepted' @{ commandId = $commandId } $commandId)
                $diag = Export-AutoRunnerDiagnostics -DestinationDirectory (Get-RemoteAgentRoot)
                $summary = @{ path = [IO.Path]::GetFileName($diag); size = (Get-Item $diag).Length; note = 'Arquivo permanece local nesta RC; resumo enviado ao Control Plane.' }
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'diagnostic.completed' @{ commandId = $commandId; summary = $summary; payload = @{} } $commandId)
                $done = [ordered]@{ commandId = $commandId; status = 'succeeded'; success = $true; result = $summary }
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $done $commandId)
                Save-CachedAgentCommand $commandId 'collectDiagnostics' $done
            }
            'command.cancel' {
                $target = [string]$cmd.payload.targetCommandId
                if ($Running.ContainsKey($target)) {
                    Stop-Job $Running[$target].Job -ErrorAction SilentlyContinue
                    $done = [ordered]@{ commandId = $commandId; status = 'succeeded'; success = $true; result = @{ cancelled = $target } }
                } else {
                    $done = [ordered]@{ commandId = $commandId; status = 'failed'; success = $false; errorCode = 'TARGET_NOT_RUNNING'; errorSummary = 'Comando alvo não está em execução.' }
                }
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $done $commandId)
                Save-CachedAgentCommand $commandId 'cancel' $done
            }
            'command.updateAgent' {
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.rejected' @{ commandId = $commandId; errorCode = 'CAPABILITY_DISABLED'; errorSummary = 'Atualização remota do agente está desabilitada nesta RC.' } $commandId)
            }
            default {
                Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.rejected' @{ commandId = $commandId; errorCode = 'UNSUPPORTED_COMMAND'; errorSummary = 'Comando não suportado.' } $commandId)
            }
        }
    } catch {
        $done = [ordered]@{ commandId = $commandId; status = 'failed'; success = $false; errorCode = 'AGENT_COMMAND_ERROR'; errorSummary = $_.Exception.Message }
        Send-AgentEnvelope $Socket (New-AgentEnvelope 'command.completed' $done $commandId)
        Save-CachedAgentCommand $commandId 'error' $done
    }
}

function Start-RemoteAgentLoop {
    [CmdletBinding()] param()
    Import-RemoteAgentCore
    $identity = Get-RemoteAgentIdentity
    if (-not $identity) { throw 'Agente ainda não matriculado. Execute -Enroll primeiro.' }
    [void](Assert-AgentEndpointSecurity -BaseUrl $identity.BaseUrl -AllowInsecureTransport:$identity.AllowInsecureTransport)
    [void](Test-AgentWebSocketUrl -WsUrl $identity.WsUrl -AllowInsecureTransport:$identity.AllowInsecureTransport)
    $backoff = 2
    $running = @{}
    while ($true) {
        $socket = $null
        try {
            $socket = New-Object Net.WebSockets.ClientWebSocket
            $socket.Options.SetRequestHeader('Authorization', ('Agent ' + $identity.AgentId + '.' + $identity.Secret))
            $socket.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
            $uri = New-Object Uri $identity.WsUrl
            $socket.ConnectAsync($uri, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
            $backoff = 2
            Send-AgentEnvelope $socket (New-AgentEnvelope 'hello' ([ordered]@{ version = (Get-AutoRunnerDisplayVersion).Replace(' ', '-'); channel = Get-AutoRunnerReleaseChannel; capabilities = Get-AgentCapabilities }))
            Send-AgentEnvelope $socket (New-AgentEnvelope 'inventory.snapshot' (Get-RemoteAgentInventory))
            $lastHeartbeat = Get-Date
            while ($socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
                if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 25) {
                    Send-AgentEnvelope $socket (New-AgentEnvelope 'heartbeat' ([ordered]@{ uptimeSeconds = [Environment]::TickCount / 1000 }))
                    $lastHeartbeat = Get-Date
                }
                Complete-RunningAgentJobs -Socket $socket -Running $running
                $msg = Receive-AgentEnvelope $socket 750
                if ($msg -and ([string]$msg.type).StartsWith('command.')) { Process-AgentCommand -Socket $socket -Message $msg -Running $running }
            }
        } catch {
            Start-Sleep -Seconds ($backoff + (Get-Random -Minimum 0 -Maximum 3))
            $backoff = [Math]::Min(60, $backoff * 2)
        } finally {
            if ($socket) { try { $socket.Dispose() } catch {} }
        }
    }
}

Export-ModuleMember -Function *
