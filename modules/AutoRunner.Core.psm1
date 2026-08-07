Set-StrictMode -Version 2.0

$script:AutoRunnerVersion = '3.0.0'
$script:AutoRunnerReleaseChannel = 'RC'
$script:ConfigSchemaVersion = 6
$script:DefaultSupportDir = Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'
$script:DefaultTaskName = 'SQLBackupAndFTP AutoRunner'
$script:DefaultTaskPath = '\SQLBackupAndFTPAuto\'

function Get-AutoRunnerVersion { return $script:AutoRunnerVersion }
function Get-AutoRunnerReleaseChannel { return $script:AutoRunnerReleaseChannel }
function Get-AutoRunnerDisplayVersion {
    if ([string]::IsNullOrWhiteSpace($script:AutoRunnerReleaseChannel) -or $script:AutoRunnerReleaseChannel -ieq 'Stable') { return $script:AutoRunnerVersion }
    return ($script:AutoRunnerVersion + ' ' + $script:AutoRunnerReleaseChannel)
}
function Get-AutoRunnerSchemaVersion { return $script:ConfigSchemaVersion }
function Get-AutoRunnerDefaultSupportDir { return $script:DefaultSupportDir }
function Get-AutoRunnerDefaultTaskName { return $script:DefaultTaskName }
function Get-AutoRunnerDefaultTaskPath { return $script:DefaultTaskPath }

$script:UserRegistryPath = 'HKCU:\Software\Alpha Software\SQLBackupAndFTP AutoRunner'
$script:MachineRegistryPath = 'HKLM:\Software\Alpha Software\SQLBackupAndFTP AutoRunner'

function Get-AutoRunnerUserRegistryPath { return $script:UserRegistryPath }
function Get-AutoRunnerMachineRegistryPath { return $script:MachineRegistryPath }

function Get-AutoRunnerApplicationInstallDir {
    [CmdletBinding()]
    param()
    if (-not (Test-AutoRunnerIsWindows)) { return $null }
    foreach ($key in @($script:MachineRegistryPath,$script:UserRegistryPath)) {
        try {
            $item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $path=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'ApplicationInstallDir' -Default '')
            if($path -and (Test-Path -LiteralPath $path -PathType Container)){return [IO.Path]::GetFullPath($path).TrimEnd('\')}
        } catch {}
    }
    return $null
}

function Get-AutoRunnerApplicationRegistration {
    [CmdletBinding()]
    param()
    $defaults=[ordered]@{
        IsRegistered=$false
        InstallDir=''
        Version=''
        SetupPath=''
        InstallTechnology='EXE'
        MsiProductCode=''
    }
    if(-not(Test-AutoRunnerIsWindows)){return [pscustomobject]$defaults}
    foreach($key in @($script:MachineRegistryPath,$script:UserRegistryPath)){
        try{
            $item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $defaults.IsRegistered=$true
            $defaults.InstallDir=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'ApplicationInstallDir' -Default '')
            $defaults.Version=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'ApplicationVersion' -Default '')
            $defaults.SetupPath=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'SetupPath' -Default '')
            $technology=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'InstallTechnology' -Default 'EXE')
            $defaults.InstallTechnology=if($technology -ieq 'MSI'){'MSI'}else{'EXE'}
            $defaults.MsiProductCode=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'MsiProductCode' -Default '')
            break
        }catch{}
    }
    return [pscustomobject]$defaults
}

function Test-AutoRunnerApplicationMaintenanceAvailable {
    [CmdletBinding()]
    param()
    $registration=Get-AutoRunnerApplicationRegistration
    if(-not $registration.IsRegistered){return $false}
    if($registration.InstallTechnology -eq 'MSI'){
        return ([string]$registration.MsiProductCode -match '^\{[0-9A-Fa-f-]{36}\}$')
    }
    return (-not [string]::IsNullOrWhiteSpace([string]$registration.SetupPath) -and (Test-Path -LiteralPath $registration.SetupPath -PathType Leaf))
}

function Start-AutoRunnerApplicationMaintenance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Repair','Uninstall')][string]$Action)
    if(-not(Test-AutoRunnerIsWindows)){throw 'Manutenção do aplicativo disponível somente no Windows.'}
    $registration=Get-AutoRunnerApplicationRegistration
    if(-not $registration.IsRegistered){throw 'Registro da instalação do AutoRunner não encontrado.'}
    if($registration.InstallTechnology -eq 'MSI'){
        $productCode=[string]$registration.MsiProductCode
        if($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$'){throw 'ProductCode do MSI ausente ou inválido.'}
        $arguments=if($Action -eq 'Repair'){@('/fa',$productCode)}else{@('/x',$productCode)}
        return Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList (Join-AutoRunnerProcessArguments -Arguments $arguments) -PassThru
    }
    $setup=[string]$registration.SetupPath
    if([string]::IsNullOrWhiteSpace($setup) -or -not(Test-Path -LiteralPath $setup -PathType Leaf)){throw 'Instalador local não encontrado.'}
    $executionSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath $setup -AllowProductFullControlPolicy
    if(-not $executionSecurity.IsSafe){throw ('O instalador local está em caminho inseguro: '+($executionSecurity.Issues -join '; '))}
    # O Setup-Wizard elevado detecta que este executável está dentro da instalação,
    # cria uma cópia em TEMP com ACL exclusiva e relança a manutenção. Não copiamos
    # para LOCALAPPDATA antes da elevação, evitando uma janela TOCTOU privilegiada.
    $argument=if($Action -eq 'Repair'){'/repair'}else{'/uninstall'}
    return Start-Process -FilePath $setup -ArgumentList $argument -Verb RunAs -PassThru
}
function Get-AutoRunnerLauncherPath {
    [CmdletBinding()]
    param()
    $dir=Get-AutoRunnerApplicationInstallDir
    if($dir){
        $launcher=Join-Path $dir 'SQLBackupAndFTP-AutoRunner.exe'
        if(Test-Path -LiteralPath $launcher -PathType Leaf){return $launcher}
    }
    return $null
}

function Get-AutoRunnerSetupPath {
    [CmdletBinding()]
    param()
    if (-not (Test-AutoRunnerIsWindows)) { return $null }
    foreach ($key in @($script:MachineRegistryPath,$script:UserRegistryPath)) {
        try {
            $item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $path=[string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'SetupPath' -Default '')
            if($path -and (Test-Path -LiteralPath $path -PathType Leaf)){return $path}
        } catch {}
    }
    $dir=Get-AutoRunnerApplicationInstallDir
    if($dir){$path=Join-Path $dir 'SQLBackupAndFTP-AutoRunner-Setup.exe';if(Test-Path -LiteralPath $path -PathType Leaf){return $path}}
    return $null
}

function Get-AutoRunnerUserSettings {
    [CmdletBinding()]
    param()
    $defaults = [ordered]@{
        PreferredSqlBackupPath = ''
        PreferredSqlBackupCliPath = ''
        PreferredSqlBackupAppPath = ''
        DetectionSource = ''
        DetectionUpdatedUtc = ''
        TutorialCompleted = $false
        TutorialDoNotShowAgain = $false
        TutorialVersion = ''
        UpdateCheckEnabled = $true
        LastUpdateCheckUtc = ''
        SkippedUpdateTag = ''
    }
    if (-not (Test-AutoRunnerIsWindows)) { return [pscustomobject]$defaults }
    try {
        $item = Get-ItemProperty -LiteralPath $script:UserRegistryPath -ErrorAction Stop
        foreach ($name in @($defaults.Keys)) {
            $value = Get-AutoRunnerPropertyValue -InputObject $item -Name $name -Default $defaults[$name]
            if ($name -in @('TutorialCompleted','TutorialDoNotShowAgain','UpdateCheckEnabled')) {
                $defaultBoolean=[bool]$defaults[$name]
                try { $defaults[$name] = ConvertTo-AutoRunnerBoolean -Value $value -Default $defaultBoolean -Name $name } catch { $defaults[$name] = $defaultBoolean }
            }
            else { $defaults[$name] = [string]$value }
        }
    }
    catch {}
    return [pscustomobject]$defaults
}

function Set-AutoRunnerUserSettings {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$PreferredSqlBackupPath,
        [AllowNull()][string]$PreferredSqlBackupCliPath,
        [AllowNull()][string]$PreferredSqlBackupAppPath,
        [AllowNull()][string]$DetectionSource,
        [AllowNull()][bool]$TutorialCompleted,
        [AllowNull()][bool]$TutorialDoNotShowAgain,
        [AllowNull()][string]$TutorialVersion,
        [AllowNull()][bool]$UpdateCheckEnabled,
        [AllowNull()][string]$LastUpdateCheckUtc,
        [AllowNull()][string]$SkippedUpdateTag
    )
    if (-not (Test-AutoRunnerIsWindows)) { return }
    New-Item -Path $script:UserRegistryPath -Force | Out-Null
    $values = [ordered]@{}
    foreach ($entry in @{
        PreferredSqlBackupPath=$PreferredSqlBackupPath
        PreferredSqlBackupCliPath=$PreferredSqlBackupCliPath
        PreferredSqlBackupAppPath=$PreferredSqlBackupAppPath
        DetectionSource=$DetectionSource
        TutorialVersion=$TutorialVersion
        LastUpdateCheckUtc=$LastUpdateCheckUtc
        SkippedUpdateTag=$SkippedUpdateTag
    }.GetEnumerator()) {
        if ($null -ne $entry.Value) { $values[$entry.Key] = [string]$entry.Value }
    }
    if ($PSBoundParameters.ContainsKey('TutorialCompleted')) { $values['TutorialCompleted'] = if($TutorialCompleted){1}else{0} }
    if ($PSBoundParameters.ContainsKey('TutorialDoNotShowAgain')) { $values['TutorialDoNotShowAgain'] = if($TutorialDoNotShowAgain){1}else{0} }
    if ($PSBoundParameters.ContainsKey('UpdateCheckEnabled')) { $values['UpdateCheckEnabled'] = if($UpdateCheckEnabled){1}else{0} }
    if ($values.Contains('PreferredSqlBackupPath') -or $values.Contains('DetectionSource')) { $values['DetectionUpdatedUtc'] = [DateTime]::UtcNow.ToString('o') }
    foreach ($entry in $values.GetEnumerator()) {
        $type = if ($entry.Value -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -Path $script:UserRegistryPath -Name $entry.Key -Value $entry.Value -PropertyType $type -Force | Out-Null
    }
}

function Clear-AutoRunnerSqlBackupPreference {
    [CmdletBinding()]
    param()
    if (-not (Test-AutoRunnerIsWindows)) { return }
    foreach ($name in @('PreferredSqlBackupPath','PreferredSqlBackupCliPath','PreferredSqlBackupAppPath','DetectionSource','DetectionUpdatedUtc')) {
        Remove-ItemProperty -LiteralPath $script:UserRegistryPath -Name $name -ErrorAction SilentlyContinue
    }
}



$script:AutoRunnerRepository = 'Gui1Kk/SQLBackupAndFTP-AutoRunner'
$script:SqlBackupAndFTPDownloadUrl = 'https://sqlbackupandftp.com/home/downloadlatestversion'
function Get-AutoRunnerRepository { return $script:AutoRunnerRepository }
function Get-SqlBackupAndFTPDownloadUrl { return $script:SqlBackupAndFTPDownloadUrl }

function ConvertTo-AutoRunnerReleaseDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Tag)
    $value=$Tag.Trim()
    $match=[regex]::Match($value,'^(?i:v)?(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:[- ]?(?<channel>RC|Beta|Alpha)(?:[.-]?(?<sequence>\d+))?)?$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $match.Success){return $null}
    $channel=if($match.Groups['channel'].Success){$match.Groups['channel'].Value}else{'Stable'}
    switch -Regex ($channel){
        '^(?i)rc$'{$channel='RC'}
        '^(?i)beta$'{$channel='Beta'}
        '^(?i)alpha$'{$channel='Alpha'}
        default{$channel='Stable'}
    }
    $sequence=0
    if($match.Groups['sequence'].Success){[void][int]::TryParse($match.Groups['sequence'].Value,[ref]$sequence)}
    $version=[version](('{0}.{1}.{2}' -f $match.Groups['major'].Value,$match.Groups['minor'].Value,$match.Groups['patch'].Value))
    $rank=switch($channel){'Stable'{4}'RC'{3}'Beta'{2}'Alpha'{1}default{0}}
    return [pscustomobject]@{Tag=$Tag;Version=$version;Channel=$channel;Sequence=$sequence;Rank=$rank;Display=($version.ToString(3)+$(if($channel -eq 'Stable'){''}else{' '+$channel+$(if($sequence -gt 0){$sequence}else{''})}))}
}

function Compare-AutoRunnerReleaseDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Left,[Parameter(Mandatory=$true)]$Right)
    $versionCompare=$Left.Version.CompareTo($Right.Version)
    if($versionCompare -ne 0){return $versionCompare}
    if([int]$Left.Rank -ne [int]$Right.Rank){return [Math]::Sign([int]$Left.Rank-[int]$Right.Rank)}
    return [Math]::Sign([int]$Left.Sequence-[int]$Right.Sequence)
}

function Get-AutoRunnerCurrentReleaseDescriptor {
    $tag=$script:AutoRunnerVersion
    if($script:AutoRunnerReleaseChannel -and $script:AutoRunnerReleaseChannel -ne 'Stable'){$tag+='-'+$script:AutoRunnerReleaseChannel}
    return ConvertTo-AutoRunnerReleaseDescriptor -Tag $tag
}

function Test-AutoRunnerShouldCheckUpdates {
    [CmdletBinding()]
    param([int]$MinimumHours=12)
    $settings=Get-AutoRunnerUserSettings
    if(-not [bool]$settings.UpdateCheckEnabled){return $false}
    if([string]::IsNullOrWhiteSpace([string]$settings.LastUpdateCheckUtc)){return $true}
    try{
        $last=[DateTime]::Parse([string]$settings.LastUpdateCheckUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
        return (([DateTime]::UtcNow-$last.ToUniversalTime()).TotalHours -ge $MinimumHours)
    }catch{return $true}
}

function Get-AutoRunnerUpdateInfo {
    [CmdletBinding()]
    param([switch]$IncludePrerelease,[int]$TimeoutSeconds=8)
    if(-not(Test-AutoRunnerIsWindows)){throw 'A verificação integrada de atualizações exige Windows.'}
    try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}catch{}
    $headers=@{'User-Agent'=('SQLBackupAndFTP-AutoRunner/'+$script:AutoRunnerVersion);'Accept'='application/vnd.github+json'}
    $uri='https://api.github.com/repos/'+$script:AutoRunnerRepository+'/releases?per_page=20'
    # Only advance the automatic-check timestamp after GitHub answered successfully.
    # Offline/proxy/DNS failures must not suppress the next startup check for 12 hours.
    $releases=@(Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop)
    try{Set-AutoRunnerUserSettings -LastUpdateCheckUtc ([DateTime]::UtcNow.ToString('o'))}catch{}
    $current=Get-AutoRunnerCurrentReleaseDescriptor
    $candidates=New-Object System.Collections.Generic.List[object]
    foreach($release in $releases){
        if([bool](Get-AutoRunnerPropertyValue -InputObject $release -Name 'draft' -Default $false)){continue}
        $prerelease=[bool](Get-AutoRunnerPropertyValue -InputObject $release -Name 'prerelease' -Default $false)
        if($prerelease -and -not $IncludePrerelease){continue}
        $tag=[string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'tag_name' -Default '')
        $descriptor=ConvertTo-AutoRunnerReleaseDescriptor -Tag $tag
        if(-not $descriptor){continue}
        if((Compare-AutoRunnerReleaseDescriptor -Left $descriptor -Right $current) -le 0){continue}
        $assets=@(Get-AutoRunnerPropertyValue -InputObject $release -Name 'assets' -Default @())
        $label=$tag.Trim();if($label.StartsWith('v',[StringComparison]::OrdinalIgnoreCase)){$label=$label.Substring(1)}
        $setupName='SQLBackupAndFTP-AutoRunner-Setup-v'+$label+'.exe'
        $setupAsset=$assets|Where-Object{[string](Get-AutoRunnerPropertyValue -InputObject $_ -Name 'name' -Default '') -ieq $setupName}|Select-Object -First 1
        $sumAsset=$assets|Where-Object{[string](Get-AutoRunnerPropertyValue -InputObject $_ -Name 'name' -Default '') -ieq 'SHA256SUMS.txt'}|Select-Object -First 1
        if(-not $setupAsset -or -not $sumAsset){continue}
        $candidates.Add([pscustomobject]@{
            IsUpdateAvailable=$true
            Current=$current.Display
            Tag=$tag
            Version=$descriptor.Version.ToString(3)
            Channel=$descriptor.Channel
            DisplayVersion=$descriptor.Display
            Name=[string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'name' -Default $tag)
            PublishedAt=[string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'published_at' -Default '')
            HtmlUrl=[string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'html_url' -Default '')
            SetupAssetName=$setupName
            SetupDownloadUrl=[string](Get-AutoRunnerPropertyValue -InputObject $setupAsset -Name 'browser_download_url' -Default '')
            ChecksumDownloadUrl=[string](Get-AutoRunnerPropertyValue -InputObject $sumAsset -Name 'browser_download_url' -Default '')
            ReleaseNotes=[string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'body' -Default '')
            Descriptor=$descriptor
        })
    }
    $selected=$null
    foreach($candidate in $candidates){if($null -eq $selected -or (Compare-AutoRunnerReleaseDescriptor -Left $candidate.Descriptor -Right $selected.Descriptor) -gt 0){$selected=$candidate}}
    if($selected){return $selected}
    return [pscustomobject]@{IsUpdateAvailable=$false;Current=$current.Display;Tag='';Version=$script:AutoRunnerVersion;Channel=$script:AutoRunnerReleaseChannel;DisplayVersion=$current.Display;Name='';PublishedAt='';HtmlUrl='';SetupAssetName='';SetupDownloadUrl='';ChecksumDownloadUrl='';ReleaseNotes='';Descriptor=$current}
}

function Get-AutoRunnerPropertyValue {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-AutoRunnerBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [bool]$Default = $false,
        [string]$Name = 'valor booleano'
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
        if ([int64]$Value -eq 0) { return $false }
        if ([int64]$Value -eq 1) { return $true }
    }
    $text = ([string]$Value).Trim()
    if ($text -match '^(?i:true|1|sim|s|yes|y)$') { return $true }
    if ($text -match '^(?i:false|0|nao|não|n|no)$') { return $false }
    throw "Valor inválido para ${Name}: '$Value'."
}

function Copy-AutoRunnerFileAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Arquivo de origem ausente: $Source" }
    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temp = Join-Path $directory ('.{0}.{1}.new' -f ([IO.Path]::GetFileName($Destination)), [Guid]::NewGuid().ToString('N'))
    $replaceBackup = Join-Path $directory ('.{0}.{1}.old' -f ([IO.Path]::GetFileName($Destination)), [Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $Source -Destination $temp -Force
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            try { [IO.File]::Replace($temp, $Destination, $replaceBackup, $true) }
            catch {
                Copy-Item -LiteralPath $Destination -Destination $replaceBackup -Force
                Move-Item -LiteralPath $temp -Destination $Destination -Force
            }
        }
        else { Move-Item -LiteralPath $temp -Destination $Destination -Force }
    }
    catch {
        if ((Test-Path -LiteralPath $replaceBackup -PathType Leaf) -and -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            Move-Item -LiteralPath $replaceBackup -Destination $Destination -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
    }
}

function Copy-AutoRunnerTreeSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Diretório de origem ausente: $Source" }
    if (Test-AutoRunnerTreeHasReparsePoint -Path $Source) { throw "Cópia recusada: a árvore contém junction ou link simbólico: $Source" }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        $target = Join-Path $Destination $item.Name
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point recusado: $($item.FullName)" }
        if ($item.PSIsContainer) { Copy-AutoRunnerTreeSafe -Source $item.FullName -Destination $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function ConvertTo-AutoRunnerProcessArgument {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)); $backslashes = 0 }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-AutoRunnerProcessArguments {
    param([Parameter(Mandatory = $true)][object[]]$Arguments)
    return (($Arguments | ForEach-Object { ConvertTo-AutoRunnerProcessArgument -Value ([string]$_) }) -join ' ')
}

function Test-AutoRunnerIsWindows {
    if ($PSVersionTable.PSVersion.Major -le 5) { return $true }
    return [bool]$IsWindows
}

function Test-AutoRunnerAdministrator {
    if (-not (Test-AutoRunnerIsWindows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AutoRunnerWindowsPowerShellPath {
    $candidate = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return 'powershell.exe'
}

function ConvertTo-AutoRunnerSafeFileName {
    param([Parameter(Mandatory = $true)][string]$Value)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Value.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    }
    $result = (-join $chars).Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($result)) { return 'item' }
    if ($result.Length -gt 80) { $result = $result.Substring(0, 80).TrimEnd() }
    return $result
}

function Get-AutoRunnerStringHash {
    param([AllowNull()][string]$Value, [ValidateRange(4, 64)][int]$Length = 12)
    if ($null -eq $Value) { $Value = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        $hash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        return $hash.Substring(0, [Math]::Min($Length, $hash.Length))
    }
    finally { $sha.Dispose() }
}

function Get-AutoRunnerJobArtifactName {
    param([Parameter(Mandatory = $true)][string]$JobName)
    $safe = ConvertTo-AutoRunnerSafeFileName -Value $JobName
    return ('{0}-{1}' -f $safe, (Get-AutoRunnerStringHash -Value $JobName -Length 10))
}

function Invoke-AutoRunnerLogRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1, 1024)][int]$MaxSizeMB = 10,
        [ValidateRange(1, 50)][int]$KeepFiles = 5,
        [ValidateRange(1, 3650)][int]$RetentionDays = 90
    )

    try {
        $directory = Split-Path -Parent $Path
        if ([string]::IsNullOrWhiteSpace($directory)) { $directory = (Get-Location).Path }
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $base = [IO.Path]::GetFileNameWithoutExtension($Path)
        $ext = [IO.Path]::GetExtension($Path)
        Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like ($base + '.*' + $ext) -and $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
        $maxBytes = [int64]$MaxSizeMB * 1MB
        if ((Get-Item -LiteralPath $Path).Length -lt $maxBytes) { return }

        $oldest = '{0}.{1}{2}' -f (Join-Path $directory $base), $KeepFiles, $ext
        Remove-Item -LiteralPath $oldest -Force -ErrorAction SilentlyContinue
        for ($index = $KeepFiles - 1; $index -ge 1; $index--) {
            $source = '{0}.{1}{2}' -f (Join-Path $directory $base), $index, $ext
            $target = '{0}.{1}{2}' -f (Join-Path $directory $base), ($index + 1), $ext
            if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination $target -Force }
        }
        $first = '{0}.1{1}' -f (Join-Path $directory $base), $ext
        Move-Item -LiteralPath $Path -Destination $first -Force
    }
    catch {
        # Falha de rotação nunca deve impedir um backup. O chamador ainda tentará escrever.
        return
    }
}

function Write-AutoRunnerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('TRACE','INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO',
        [string]$Component = 'AutoRunner',
        [switch]$NoConsole,
        [int]$MaxSizeMB = 10,
        [int]$KeepFiles = 5,
        [int]$RetentionDays = 90
    )

    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Component, $Message
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

    $mutexName = 'Global\SQLBackupAndFTPAuto_Log_' + (Get-AutoRunnerStringHash -Value ([IO.Path]::GetFullPath($Path).ToLowerInvariant()) -Length 24)
    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
        catch [Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw "Não foi possível obter bloqueio para o log '$Path'." }
        Invoke-AutoRunnerLogRotation -Path $Path -MaxSizeMB $MaxSizeMB -KeepFiles $KeepFiles -RetentionDays $RetentionDays
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    }
    finally {
        if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }

    if (-not $NoConsole) {
        $color = 'Gray'
        switch ($Level) {
            'SUCCESS' { $color = 'Green' }
            'WARN' { $color = 'Yellow' }
            'ERROR' { $color = 'Red' }
            'TRACE' { $color = 'DarkGray' }
        }
        Write-Host $line -ForegroundColor $color
    }
}

function Write-AutoRunnerJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(2, 100)][int]$Depth = 20,
        [switch]$CreateBackup
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

    $backup = $Path + '.bak'
    if ($CreateBackup -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Copy-Item -LiteralPath $Path -Destination $backup -Force
    }

    $temp = Join-Path $directory ('.{0}.{1}.tmp' -f ([IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString('N'))
    $replaceBackup = Join-Path $directory ('.{0}.{1}.replace.bak' -f ([IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString('N'))
    try {
        $json = $InputObject | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        # Valida o JSON recém-gravado antes de promovê-lo.
        [void]((Get-Content -LiteralPath $temp -Raw -Encoding UTF8) | ConvertFrom-Json)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try { [IO.File]::Replace($temp, $Path, $replaceBackup, $true) }
            catch {
                # Fallback para sistemas de arquivos que não oferecem Replace. Mantém cópia de segurança.
                Copy-Item -LiteralPath $Path -Destination $replaceBackup -Force
                Move-Item -LiteralPath $temp -Destination $Path -Force
            }
        }
        else { Move-Item -LiteralPath $temp -Destination $Path -Force }
    }
    catch {
        if ((Test-Path -LiteralPath $replaceBackup) -and -not (Test-Path -LiteralPath $Path)) {
            Move-Item -LiteralPath $replaceBackup -Destination $Path -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
    }
}

function Read-AutoRunnerJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($AllowMissing) { return $null }
        throw "Arquivo JSON nao encontrado: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Arquivo JSON vazio: $Path" }
    try { return $raw | ConvertFrom-Json }
    catch { throw "JSON invalido em '$Path': $($_.Exception.Message)" }
}

function Get-AutoRunnerFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function New-AutoRunnerManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($relative in $RelativePaths | Sort-Object -Unique) {
        $full = Join-Path $RootPath $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Arquivo do manifesto nao encontrado: $full" }
        $items.Add([pscustomobject][ordered]@{
            Path = $relative.Replace('\','/')
            Sha256 = Get-AutoRunnerFileHash -Path $full
            Length = (Get-Item -LiteralPath $full).Length
        })
    }
    $manifest = [pscustomobject][ordered]@{
        Product = 'SQLBackupAndFTP AutoRunner'
        Version = $script:AutoRunnerVersion
        CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
        Files = @($items)
    }
    Write-AutoRunnerJsonAtomic -InputObject $manifest -Path $OutputPath -Depth 10
    return $manifest
}

function Test-AutoRunnerManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string[]]$RequiredPaths
    )
    $issues = New-Object System.Collections.Generic.List[string]
    $defaultRequired = @(
        'modules/AutoRunner.Core.psm1',
        'scripts/Run-SQLBackupAndFTPJob.ps1',
        'scripts/Manager.ps1',
        'scripts/Install-SQLBackupAndFTP-Auto.ps1',
        'scripts/Uninstall-SQLBackupAndFTP-Auto.ps1',
        'scripts/Export-Diagnostics.ps1',
        'scripts/Invoke-QA.ps1'
    )
    $required = if($PSBoundParameters.ContainsKey('RequiredPaths')){@($RequiredPaths)}else{@($defaultRequired)}
    if (Test-AutoRunnerPathHasReparsePoint -Path $ManifestPath -StopAtPath $RootPath) {
        $issues.Add('Manifesto ou diretório ancestral é um reparse point.')
        return [pscustomobject]@{ IsValid = $false; Issues = @($issues) }
    }
    $manifest = Read-AutoRunnerJson -Path $ManifestPath
    if ([string]$manifest.Product -ne 'SQLBackupAndFTP AutoRunner') { $issues.Add('Produto do manifesto inválido.') }
    if ([string]$manifest.Version -ne $script:AutoRunnerVersion) { $issues.Add("Versão do manifesto divergente: $($manifest.Version)") }
    $files = @($manifest.Files)
    if ($files.Count -eq 0) { $issues.Add('Manifesto sem arquivos.') }
    $seen = @{}
    foreach ($item in $files) {
        $declared = ([string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Path' -Default '')).Trim()
        if ([string]::IsNullOrWhiteSpace($declared)) { $issues.Add('Manifesto contém caminho vazio.'); continue }
        $normalized = $declared.Replace('\','/')
        while ($normalized.StartsWith('./', [StringComparison]::Ordinal)) { $normalized = $normalized.Substring(2) }
        $parts = @($normalized.Split('/') | Where-Object { $_ -ne '' })
        if ($declared -match '^[\\/]' -or $declared -match '^[A-Za-z]:' -or [string]::IsNullOrWhiteSpace($normalized) -or $parts -contains '..') {
            $issues.Add("Caminho absoluto, vazio ou traversal no manifesto: $declared")
            continue
        }
        $key = $normalized.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { $issues.Add("Caminho duplicado no manifesto: $declared"); continue }
        $seen[$key] = $true
        $relative = $normalized.Replace('/','\')
        $full = Join-Path $RootPath $relative
        if (-not (Test-AutoRunnerPathIsWithin -ChildPath $full -ParentPath $RootPath)) {
            $issues.Add("Caminho inseguro no manifesto: $relative")
            continue
        }
        if (Test-AutoRunnerPathHasReparsePoint -Path $full -StopAtPath $RootPath) {
            $issues.Add("Reparse point detectado no caminho do manifesto: $relative")
            continue
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $issues.Add("Arquivo ausente: $relative")
            continue
        }
        $file = Get-Item -LiteralPath $full -Force
        $expectedHash = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Sha256' -Default '')
        if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') { $issues.Add("Hash inválido no manifesto: $relative"); continue }
        $hash = Get-AutoRunnerFileHash -Path $full
        if ($hash -ne $expectedHash.ToUpperInvariant()) { $issues.Add("Hash divergente: $relative") }
        $expectedLength = Get-AutoRunnerPropertyValue -InputObject $item -Name 'Length'
        if ($null -eq $expectedLength) { $issues.Add("Tamanho ausente no manifesto: $relative") }
        elseif ([int64]$expectedLength -ne [int64]$file.Length) { $issues.Add("Tamanho divergente: $relative") }
    }
    foreach ($requiredPath in $required) {
        if (-not $seen.ContainsKey($requiredPath.ToLowerInvariant())) { $issues.Add("Arquivo crítico não declarado no manifesto: $requiredPath") }
    }
    return [pscustomobject]@{ IsValid = ($issues.Count -eq 0); Issues = @($issues) }
}

function Test-AutoRunnerPackageChecksums {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RootPath, [string]$ChecksumPath = (Join-Path $RootPath 'SHA256SUMS.txt'))
    $issues = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) {
        return [pscustomobject]@{ IsPresent=$false; IsValid=$false; Issues=@('SHA256SUMS.txt ausente.') }
    }
    if (Test-AutoRunnerTreeHasReparsePoint -Path $RootPath) {
        return [pscustomobject]@{ IsPresent=$true; IsValid=$false; Issues=@('O pacote contém junction ou link simbólico.') }
    }

    $seen=@{}
    foreach ($line in @(Get-Content -LiteralPath $ChecksumPath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([A-Fa-f0-9]{64})\s+\*?(.+)$') { $issues.Add("Linha inválida em SHA256SUMS.txt: $line"); continue }
        $hash=$matches[1].ToUpperInvariant()
        $relative=$matches[2].Trim().Replace('/','\')
        if ($relative -match '^[\\/]' -or $relative -match '^[A-Za-z]:' -or $relative -match '(^|\\)\.\.(\\|$)') {
            $issues.Add("Caminho inseguro no checksum: $relative"); continue
        }
        if ([IO.Path]::GetFileName($relative) -ieq 'SHA256SUMS.txt') {
            $issues.Add('SHA256SUMS.txt não pode declarar o próprio hash.'); continue
        }
        $key=$relative.ToLowerInvariant()
        if($seen.ContainsKey($key)){$issues.Add("Caminho duplicado no checksum: $relative");continue}
        $seen[$key]=$true
        $full=Join-Path $RootPath $relative
        if(-not(Test-AutoRunnerPathIsWithin -ChildPath $full -ParentPath $RootPath)){$issues.Add("Caminho fora do pacote: $relative");continue}
        if(Test-AutoRunnerPathHasReparsePoint -Path $full -StopAtPath $RootPath){$issues.Add("Reparse point no pacote: $relative");continue}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){$issues.Add("Arquivo ausente no pacote: $relative");continue}
        if((Get-AutoRunnerFileHash -Path $full) -ne $hash){$issues.Add("Hash divergente no pacote: $relative")}
    }
    if($seen.Count -eq 0){$issues.Add('Nenhum arquivo válido declarado no checksum.')}

    # Cada arquivo do pacote, sem exceções silenciosas, deve estar declarado.
    # O build de produção é responsável por excluir .git, resultados, logs e temporários.
    foreach($file in @(Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force -ErrorAction Stop)) {
        if($file.FullName -ieq ([IO.Path]::GetFullPath($ChecksumPath))){continue}
        $relative=$file.FullName.Substring(([IO.Path]::GetFullPath($RootPath).TrimEnd('\')).Length).TrimStart('\')
        if(-not $seen.ContainsKey($relative.ToLowerInvariant())){$issues.Add("Arquivo não declarado no checksum: $relative")}
    }
    return [pscustomobject]@{IsPresent=$true;IsValid=($issues.Count -eq 0);Issues=@($issues)}
}

function Get-AutoRunnerExecutablePathFromCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $trimmed = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($trimmed -match '^"([^"]+)"') { return $matches[1] }
    if ($trimmed -match '^(.*?\.exe)(?:\s|$)') { return $matches[1].Trim() }
    return ($trimmed -split '\s+', 2)[0]
}

function Get-AutoRunnerFileVersion {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Item -LiteralPath $Path).VersionInfo.FileVersion }
    catch { return $null }
}

function Get-SqlBackupAndFTPService {
    [CmdletBinding()]
    param([string]$InstallDir)
    if (-not (Test-AutoRunnerIsWindows)) { return $null }
    $normalizedInstall = $null
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        try { $normalizedInstall = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\') } catch {}
    }
    $ranked = foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $pathName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'PathName' -Default '')
        $path = Get-AutoRunnerExecutablePathFromCommandLine -CommandLine $pathName
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $serviceName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'Name' -Default '')
        $displayName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'DisplayName' -Default '')
        $fileName = [IO.Path]::GetFileName($path)
        $parent = $null
        try { $parent = [IO.Path]::GetFullPath((Split-Path -Parent $path)).TrimEnd('\') } catch {}
        $exactExecutable = ($fileName -ieq 'SqlBak.Service.exe')
        $sameInstall = ($normalizedInstall -and $parent -and $parent -ieq $normalizedInstall)
        $named = ($serviceName -match '(?i)SqlBak|SQLBackupAndFTP') -or ($displayName -match '(?i)SqlBak|SQLBackupAndFTP')
        if (-not $exactExecutable -and -not ($sameInstall -and $named)) { continue }
        $score = 0
        if ($exactExecutable) { $score += 100 }
        if ($sameInstall) { $score += 80 }
        if ($named) { $score += 20 }
        [pscustomobject]@{
            Score=$score
            Name=$serviceName
            DisplayName=$displayName
            State=[string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'State' -Default '')
            StartMode=[string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'StartMode' -Default '')
            PathName=$pathName
            ExecutablePath=$path
        }
    }
    return $ranked | Sort-Object Score -Descending | Select-Object -First 1
}

function Resolve-SqlBackupAndFTPDirectory {
    [CmdletBinding()]
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        if ($expanded -match ',\s*\d+$') { $expanded = $expanded -replace ',\s*\d+$','' }
        if ([IO.Path]::GetExtension($expanded) -match '(?i)^\.(exe|dll)$') { $expanded = Split-Path -Parent $expanded }
        return [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    }
    catch { return $null }
}

function Test-SqlBackupAndFTPDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $directory = Resolve-SqlBackupAndFTPDirectory -Path $Path
    if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }
    $cliCandidates = @('SqlBak.Job.Cli.exe','SqlBak.Job.CLI.exe') | ForEach-Object { Join-Path $directory $_ }
    $cli = $cliCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $cli) { return $null }
    $appCandidates = @('SBF.Application.exe','SQLBackupAndFTP.exe','SqlBak.Application.exe') | ForEach-Object { Join-Path $directory $_ }
    $app = $appCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $serviceExe = Join-Path $directory 'SqlBak.Service.exe'
    return [pscustomobject][ordered]@{
        InstallDir=$directory
        CliPath=$cli
        CliVersion=Get-AutoRunnerFileVersion -Path $cli
        AppPath=$app
        AppVersion=if($app){Get-AutoRunnerFileVersion -Path $app}else{$null}
        ServiceExecutable=if(Test-Path -LiteralPath $serviceExe -PathType Leaf){$serviceExe}else{$null}
    }
}


function Find-SqlBakCliLimited {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [ValidateRange(1,8)][int]$MaxDepth=5,
        [ValidateRange(100,50000)][int]$MaxDirectories=12000
    )
    $results=New-Object System.Collections.Generic.List[string]
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){return @()}
    $fullRoot=[IO.Path]::GetFullPath($Root)
    $queue=New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{Path=$fullRoot;Depth=0})
    $visited=0
    $rootPath=[IO.Path]::GetPathRoot($fullRoot)
    while($queue.Count -gt 0 -and $visited -lt $MaxDirectories){
        $current=$queue.Dequeue();$visited++
        try{
            $cli=Join-Path $current.Path 'SqlBak.Job.Cli.exe'
            if(Test-Path -LiteralPath $cli -PathType Leaf){$results.Add($cli)}
            if($current.Depth -ge $MaxDepth){continue}
            foreach($dir in @(Get-ChildItem -LiteralPath $current.Path -Directory -Force -ErrorAction SilentlyContinue)){
                if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){continue}
                # Em busca iniciada na raiz do volume, nunca mergulhar em árvores de
                # sistema ou perfis. O objetivo é achar instalações customizadas em
                # D:\Apps, C:\Ferramentas, etc., não varrer o disco inteiro.
                if($current.Path.TrimEnd('\') -ieq $rootPath.TrimEnd('\')){
                    if($dir.Name -match '(?i)^(Windows|Users|ProgramData|System Volume Information|\$Recycle\.Bin|Recovery|PerfLogs|Documents and Settings)$'){continue}
                }
                if($dir.Name -match '(?i)^(WindowsApps|Windows Defender)$'){continue}
                $queue.Enqueue([pscustomobject]@{Path=$dir.FullName;Depth=([int]$current.Depth+1)})
            }
        }catch{}
    }
    return @($results|Select-Object -Unique)
}

function Get-AutoRunnerFixedDriveRoots {
    [CmdletBinding()]
    param()
    $roots=New-Object System.Collections.Generic.List[string]
    try{
        foreach($drive in [IO.DriveInfo]::GetDrives()){
            try{
                if(-not $drive.IsReady){continue}
                if($drive.DriveType -ne [IO.DriveType]::Fixed){continue}
                if(Test-Path -LiteralPath $drive.RootDirectory.FullName -PathType Container){[void]$roots.Add($drive.RootDirectory.FullName)}
            }catch{}
        }
    }catch{}
    return @($roots|Select-Object -Unique)
}
function Find-SqlBackupAndFTPInstallations {
    [CmdletBinding()]
    param(
        [string]$PreferredPath,
        [switch]$DeepSearch,
        [switch]$Quick,
        [ValidateRange(1,8)][int]$SearchDepth = 4
    )
    if (-not (Test-AutoRunnerIsWindows)) { throw 'Detecção do SQLBackupAndFTP exige Windows.' }
    $candidateDirs = New-Object System.Collections.Generic.List[object]
    function Add-SqlBakCandidate {
        param([AllowNull()][string]$Path,[string]$Source,[int]$Score)
        $full = Resolve-SqlBackupAndFTPDirectory -Path $Path
        if ([string]::IsNullOrWhiteSpace($full)) { return }
        $candidateDirs.Add([pscustomobject]@{Path=$full;Source=$Source;Score=$Score})
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) { Add-SqlBakCandidate -Path $PreferredPath -Source 'Caminho informado' -Score 1200 }
    $settings = Get-AutoRunnerUserSettings
    if (-not [string]::IsNullOrWhiteSpace($settings.PreferredSqlBackupPath)) { Add-SqlBakCandidate -Path $settings.PreferredSqlBackupPath -Source 'Preferência salva' -Score 1150 }

    $registryPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($registryPath in $registryPaths) {
        foreach ($item in @(Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue)) {
            $displayName = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'DisplayName' -Default '')
            $publisher = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Publisher' -Default '')
            if (($displayName + ' ' + $publisher) -notmatch '(?i)SQLBackupAndFTP|SQL Backup and FTP|Pranas') { continue }
            $installLocation = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'InstallLocation' -Default '')
            $displayIcon = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'DisplayIcon' -Default '')
            $uninstallString = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'UninstallString' -Default '')
            if ($installLocation) { Add-SqlBakCandidate -Path $installLocation -Source ("Registro: $displayName") -Score 900 }
            if ($displayIcon) {
                $iconPath = Get-AutoRunnerExecutablePathFromCommandLine -CommandLine $displayIcon
                if ($iconPath) { Add-SqlBakCandidate -Path $iconPath -Source ("Ícone do registro: $displayName") -Score 850 }
            }
            if ($uninstallString) {
                $uninstallExe = Get-AutoRunnerExecutablePathFromCommandLine -CommandLine $uninstallString
                if ($uninstallExe) { Add-SqlBakCandidate -Path $uninstallExe -Source ("Desinstalador: $displayName") -Score 700 }
            }
        }
    }

    # O modo Quick é usado durante a primeira pintura das interfaces. Ele evita
    # consultas CIM/WMI, que podem bloquear por vários segundos em instalações
    # Windows danificadas ou com o provedor WMI ocupado. A busca completa continua
    # disponível quando o usuário clica em Procurar automaticamente.
    if (-not $Quick) {
        foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
            $pathName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'PathName' -Default '')
            $exe = Get-AutoRunnerExecutablePathFromCommandLine -CommandLine $pathName
            if ([string]::IsNullOrWhiteSpace($exe)) { continue }
            $serviceName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'Name' -Default '')
            $displayName = [string](Get-AutoRunnerPropertyValue -InputObject $service -Name 'DisplayName' -Default '')
            $exact = [IO.Path]::GetFileName($exe) -ieq 'SqlBak.Service.exe'
            $named = ($serviceName + ' ' + $displayName) -match '(?i)SqlBak|SQLBackupAndFTP'
            if ($exact -or $named) { Add-SqlBakCandidate -Path $exe -Source ("Serviço: $serviceName") -Score $(if($exact){1100}else{800}) }
        }

        foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
            $exe = [string](Get-AutoRunnerPropertyValue -InputObject $process -Name 'ExecutablePath' -Default '')
            $name = [string](Get-AutoRunnerPropertyValue -InputObject $process -Name 'Name' -Default '')
            if ([string]::IsNullOrWhiteSpace($exe)) { continue }
            if ($name -match '(?i)^(SBF\.Application|SQLBackupAndFTP|SqlBak\.Service|SqlBak\.Job\.Cli)\.exe$') {
                Add-SqlBakCandidate -Path $exe -Source ("Processo: $name") -Score 980
            }
        }
    }

    foreach ($appPath in @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\SBF.Application.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\SBF.Application.exe',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\SBF.Application.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\SQLBackupAndFTP.exe',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\SQLBackupAndFTP.exe'
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $appPath -ErrorAction Stop
            $defaultValue = ''
            try {
                $registryKey = Get-Item -LiteralPath $appPath -ErrorAction Stop
                $defaultValue = [string]$registryKey.GetValue('', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            } catch {}
            if ([string]::IsNullOrWhiteSpace($defaultValue)) { $defaultValue = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name '(default)' -Default '') }
            if ([string]::IsNullOrWhiteSpace($defaultValue)) { $defaultValue = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name '' -Default '') }
            $pathValue = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Path' -Default '')
            if ($defaultValue) { Add-SqlBakCandidate -Path $defaultValue -Source 'App Paths' -Score 850 }
            if ($pathValue) { Add-SqlBakCandidate -Path $pathValue -Source 'App Paths' -Score 820 }
        } catch {}
    }

    if (-not $Quick) {
        foreach ($startRoot in @(
            [Environment]::GetFolderPath('CommonStartMenu'),
            [Environment]::GetFolderPath('StartMenu'),
            [Environment]::GetFolderPath('CommonPrograms'),
            [Environment]::GetFolderPath('Programs')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }) {
            $shell = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                foreach ($shortcut in @(Get-ChildItem -LiteralPath $startRoot -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)SQLBackup|SqlBak' })) {
                    $shortcutCom=$null
                    try {
                        $shortcutCom=$shell.CreateShortcut($shortcut.FullName)
                        $target=[string]$shortcutCom.TargetPath
                        if ($target) { Add-SqlBakCandidate -Path $target -Source ("Atalho: $($shortcut.Name)") -Score 760 }
                    } catch {}
                    finally{if($shortcutCom){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutCom)}}
                }
            } catch {}
            finally{if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
        }
    }

    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    foreach ($root in $roots) {
        foreach ($name in @('SQLBackupAndFTP','SQL Backup And FTP','Pranas.NET\SQLBackupAndFTP')) {
            Add-SqlBakCandidate -Path (Join-Path $root $name) -Source 'Pasta padrão' -Score 300
        }
    }

    if ($DeepSearch) {
        # Último recurso: busca limitada em todos os volumes locais fixos. Ela não
        # depende do caminho padrão, mas possui profundidade/quantidade máximas e
        # ignora árvores de sistema para não virar uma varredura irrestrita.
        foreach ($root in @(Get-AutoRunnerFixedDriveRoots)) {
            foreach ($cli in @(Find-SqlBakCliLimited -Root $root -MaxDepth ([Math]::Max(5,$SearchDepth)) -MaxDirectories 12000)) {
                Add-SqlBakCandidate -Path $cli -Source ('Busca limitada no volume '+$root) -Score 260
            }
        }
    }

    $valid = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($candidateDirs | Group-Object { $_.Path.ToLowerInvariant() })) {
        $validated = Test-SqlBackupAndFTPDirectory -Path ([string]$group.Group[0].Path)
        if (-not $validated) { continue }
        $score = [int](($group.Group | Measure-Object Score -Maximum).Maximum)
        $sources = @($group.Group | Sort-Object Score -Descending | ForEach-Object { $_.Source } | Select-Object -Unique)
        $service = if($Quick){$null}else{Get-SqlBackupAndFTPService -InstallDir $validated.InstallDir}
        if ($service) { $score += 100 }
        if ($validated.AppPath) { $score += 25 }
        $sortableVersion = [version]'0.0.0.0'
        try {
            $m=[regex]::Match([string]$validated.CliVersion,'\d+(?:\.\d+){1,3}')
            if($m.Success){$sortableVersion=[version]$m.Value}
        } catch {}
        $valid.Add([pscustomobject][ordered]@{
            Score=$score
            SortableVersion=$sortableVersion
            InstallDir=$validated.InstallDir
            CliPath=$validated.CliPath
            CliVersion=$validated.CliVersion
            AppPath=$validated.AppPath
            AppVersion=$validated.AppVersion
            ServiceName=if($service){$service.Name}else{$null}
            ServiceDisplayName=if($service){$service.DisplayName}else{$null}
            ServiceState=if($service){$service.State}else{$null}
            ServicePath=if($service){$service.ExecutablePath}else{$validated.ServiceExecutable}
            DetectionSources=$sources
        })
    }
    return @($valid | Sort-Object @{Expression='Score';Descending=$true}, @{Expression='SortableVersion';Descending=$true})
}

function Get-SqlBackupAndFTPInstall {
    [CmdletBinding()]
    param(
        [string]$PreferredPath,
        [switch]$DeepSearch,
        [switch]$Quick,
        [switch]$AllowNotFound,
        [switch]$SavePreference
    )
    $all = @(Find-SqlBackupAndFTPInstallations -PreferredPath $PreferredPath -DeepSearch:$DeepSearch -Quick:$Quick)
    $selected = $all | Select-Object -First 1
    if (-not $selected) {
        if ($AllowNotFound) { return $null }
        throw 'SQLBackupAndFTP não foi localizado. Use “Localizar SQLBackupAndFTP” e selecione a pasta que contém SqlBak.Job.Cli.exe.'
    }
    $result = [pscustomobject][ordered]@{
        InstallDir=$selected.InstallDir
        CliPath=$selected.CliPath
        CliVersion=$selected.CliVersion
        AppPath=$selected.AppPath
        AppVersion=$selected.AppVersion
        ServiceName=$selected.ServiceName
        ServiceDisplayName=$selected.ServiceDisplayName
        ServiceState=$selected.ServiceState
        ServicePath=$selected.ServicePath
        DetectionSources=@($selected.DetectionSources)
        DetectionScore=[int]$selected.Score
        Alternatives=@($all | Select-Object -Skip 1)
    }
    if ($SavePreference) {
        Set-AutoRunnerUserSettings -PreferredSqlBackupPath $result.InstallDir -PreferredSqlBackupCliPath $result.CliPath -PreferredSqlBackupAppPath $result.AppPath -DetectionSource ($result.DetectionSources -join '; ')
    }
    return $result
}

function Get-SqlBakConfigurationRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallDir)
    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    function Add-ConfigRootCandidate {
        param([AllowNull()][string]$Value,[string]$Source,[string]$BaseDirectory)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"').Trim("'"))
            if (-not [IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $BaseDirectory $expanded }
            $expanded = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
            $possibleRoots = New-Object System.Collections.Generic.List[string]
            $possibleRoots.Add($expanded)
            if ([IO.Path]::GetFileName($expanded) -ieq 'context.db') { $possibleRoots.Add((Split-Path -Parent (Split-Path -Parent $expanded))) }
            elseif ([IO.Path]::GetFileName($expanded) -ieq 'Db') { $possibleRoots.Add((Split-Path -Parent $expanded)) }
            else { $possibleRoots.Add((Split-Path -Parent $expanded)) }
            foreach($root in @($possibleRoots | Where-Object {$_} | Select-Object -Unique)) {
                $db=Join-Path $root 'Db\context.db'
                if(Test-Path -LiteralPath $db -PathType Leaf){
                    $key=$root.ToLowerInvariant();if(-not $seen.ContainsKey($key)){$seen[$key]=$true;$candidates.Add([pscustomobject]@{Path=$root;Source=$Source})}
                }
            }
        } catch {}
    }

    $localConfigFiles = @(
        (Join-Path $InstallDir 'SqlBak.Local.config'),
        (Join-Path $InstallDir 'SBF.Application.exe.config'),
        (Join-Path $InstallDir 'SqlBak.Service.exe.config')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    foreach ($configFile in $localConfigFiles) {
        try {
            $text = Get-Content -LiteralPath $configFile -Raw -ErrorAction Stop
            $sourceName=[IO.Path]::GetFileName($configFile)
            foreach($line in @($text -split "`r?`n")){
                if($line -match '^\s*[^#;=]+\s*=\s*(.+?)\s*$'){Add-ConfigRootCandidate -Value $matches[1] -Source ($sourceName+':KeyValue') -BaseDirectory (Split-Path -Parent $configFile)}
            }
            $pathMatches = [regex]::Matches($text, '(?i)([A-Z]:\\[^\r\n"''<>]+|\\\\[^\r\n"''<>]+)')
            foreach ($match in $pathMatches) { Add-ConfigRootCandidate -Value $match.Value -Source ($sourceName+':Text') -BaseDirectory (Split-Path -Parent $configFile) }
            try {
                [xml]$xml = $text
                foreach ($node in @($xml.SelectNodes('//*'))) {
                    foreach($attribute in @($node.Attributes)){Add-ConfigRootCandidate -Value ([string]$attribute.Value) -Source ($sourceName+':XmlAttribute') -BaseDirectory (Split-Path -Parent $configFile)}
                    Add-ConfigRootCandidate -Value ([string]$node.InnerText) -Source ($sourceName+':XmlText') -BaseDirectory (Split-Path -Parent $configFile)
                }
            } catch {}
        } catch {}
    }

    $default = Join-Path $env:ProgramData 'Pranas.NET\SQLBackupAndFTP'
    Add-ConfigRootCandidate -Value $default -Source 'DefaultProgramData' -BaseDirectory $env:ProgramData
    $selected = $candidates | Select-Object -First 1
    if ($selected) { return $selected }
    return [pscustomobject]@{ Path = $default; Source = 'DefaultProgramDataNotFound' }
}


function Get-AutoRunnerProductFullControlSidList {
    [CmdletBinding()]
    param()
    $list=New-Object System.Collections.Generic.List[string]
    foreach($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-1-0','S-1-15-2-1','S-1-15-2-2','S-1-3-0','S-1-3-4')){[void]$list.Add($sid)}
    try{$current=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;if($current -and -not $list.Contains($current)){[void]$list.Add($current)}}catch{}
    return @($list)
}

function Set-AutoRunnerProductFullControlAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-AutoRunnerAdministrator)) { throw 'Administrador necessário para aplicar a política FullControl 3.0.0-RC.' }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $inspection=Get-AutoRunnerTreeInspection -Path $Path
        if(-not $inspection.InspectionSucceeded){throw ('Falha ao inspecionar árvore antes da ACL: '+($inspection.Errors -join '; '))}
        if($inspection.HasReparsePoint){throw ('ACL recusada: a árvore contém junction/link simbólico: '+($inspection.ReparsePoints -join '; '))}
    }
    $required=@(Get-AutoRunnerProductFullControlSidList)
    $owner=$null
    try{$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User}catch{}
    if(-not $owner){$owner=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')}
    $targets=New-Object System.Collections.Generic.List[string]
    [void]$targets.Add($Path)
    if(Test-Path -LiteralPath $Path -PathType Container){
        foreach($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)){[void]$targets.Add($item.FullName)}
    }
    # Cada item recebe ACE explícita, em vez de depender somente de herança. Isso é
    # intencional: a 3.0.0-RC exige FullControl observável em todos os recursos.
    foreach($target in @($targets | Sort-Object { $_.Length })){
        $item=Get-Item -LiteralPath $target -Force -ErrorAction Stop
        $security=if($item.PSIsContainer){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
        $security.SetAccessRuleProtection($true,$false)
        try{$security.SetOwner($owner)}catch{}
        foreach($sidText in $required){
            $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
            if($item.PSIsContainer){
                $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
            }else{
                $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow)
            }
            [void]$security.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $target -AclObject $security -ErrorAction Stop
    }
    $policy=Test-AutoRunnerProductFullControlAcl -Path $Path
    if(-not $policy.IsCompliant){throw ('Política FullControl 3.0.0-RC não aplicada integralmente: '+($policy.Issues -join '; '))}
    return Get-Acl -LiteralPath $Path
}

function Test-AutoRunnerProductFullControlAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $issues=New-Object System.Collections.Generic.List[string]
    if(-not(Test-Path -LiteralPath $Path)){return [pscustomobject]@{IsCompliant=$false;Issues=@("Caminho ausente: $Path")}}
    try{
        $required=@(Get-AutoRunnerProductFullControlSidList)
        $targets=New-Object System.Collections.Generic.List[string];$targets.Add($Path)
        if(Test-Path -LiteralPath $Path -PathType Container){foreach($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)){[void]$targets.Add($item.FullName)}}
        foreach($target in $targets){
            $acl=Get-Acl -LiteralPath $target -ErrorAction Stop
            foreach($sidText in $required){
                $found=$false
                foreach($entry in @($acl.Access)){
                    try{$sid=$entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value}catch{$sid=[string]$entry.IdentityReference.Value}
                    if($sid -eq $sidText -and $entry.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and (($entry.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl)){$found=$true;break}
                }
                if(-not$found){$issues.Add("$target | SID $sidText sem FullControl efetivo")}
            }
        }
    }catch{$issues.Add($_.Exception.Message)}
    return [pscustomobject]@{IsCompliant=($issues.Count -eq 0);Issues=@($issues)}
}

function Test-AutoRunnerExecutionPathSecurity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ExecutablePath, [switch]$AllowProductFullControlPolicy)
    $issues=New-Object System.Collections.Generic.List[string]
    if(-not(Test-Path -LiteralPath $ExecutablePath -PathType Leaf)){$issues.Add("Executável/DLL ausente: $ExecutablePath");return [pscustomobject]@{IsSafe=$false;Issues=@($issues)}}
    try{
        $full=[IO.Path]::GetFullPath($ExecutablePath)
        $directory=Split-Path -Parent $full
        $root=[IO.Path]::GetPathRoot($full)
        if(Test-AutoRunnerPathHasReparsePoint -Path $full -StopAtPath $root){$issues.Add("Caminho contém junction ou link simbólico: $full")}
        if(-not $AllowProductFullControlPolicy){
            foreach($unsafe in @(Get-AutoRunnerUnsafeAclEntries -Path $directory)){$issues.Add("ACL gravável por identidade ampla na árvore executável: $unsafe")}
        } else {
            $policy=Test-AutoRunnerProductFullControlAcl -Path $directory
            if(-not $policy.IsCompliant){foreach($issue in @($policy.Issues)){$issues.Add("ACL 3.0.0-RC não conforme: $issue")}}
        }
        # Um pai gravável pode permitir troca/renomeação do diretório executável. Verifica
        # cada ancestral existente, sem percorrer recursivamente Program Files ou o volume.
        $ancestor=if($AllowProductFullControlPolicy){Split-Path -Parent $directory}else{$directory}
        while(-not [string]::IsNullOrWhiteSpace($ancestor) -and $ancestor.TrimEnd('\') -ine $root.TrimEnd('\')){
            foreach($unsafe in @(Get-AutoRunnerUnsafeAclEntries -Path $ancestor -CurrentOnly)){$issues.Add("ACL gravável por identidade ampla em ancestral: $unsafe")}
            $parent=Split-Path -Parent $ancestor
            if([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $ancestor){break}
            $ancestor=$parent
        }
        $file=Get-Item -LiteralPath $full -Force
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$issues.Add("Arquivo é reparse point: $full")}
    }catch{$issues.Add($_.Exception.Message)}
    return [pscustomobject]@{IsSafe=($issues.Count -eq 0);Issues=@($issues)}
}

function Copy-SqliteDatabaseSnapshot {
    param([Parameter(Mandatory = $true)][string]$DatabasePath)
    $tempRoot = Join-Path $env:TEMP ('SQLBackupAndFTPAuto-SQLite-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $target = Join-Path $tempRoot 'context.db'
    Copy-Item -LiteralPath $DatabasePath -Destination $target -Force
    foreach ($suffix in @('-wal','-shm','-journal')) {
        $sidecar = $DatabasePath + $suffix
        if (Test-Path -LiteralPath $sidecar) { Copy-Item -LiteralPath $sidecar -Destination ($target + $suffix) -Force }
    }
    return [pscustomobject]@{ Root = $tempRoot; DatabasePath = $target }
}

function Get-SqlBakJobsFromSqlite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$DatabasePath
    )
    $sqliteDll = Join-Path $InstallDir 'System.Data.SQLite.dll'
    if (-not (Test-Path -LiteralPath $sqliteDll)) { throw "System.Data.SQLite.dll nao encontrada: $sqliteDll" }
    if (-not (Test-Path -LiteralPath $DatabasePath)) { throw "Banco de configuracao nao encontrado: $DatabasePath" }
    $sqliteSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath $sqliteDll
    if(-not $sqliteSecurity.IsSafe){throw ('DLL SQLite recusada por segurança: '+($sqliteSecurity.Issues -join '; '))}

    $snapshot = Copy-SqliteDatabaseSnapshot -DatabasePath $DatabasePath
    try {
        if (-not ([System.Management.Automation.PSTypeName]'System.Data.SQLite.SQLiteConnection').Type) {
            Add-Type -Path $sqliteDll -ErrorAction Stop
        }
        $connection = New-Object System.Data.SQLite.SQLiteConnection(('Data Source={0};Version=3;Read Only=True;Pooling=False;' -f $snapshot.DatabasePath))
        $connection.Open()
        try {
            $tableCommand = $connection.CreateCommand()
            $tableCommand.CommandText = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            $reader = $tableCommand.ExecuteReader()
            $tables = New-Object System.Collections.Generic.List[string]
            while ($reader.Read()) { $tables.Add([string]$reader['name']) }
            $reader.Close()

            $selectedTable = $null
            $columns = @()
            foreach ($table in $tables) {
                $pragma = $connection.CreateCommand()
                $safeTable = $table.Replace("'", "''")
                $pragma.CommandText = "PRAGMA table_info('$safeTable')"
                $columnReader = $pragma.ExecuteReader()
                $found = New-Object System.Collections.Generic.List[string]
                while ($columnReader.Read()) { $found.Add([string]$columnReader['name']) }
                $columnReader.Close()
                $nameColumn = @('JobName','Name','Title') | Where-Object { $found -contains $_ } | Select-Object -First 1
                if ($nameColumn -and (($found -contains 'JobType') -or ($table -ieq 'Job'))) {
                    $selectedTable = $table
                    $columns = @($found)
                    break
                }
            }
            if (-not $selectedTable) { throw 'Esquema SQLite nao reconhecido com seguranca.' }

            $nameColumn = @('JobName','Name','Title') | Where-Object { $columns -contains $_ } | Select-Object -First 1
            $idColumn = @('JobId','Id','Oid') | Where-Object { $columns -contains $_ } | Select-Object -First 1
            $typeColumn = @('JobType','Type') | Where-Object { $columns -contains $_ } | Select-Object -First 1
            $scheduledColumn = @('IsScheduled','Scheduled','ScheduleEnabled') | Where-Object { $columns -contains $_ } | Select-Object -First 1
            $lastRunColumn = @('LastRunAt','LastRun','LastRunDate') | Where-Object { $columns -contains $_ } | Select-Object -First 1

            $selectParts = @("[$nameColumn] AS JobName")
            if ($idColumn) { $selectParts += "[$idColumn] AS JobId" } else { $selectParts += "NULL AS JobId" }
            if ($typeColumn) { $selectParts += "[$typeColumn] AS JobType" } else { $selectParts += "NULL AS JobType" }
            if ($scheduledColumn) { $selectParts += "[$scheduledColumn] AS IsScheduled" } else { $selectParts += "NULL AS IsScheduled" }
            if ($lastRunColumn) { $selectParts += "[$lastRunColumn] AS LastRunAt" } else { $selectParts += "NULL AS LastRunAt" }

            $query = $connection.CreateCommand()
            $query.CommandText = 'SELECT {0} FROM [{1}] ORDER BY [{2}]' -f ($selectParts -join ', '), $selectedTable.Replace(']',']]'), $nameColumn.Replace(']',']]')
            $jobReader = $query.ExecuteReader()
            $jobs = New-Object System.Collections.Generic.List[object]
            while ($jobReader.Read()) {
                $name = [string]$jobReader['JobName']
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $rawType = if ($jobReader['JobType'] -is [DBNull]) { $null } else { $jobReader['JobType'] }
                $isBackup = $false
                $typeLabel = 'Desconhecido'
                if ($null -ne $rawType) {
                    if ([string]$rawType -eq '1') { $isBackup = $true; $typeLabel = 'Backup' }
                    elseif ([string]$rawType -match '(?i)backup') { $isBackup = $true; $typeLabel = 'Backup' }
                    elseif ([string]$rawType -match '(?i)restore') { $typeLabel = 'Restore' }
                    elseif ([string]$rawType -match '(?i)maintenance|manuten') { $typeLabel = 'Maintenance' }
                    elseif ([string]$rawType -match '(?i)shipping') { $typeLabel = 'Log Shipping' }
                    else { $typeLabel = 'Outro (' + [string]$rawType + ')' }
                }
                $scheduled = $null
                if (-not ($jobReader['IsScheduled'] -is [DBNull])) {
                    try { $scheduled = [Convert]::ToBoolean($jobReader['IsScheduled']) }
                    catch { $scheduled = ([string]$jobReader['IsScheduled'] -in @('1','true','True','SIM','Sim')) }
                }
                $jobs.Add([pscustomobject][ordered]@{
                    Name = $name
                    Id = if ($jobReader['JobId'] -is [DBNull]) { $null } else { [string]$jobReader['JobId'] }
                    Type = $typeLabel
                    RawType = if ($null -eq $rawType) { $null } else { [string]$rawType }
                    IsBackup = $isBackup
                    IsScheduled = $scheduled
                    LastRunAt = if ($jobReader['LastRunAt'] -is [DBNull]) { $null } else { [string]$jobReader['LastRunAt'] }
                    Source = 'SQLiteValidated'
                    Confidence = if ($isBackup -and ([string]$rawType -match '(?i)backup')) { 'High' } elseif ($isBackup) { 'Medium' } else { 'Medium' }
                    Selectable = $isBackup
                })
            }
            $jobReader.Close()
            return @($jobs)
        }
        finally { $connection.Dispose() }
    }
    finally { Remove-Item -LiteralPath $snapshot.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-SqlBakJobsFromCli {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CliPath)
    if (-not (Test-Path -LiteralPath $CliPath)) { throw "CLI nao encontrada: $CliPath" }
    $output = & $CliPath '-listJobs' 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) { throw "-listJobs retornou codigo ${exit}: $($output -join ' ')" }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($output)) {
        $text = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^[\-\*\d\.\)\s]+(.+)$') { $text = $matches[1].Trim() }
        if ($text -match '(?i)^(jobs?|lista|available|sqlbackupandftp|version|usage|uso)\b') { continue }
        if ($text.Length -gt 0 -and $text.Length -le 250) { $names.Add($text) }
    }
    return @($names | Sort-Object -Unique | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = $_; Id = $null; Type = 'Desconhecido'; RawType = $null; IsBackup = $null;
            IsScheduled = $null; LastRunAt = $null; Source = 'CliListJobsUndocumented';
            Confidence = 'Low'; Selectable = $true
        }
    })
}

function Get-SqlBakJobs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InstallInfo, [switch]$DisableCliFallback)
    $errors = New-Object System.Collections.Generic.List[string]
    $jobs = @()
    $configuredRoot = [string](Get-AutoRunnerPropertyValue -InputObject $InstallInfo -Name 'ConfigRoot' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot) -and (Test-Path -LiteralPath (Join-Path $configuredRoot 'Db\context.db') -PathType Leaf)) {
        $configRoot = [pscustomobject]@{ Path=[IO.Path]::GetFullPath($configuredRoot).TrimEnd('\'); Source='Configured' }
    }
    else { $configRoot = Get-SqlBakConfigurationRoot -InstallDir $InstallInfo.InstallDir }
    $db = Join-Path $configRoot.Path 'Db\context.db'
    if (Test-Path -LiteralPath $db) {
        try { $jobs = @(Get-SqlBakJobsFromSqlite -InstallDir $InstallInfo.InstallDir -DatabasePath $db) }
        catch { $errors.Add('SQLite: ' + $_.Exception.Message) }
    }
    else { $errors.Add("SQLite: context.db nao encontrado em $db") }

    if ($jobs.Count -eq 0 -and -not $DisableCliFallback) {
        try { $jobs = @(Get-SqlBakJobsFromCli -CliPath $InstallInfo.CliPath) }
        catch { $errors.Add('CLI -listJobs: ' + $_.Exception.Message) }
    }
    return [pscustomobject]@{
        Jobs = @($jobs)
        Errors = @($errors)
        ConfigRoot = $configRoot.Path
        ConfigRootSource = $configRoot.Source
        DiscoverySucceeded = ($jobs.Count -gt 0)
        ConfigRootExists = (Test-Path -LiteralPath $db -PathType Leaf)
    }
}

function New-AutoRunnerDefaultConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InstallInfo, [object[]]$Jobs)
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ConfigSchemaVersion
        Product = 'SQLBackupAndFTP AutoRunner'
        AppVersion = $script:AutoRunnerVersion
        InstallId = [Guid]::NewGuid().ToString()
        InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        SqlBackupAndFTP = [pscustomobject][ordered]@{
            InstallDir = $InstallInfo.InstallDir
            CliPath = $InstallInfo.CliPath
            CliVersion = $InstallInfo.CliVersion
            AppPath = $InstallInfo.AppPath
            AppVersion = $InstallInfo.AppVersion
            ServiceName = $InstallInfo.ServiceName
            ServiceDisplayName = $InstallInfo.ServiceDisplayName
            ConfigRoot = $null
        }
        Execution = [pscustomobject][ordered]@{
            StartupDelayMinutes = 5
            MinimumIntervalHours = 12
            RetryCount = 0
            RetryDelayMinutes = 2
            RetryOnCliError = $false
            StopOnFirstFailure = $false
            ServiceWaitSeconds = 300
            SqlServiceWaitSeconds = 300
            SqlServiceWaitMode = 'AnyAutomaticLocal'
            ExecutionTimeLimitHours = 24
            PostJobDelaySeconds = 5
            TaskRestartOnFailure = $false
            TaskRestartCount = 1
            TaskRestartIntervalMinutes = 5
        }
        Logging = [pscustomobject][ordered]@{
            MaxSizeMB = 10
            KeepFiles = 5
            RetentionDays = 90
        }
        Security = [pscustomobject][ordered]@{
            EnforceManifest = $true
            RunnerSha256 = $null
            CoreModuleSha256 = $null
            ManifestSha256 = $null
            SignatureStatus = 'NotChecked'
        }
        Jobs = @($Jobs)
    }
}

function ConvertTo-AutoRunnerCurrentConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Config, [Parameter(Mandatory = $true)]$InstallInfo)
    $schema = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'SchemaVersion' -Default 0
    if([int]$schema -gt $script:ConfigSchemaVersion){throw "Schema de configuração $schema é mais novo que o suportado ($script:ConfigSchemaVersion)."}
    $sourceProduct=[string](Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Product' -Default '')
    if(-not [string]::IsNullOrWhiteSpace($sourceProduct) -and $sourceProduct -ne 'SQLBackupAndFTP AutoRunner'){throw "Configuração pertence a outro produto: $sourceProduct"}
    # Mesmo no schema atual, normaliza propriedades ausentes e aplica valores padrão.

    $jobs = New-Object System.Collections.Generic.List[object]
    # Somente schemas legados, anteriores à exigência de confirmação explícita,
    # recebem confirmação migrada. Um schema atual malformado nunca ganha confiança.
    $legacyConfirmationDefault = ([int]$schema -lt 3)
    $oldJobs = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Jobs' -Default @()
    foreach ($item in @($oldJobs)) {
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                $jobs.Add([pscustomobject][ordered]@{
                    Name=[string]$item; BackupType='Default'; Source='Migrated'; Type='Desconhecido'; IsScheduled=$null; LastRunAt=$null
                    ConfirmedByTechnician=$legacyConfirmationDefault
                    ConfirmedAtUtc=$(if($legacyConfirmationDefault){[DateTime]::UtcNow.ToString('o')}else{$null})
                    ConfirmedBy=$(if($legacyConfirmationDefault){'Migração de schema legado'}else{$null})
                    ConfirmationReason=$(if($legacyConfirmationDefault){'Compatibilidade com configuração anterior à confirmação explícita'}else{'Confirmação ausente em schema atual'})
                })
            }
            continue
        }
        $name = Get-AutoRunnerPropertyValue -InputObject $item -Name 'Name'
        if (-not $name) { continue }
        $jobs.Add([pscustomobject][ordered]@{
            Name = [string]$name
            BackupType = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'BackupType' -Default 'Default')
            Source = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Source' -Default 'Migrated')
            Type = [string](Get-AutoRunnerPropertyValue -InputObject $item -Name 'Type' -Default 'Desconhecido')
            IsScheduled = Get-AutoRunnerPropertyValue -InputObject $item -Name 'IsScheduled'
            LastRunAt = Get-AutoRunnerPropertyValue -InputObject $item -Name 'LastRunAt'
            ConfirmedByTechnician = ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $item -Name 'ConfirmedByTechnician') -Default $legacyConfirmationDefault -Name 'ConfirmedByTechnician'
            ConfirmedAtUtc = Get-AutoRunnerPropertyValue -InputObject $item -Name 'ConfirmedAtUtc'
            ConfirmedBy = Get-AutoRunnerPropertyValue -InputObject $item -Name 'ConfirmedBy'
            ConfirmationReason = Get-AutoRunnerPropertyValue -InputObject $item -Name 'ConfirmationReason'
        })
    }
    foreach ($name in @(Get-AutoRunnerPropertyValue -InputObject $Config -Name 'JobNames' -Default @())) {
        if ($name) {
            $jobs.Add([pscustomobject][ordered]@{
                Name=[string]$name; BackupType='Default'; Source='Migrated'; Type='Desconhecido'; IsScheduled=$null; LastRunAt=$null
                ConfirmedByTechnician=$legacyConfirmationDefault
                ConfirmedAtUtc=$(if($legacyConfirmationDefault){[DateTime]::UtcNow.ToString('o')}else{$null})
                ConfirmedBy=$(if($legacyConfirmationDefault){'Migração de schema legado'}else{$null})
                ConfirmationReason=$(if($legacyConfirmationDefault){'Compatibilidade com configuração anterior à confirmação explícita'}else{'Confirmação ausente em schema atual'})
            })
        }
    }
    $uniqueJobs = @($jobs | Group-Object { ([string]$_.Name).Trim().ToLowerInvariant() } | ForEach-Object { $_.Group | Select-Object -First 1 })
    $new = New-AutoRunnerDefaultConfig -InstallInfo $InstallInfo -Jobs $uniqueJobs

    foreach ($property in @('InstallId','InstalledAtUtc')) {
        $value = Get-AutoRunnerPropertyValue -InputObject $Config -Name $property
        if ($value) { $new.$property = [string]$value }
    }
    $oldExecution = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Execution'
    foreach ($property in @('StartupDelayMinutes','MinimumIntervalHours','RetryCount','RetryDelayMinutes','RetryOnCliError','StopOnFirstFailure','ServiceWaitSeconds','SqlServiceWaitSeconds','SqlServiceWaitMode','ExecutionTimeLimitHours','PostJobDelaySeconds','TaskRestartOnFailure','TaskRestartCount','TaskRestartIntervalMinutes')) {
        $value = Get-AutoRunnerPropertyValue -InputObject $oldExecution -Name $property
        if ($null -eq $value) { $value = Get-AutoRunnerPropertyValue -InputObject $Config -Name $property }
        if ($null -ne $value) { $new.Execution.$property = $value }
    }
    foreach ($booleanProperty in @('RetryOnCliError','StopOnFirstFailure','TaskRestartOnFailure')) {
        $new.Execution.$booleanProperty = ConvertTo-AutoRunnerBoolean -Value $new.Execution.$booleanProperty -Default $false -Name $booleanProperty
    }
    if ([string]$new.Execution.SqlServiceWaitMode -notin @('None','AnyAutomaticLocal','AllAutomaticLocal')) {
        $new.Execution.SqlServiceWaitMode = 'AnyAutomaticLocal'
    }
    $oldLogging = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Logging'
    foreach ($property in @('MaxSizeMB','KeepFiles','RetentionDays')) {
        $value = Get-AutoRunnerPropertyValue -InputObject $oldLogging -Name $property
        if ($null -ne $value) { $new.Logging.$property = $value }
    }
    $oldSql = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'SqlBackupAndFTP'
    $configRoot = Get-AutoRunnerPropertyValue -InputObject $InstallInfo -Name 'ConfigRoot'
    if ([string]::IsNullOrWhiteSpace([string]$configRoot)) { $configRoot = Get-AutoRunnerPropertyValue -InputObject $oldSql -Name 'ConfigRoot' }
    if (-not [string]::IsNullOrWhiteSpace([string]$configRoot)) { $new.SqlBackupAndFTP.ConfigRoot = [string]$configRoot }
    $oldSecurity = Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Security'
    # Integridade é obrigatória no schema atual. Configurações antigas que a desativavam
    # são migradas para o modo seguro, pois o runner é executado como SYSTEM.
    $new.Security.EnforceManifest = $true
    foreach ($securityProperty in @('RunnerSha256','CoreModuleSha256','ManifestSha256','SignatureStatus')) {
        $securityValue = Get-AutoRunnerPropertyValue -InputObject $oldSecurity -Name $securityProperty
        if ($null -ne $securityValue) { $new.Security.$securityProperty = [string]$securityValue }
    }
    $new.UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    return $new
}


function Test-AutoRunnerConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [switch]$RequireSecurityHashes,
        [switch]$RequireExistingCli
    )
    $issues = New-Object System.Collections.Generic.List[string]
    if ([string](Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Product' -Default '') -ne 'SQLBackupAndFTP AutoRunner') { $issues.Add('Produto da configuração inválido.') }
    $schema=0
    try{$schema=[int](Get-AutoRunnerPropertyValue -InputObject $Config -Name 'SchemaVersion' -Default 0)}catch{$issues.Add('Schema da configuração não é numérico.')}
    if($schema -ne $script:ConfigSchemaVersion){$issues.Add("Schema da configuração inválido: $schema; esperado $script:ConfigSchemaVersion.")}
    $installId=[string](Get-AutoRunnerPropertyValue -InputObject $Config -Name 'InstallId' -Default '')
    if([string]::IsNullOrWhiteSpace($installId) -or $installId.Length -gt 200 -or $installId -match '[\x00-\x1F\x7F]'){$issues.Add('InstallId ausente ou inválido.')}

    $sql=Get-AutoRunnerPropertyValue -InputObject $Config -Name 'SqlBackupAndFTP'
    $cliPath=[string](Get-AutoRunnerPropertyValue -InputObject $sql -Name 'CliPath' -Default '')
    if([string]::IsNullOrWhiteSpace($cliPath)){$issues.Add('Caminho da CLI não informado.')}
    elseif($RequireExistingCli -and -not(Test-Path -LiteralPath $cliPath -PathType Leaf)){$issues.Add("CLI não encontrada: $cliPath")}

    $jobs=@(Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Jobs' -Default @())
    if($jobs.Count -eq 0){$issues.Add('Nenhum job configurado.')}
    $seen=@{}
    foreach($job in $jobs){
        $name=([string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'Name' -Default '')).Trim()
        if([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 250 -or $name -match '[\x00-\x1F\x7F]'){$issues.Add("Nome de job inválido: '$name'.");continue}
        $key=$name.ToLowerInvariant();if($seen.ContainsKey($key)){$issues.Add("Job duplicado: '$name'.")}else{$seen[$key]=$true}
        $backupType=[string](Get-AutoRunnerPropertyValue -InputObject $job -Name 'BackupType' -Default 'Default')
        if($backupType -notin @('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')){$issues.Add("Tipo de backup inválido em '$name': $backupType.")}
        try{if(-not(ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmedByTechnician') -Default $false -Name 'ConfirmedByTechnician')){$issues.Add("Job sem confirmação técnica: '$name'.")}}catch{$issues.Add("Confirmação inválida em '$name': $($_.Exception.Message)")}
        $scheduled=Get-AutoRunnerPropertyValue -InputObject $job -Name 'IsScheduled'
        if($null -ne $scheduled){try{[void](ConvertTo-AutoRunnerBoolean -Value $scheduled -Name 'IsScheduled')}catch{$issues.Add("IsScheduled inválido em '$name'.")}}
    }

    $execution=Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Execution'
    $ranges=@(
        [pscustomobject]@{Name='StartupDelayMinutes';Min=0;Max=120},
        [pscustomobject]@{Name='MinimumIntervalHours';Min=0;Max=720},
        [pscustomobject]@{Name='RetryCount';Min=0;Max=10},
        [pscustomobject]@{Name='RetryDelayMinutes';Min=0;Max=60},
        [pscustomobject]@{Name='ServiceWaitSeconds';Min=0;Max=1800},
        [pscustomobject]@{Name='SqlServiceWaitSeconds';Min=0;Max=1800},
        [pscustomobject]@{Name='ExecutionTimeLimitHours';Min=1;Max=168},
        [pscustomobject]@{Name='PostJobDelaySeconds';Min=0;Max=600},
        [pscustomobject]@{Name='TaskRestartCount';Min=1;Max=10},
        [pscustomobject]@{Name='TaskRestartIntervalMinutes';Min=1;Max=1440}
    )
    foreach($range in $ranges){
        $name=[string]$range.Name;$value=Get-AutoRunnerPropertyValue -InputObject $execution -Name $name
        $number=0
        if($null -eq $value -or -not [int]::TryParse([string]$value,[ref]$number) -or $number -lt [int]$range.Min -or $number -gt [int]$range.Max){$issues.Add("$name fora da faixa $($range.Min)..$($range.Max).")}
    }
    foreach($name in @('RetryOnCliError','StopOnFirstFailure','TaskRestartOnFailure')){try{[void](ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $execution -Name $name) -Name $name)}catch{$issues.Add($_.Exception.Message)}}
    $sqlMode=[string](Get-AutoRunnerPropertyValue -InputObject $execution -Name 'SqlServiceWaitMode' -Default '')
    if($sqlMode -notin @('None','AnyAutomaticLocal','AllAutomaticLocal')){$issues.Add("SqlServiceWaitMode inválido: $sqlMode.")}

    $logging=Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Logging'
    foreach($range in @(
        [pscustomobject]@{Name='MaxSizeMB';Min=1;Max=1024},
        [pscustomobject]@{Name='KeepFiles';Min=1;Max=50},
        [pscustomobject]@{Name='RetentionDays';Min=1;Max=3650}
    )){
        $name=[string]$range.Name;$value=Get-AutoRunnerPropertyValue -InputObject $logging -Name $name;$number=0
        if($null -eq $value -or -not [int]::TryParse([string]$value,[ref]$number) -or $number -lt [int]$range.Min -or $number -gt [int]$range.Max){$issues.Add("Logging.$name fora da faixa $($range.Min)..$($range.Max).")}
    }

    $security=Get-AutoRunnerPropertyValue -InputObject $Config -Name 'Security'
    try{if(-not(ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $security -Name 'EnforceManifest') -Default $false -Name 'EnforceManifest')){$issues.Add('EnforceManifest deve permanecer habilitado.')}}catch{$issues.Add($_.Exception.Message)}
    if($RequireSecurityHashes){
        foreach($name in @('RunnerSha256','CoreModuleSha256','ManifestSha256')){
            $value=[string](Get-AutoRunnerPropertyValue -InputObject $security -Name $name -Default '')
            if($value -notmatch '^[A-Fa-f0-9]{64}$'){$issues.Add("Security.$name ausente ou inválido.")}
        }
    }
    return [pscustomobject]@{IsValid=($issues.Count -eq 0);Issues=@($issues)}
}

function Test-AutoRunnerPathIsWithin {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ChildPath, [Parameter(Mandatory = $true)][string]$ParentPath)
    try {
        $child = [IO.Path]::GetFullPath($ChildPath).TrimEnd('\')
        $parent = [IO.Path]::GetFullPath($ParentPath).TrimEnd('\')
        if ($child -ieq $parent) { return $true }
        return $child.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Test-AutoRunnerPathHasReparsePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$StopAtPath = $env:ProgramData
    )
    try {
        $current = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $stop = [IO.Path]::GetFullPath($StopAtPath).TrimEnd('\')
        while ($current.Length -ge $stop.Length) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
            }
            if ($current -ieq $stop) { break }
            $parent = Split-Path -Parent $current
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $current) { break }
            $current = [IO.Path]::GetFullPath($parent).TrimEnd('\')
        }
        return $false
    }
    catch {
        throw ("Não foi possível inspecionar componentes do caminho para detectar reparse points: " + $_.Exception.Message)
    }
}

function New-AutoRunnerPrivilegedScratchDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Prefix)
    if (-not (Test-AutoRunnerIsWindows)) { throw 'Diretório temporário privilegiado é suportado somente no Windows.' }
    if (-not (Test-AutoRunnerAdministrator)) { throw 'Administrador necessário para criar diretório temporário privilegiado.' }
    if ($Prefix -notmatch '^[A-Za-z0-9-]{3,64}$') { throw "Prefixo temporário privilegiado inválido: $Prefix" }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { throw 'Program Files não está disponível.' }
    $base = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "Program Files não encontrado: $base" }
    if (Test-AutoRunnerPathHasReparsePoint -Path $base -StopAtPath ([IO.Path]::GetPathRoot($base))) { throw "Program Files contém junction ou link simbólico: $base" }

    for ($attempt = 0; $attempt -lt 16; $attempt++) {
        $leaf = $Prefix + [Guid]::NewGuid().ToString('N')
        $path = Join-Path $base $leaf
        if (Test-Path -LiteralPath $path) { continue }
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetAccessRuleProtection($true, $false)
        $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        try { $security.SetOwner($administrators) } catch {}
        $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        $propagation = [Security.AccessControl.PropagationFlags]::None
        $allow = [Security.AccessControl.AccessControlType]::Allow
        foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
            $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,$propagation,$allow)
            [void]$security.AddAccessRule($rule)
        }
        try {
            [IO.Directory]::CreateDirectory($path, $security) | Out-Null
            $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
            if (([IO.Path]::GetFullPath((Split-Path -Parent $full)).TrimEnd('\')) -ine $base) { throw "Diretório temporário saiu da raiz privilegiada: $full" }
            if (Test-AutoRunnerTreeHasReparsePoint -Path $full) { throw "Diretório temporário privilegiado contém reparse point: $full" }
            $unsafe = @(Get-AutoRunnerUnsafeAclEntries -Path $full -CurrentOnly)
            if ($unsafe.Count -gt 0) { throw ('Diretório temporário privilegiado permaneceu gravável por identidade ampla: ' + ($unsafe -join '; ')) }
            return $full
        }
        catch {
            try {
                if (Test-Path -LiteralPath $path -PathType Container) { [IO.Directory]::Delete($path, $true) }
            } catch {}
            throw
        }
    }
    throw 'Não foi possível criar um diretório temporário privilegiado.'
}

function Remove-AutoRunnerPrivilegedScratchDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string[]]$AllowedPrefixes)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { throw 'Program Files não está disponível para limpeza privilegiada.' }
    $base = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $parent = [IO.Path]::GetFullPath((Split-Path -Parent $full)).TrimEnd('\')
    if ($parent -ine $base) { throw "Limpeza privilegiada recusada fora da raiz imediata de Program Files: $full" }
    $leaf = Split-Path -Leaf $full
    $matched = $false
    foreach ($prefix in @($AllowedPrefixes)) {
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($leaf.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
            $suffix = $leaf.Substring($prefix.Length)
            if ($suffix -match '^[A-Fa-f0-9]{32}$') { $matched = $true; break }
        }
    }
    if (-not $matched) { throw "Limpeza privilegiada recusada para nome inesperado: $leaf" }
    $inspection = Get-AutoRunnerTreeInspection -Path $full
    if (-not $inspection.InspectionSucceeded) { throw ('Limpeza privilegiada recusada porque a árvore não pôde ser inspecionada: ' + ($inspection.Errors -join '; ')) }
    if ($inspection.HasReparsePoint) { throw ('Limpeza privilegiada recusada: junction ou link simbólico em ' + ($inspection.ReparsePoints -join '; ')) }
    Remove-Item -LiteralPath $full -Recurse -Force
}

function Get-AutoRunnerTreeInspection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $reparsePoints = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $full)) {
            return [pscustomobject]@{ Path=$full; Exists=$false; InspectionSucceeded=$true; HasReparsePoint=$false; ReparsePoints=@(); Errors=@() }
        }
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        $queue.Enqueue($full)
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
            catch { $errors.Add($current + ': ' + $_.Exception.Message); continue }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reparsePoints.Add($item.FullName)
                continue
            }
            if (-not $item.PSIsContainer) { continue }
            $children = @()
            try { $children = @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop) }
            catch { $errors.Add($item.FullName + ': ' + $_.Exception.Message); continue }
            foreach ($child in $children) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $reparsePoints.Add($child.FullName)
                    continue
                }
                if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) }
            }
        }
        return [pscustomobject]@{
            Path = $full
            Exists = $true
            InspectionSucceeded = ($errors.Count -eq 0)
            HasReparsePoint = ($reparsePoints.Count -gt 0)
            ReparsePoints = @($reparsePoints)
            Errors = @($errors)
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{ Path=$Path; Exists=$false; InspectionSucceeded=$false; HasReparsePoint=$false; ReparsePoints=@(); Errors=@($errors) }
    }
}

function Test-AutoRunnerTreeHasReparsePoint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $inspection = Get-AutoRunnerTreeInspection -Path $Path
    if (-not $inspection.InspectionSucceeded) {
        throw ('Não foi possível inspecionar a árvore com segurança: ' + ($inspection.Errors -join '; '))
    }
    return [bool]$inspection.HasReparsePoint
}

function Remove-AutoRunnerTreeNoFollow {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$IgnoreMissing)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full)) {
        if ($IgnoreMissing) { return }
        throw "Caminho não encontrado: $full"
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($item.PSIsContainer) { [IO.Directory]::Delete($full, $false) }
        else { [IO.File]::Delete($full) }
        return
    }
    if ($item.PSIsContainer) {
        foreach ($child in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)) {
            Remove-AutoRunnerTreeNoFollow -Path $child.FullName
        }
        [IO.Directory]::Delete($full, $false)
        return
    }
    try { [IO.File]::SetAttributes($full, [IO.FileAttributes]::Normal) } catch {}
    [IO.File]::Delete($full)
}

function Test-AutoRunnerSupportPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$RequireExactDefault)
    try {
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $programData = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')
        $default = [IO.Path]::GetFullPath($script:DefaultSupportDir).TrimEnd('\')
        if ($RequireExactDefault -and $full -ine $default) { return $false }
        if ($full -ieq $programData) { return $false }
        $prefix = $programData + '\'
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        if (Test-AutoRunnerPathHasReparsePoint -Path $full -StopAtPath $programData) { return $false }
        return $true
    }
    catch { return $false }
}

function Get-AutoRunnerUnsafeAclEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$DenyAnyBroadRead, [switch]$CurrentOnly)
    $issues = New-Object System.Collections.Generic.List[string]
    $broadPattern = '(?i)(^|\\)(S-1-1-0|Everyone|Todos|S-1-5-11|Authenticated Users|Usuários autenticados|Usuarios autenticados|S-1-5-32-545|Users|Usuários|Usuarios)$'
    # Use somente direitos atômicos de escrita. Modify e FullControl são valores
    # compostos que também contêm bits de leitura. Ao incluí-los na máscara, uma
    # ACE legítima ReadAndExecute podia ser classificada falsamente como gravável,
    # bloqueando a instalação em Program Files mesmo depois do icacls aplicar RX.
    $writeMask = [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    $targets = New-Object System.Collections.Generic.List[string]
    $targets.Add($Path)
    if (-not $CurrentOnly -and (Test-Path -LiteralPath $Path -PathType Container)) {
        foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)) { $targets.Add($item.FullName) }
    }
    foreach ($target in @($targets | Sort-Object -Unique)) {
        $acl = Get-Acl -LiteralPath $target -ErrorAction Stop
        foreach ($entry in @($acl.Access)) {
            $identity = [string]$entry.IdentityReference.Value
            if ($identity -notmatch $broadPattern -or $entry.AccessControlType -ne 'Allow') { continue }
            if ($DenyAnyBroadRead -or (($entry.FileSystemRights -band $writeMask) -ne 0)) {
                $issues.Add("$target | $identity | $($entry.FileSystemRights) | herdado=$($entry.IsInherited)")
            }
        }
    }
    return @($issues)
}

function Protect-AutoRunnerDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-AutoRunnerSupportPath -Path $Path)) { throw "Caminho de suporte inseguro: $Path" }
    # 3.0.0-RC: requisito explícito de produto. A mesma política FullControl aplicada
    # ao diretório do aplicativo também se aplica a ProgramData e seus recursos.
    return Set-AutoRunnerProductFullControlAcl -Path $Path
}

function Get-AutoRunnerInstalledState {
    [CmdletBinding()]
    param(
        [string]$SupportDir = $script:DefaultSupportDir,
        [string]$TaskName = $script:DefaultTaskName,
        [string]$TaskPath = $script:DefaultTaskPath
    )
    $configPath = Join-Path $SupportDir 'config.json'
    $statePath = Join-Path $SupportDir 'state.json'
    $config = $null
    $state = $null
    $errors = New-Object System.Collections.Generic.List[string]
    try { $config = Read-AutoRunnerJson -Path $configPath -AllowMissing } catch { $errors.Add('Configuração: ' + $_.Exception.Message) }
    try { if(Test-Path -LiteralPath $statePath -PathType Leaf){$state = Read-AutoRunnerState -Path $statePath} } catch { $errors.Add('Estado: ' + $_.Exception.Message) }
    $task = $null
    if (Test-AutoRunnerIsWindows) {
        try { $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop }
        catch { $task = $null }
    }
    return [pscustomobject]@{
        HasConfiguration = ($null -ne $config)
        HasTask = ($null -ne $task)
        IsInstalled = ($null -ne $config -and $null -ne $task)
        IsComplete = ($null -ne $config -and $null -ne $task)
        SupportDir = $SupportDir
        Config = $config
        State = $state
        Task = $task
        ConfigPath = $configPath
        StatePath = $statePath
        Errors = @($errors)
    }
}

function Ensure-AutoRunnerTaskFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TaskPath)
    if ([string]::IsNullOrWhiteSpace($TaskPath) -or $TaskPath -eq '\') { return }
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $currentFolder = $service.GetFolder('\')
    foreach ($segment in $TaskPath.Trim('\').Split('\')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        try { $currentFolder = $currentFolder.GetFolder($segment) }
        catch { $currentFolder = $currentFolder.CreateFolder($segment, $null) }
    }
}

function Register-AutoRunnerScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SupportDir,
        [Parameter(Mandatory = $true)]$Config,
        [string]$TaskName = $script:DefaultTaskName,
        [string]$TaskPath = $script:DefaultTaskPath
    )
    if (-not (Test-AutoRunnerAdministrator)) { throw 'Administrador necessario para registrar tarefa.' }
    $runner = Join-Path $SupportDir 'scripts\Run-SQLBackupAndFTPJob.ps1'
    if (-not (Test-Path -LiteralPath $runner)) { throw "Runner nao encontrado: $runner" }
    $powershell = Get-AutoRunnerWindowsPowerShellPath
    $arguments = Join-AutoRunnerProcessArguments -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runner,'-Trigger','Startup','-SupportDir',$SupportDir)
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $SupportDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $delayMinutes = [int]$Config.Execution.StartupDelayMinutes
    if ($delayMinutes -gt 0) { $trigger.Delay = 'PT{0}M' -f $delayMinutes }
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settingsParams = @{
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
        StartWhenAvailable = $true
        MultipleInstances = 'IgnoreNew'
        ExecutionTimeLimit = (New-TimeSpan -Hours ([int]$Config.Execution.ExecutionTimeLimitHours))
    }
    if ([bool]$Config.Execution.TaskRestartOnFailure) {
        $restartCount = [int]$Config.Execution.TaskRestartCount
        $restartInterval = [int]$Config.Execution.TaskRestartIntervalMinutes
        if ($restartCount -lt 1) { throw 'TaskRestartCount deve ser maior que zero quando o reinício da tarefa estiver habilitado.' }
        if ($restartInterval -lt 1) { throw 'TaskRestartIntervalMinutes deve ser maior que zero quando o reinício da tarefa estiver habilitado.' }
        $settingsParams.RestartCount = $restartCount
        $settingsParams.RestartInterval = (New-TimeSpan -Minutes $restartInterval)
    }
    $settings = New-ScheduledTaskSettingsSet @settingsParams
    Ensure-AutoRunnerTaskFolder -TaskPath $TaskPath
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description ('Executa jobs selecionados do SQLBackupAndFTP no boot. AutoRunner {0}.' -f $script:AutoRunnerVersion)
    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -InputObject $task -Force | Out-Null
    return Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
}

function Register-AutoRunnerUninstallEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SupportDir)
    $applicationDir=Get-AutoRunnerApplicationInstallDir
    if($applicationDir){ return }
    $key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SQLBackupAndFTPAuto'
    New-Item -Path $key -Force | Out-Null
    $ps = Get-AutoRunnerWindowsPowerShellPath
    $manager = Join-Path $SupportDir 'scripts\Manager.ps1'
    $uninstall = (ConvertTo-AutoRunnerProcessArgument -Value $ps) + ' ' + (Join-AutoRunnerProcessArguments -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$manager,'-Action','Uninstall','-SupportDir',$SupportDir))
    $repair = (ConvertTo-AutoRunnerProcessArgument -Value $ps) + ' ' + (Join-AutoRunnerProcessArguments -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$manager,'-Action','Repair','-SupportDir',$SupportDir))
    New-ItemProperty -Path $key -Name DisplayName -Value 'SQLBackupAndFTP AutoRunner' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name DisplayVersion -Value $script:AutoRunnerVersion -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name Publisher -Value 'Alpha Software' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name InstallLocation -Value $SupportDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name UninstallString -Value $uninstall -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name QuietUninstallString -Value $uninstall -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name ModifyPath -Value $repair -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name InstallDate -Value (Get-Date -Format 'yyyyMMdd') -PropertyType String -Force | Out-Null
    $icon = Join-Path $SupportDir 'assets\AutoRunner.ico'
    if (Test-Path -LiteralPath $icon) { New-ItemProperty -Path $key -Name DisplayIcon -Value $icon -PropertyType String -Force | Out-Null }
    $sizeMeasure = Get-ChildItem -LiteralPath $SupportDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    $sizeBytes = if ($null -ne $sizeMeasure.Sum) { [int64]$sizeMeasure.Sum } else { 0 }
    $estimatedKB = [int]([math]::Ceiling($sizeBytes / 1KB))
    New-ItemProperty -Path $key -Name EstimatedSize -Value $estimatedKB -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name NoModify -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name NoRepair -Value 0 -PropertyType DWord -Force | Out-Null
}

function New-AutoRunnerShortcut {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SupportDir)
    $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Alpha Software'
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    $shortcutPath = Join-Path $startMenu 'SQLBackupAndFTP AutoRunner.lnk'
    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $launcher=Get-AutoRunnerLauncherPath
        if($launcher){
            $shortcut.TargetPath=$launcher
            $shortcut.Arguments=''
            $shortcut.WorkingDirectory=Split-Path -Parent $launcher
        }
        else{
            $shortcut.TargetPath = Get-AutoRunnerWindowsPowerShellPath
            $shortcut.Arguments = Join-AutoRunnerProcessArguments -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $SupportDir 'scripts\Manager.ps1'),'-SupportDir',$SupportDir)
            $shortcut.WorkingDirectory = $SupportDir
        }
        $shortcut.Description = 'Gerenciar SQLBackupAndFTP AutoRunner'
        $app = Join-Path $SupportDir 'assets\AutoRunner.ico'
        if (Test-Path -LiteralPath $app) { $shortcut.IconLocation = $app }
        $shortcut.Save()
    }
    finally {
        if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
    return $shortcutPath
}

function Remove-AutoRunnerIntegration {
    [CmdletBinding()]
    param(
        [string]$TaskName = $script:DefaultTaskName,
        [string]$TaskPath = $script:DefaultTaskPath
    )
    try { Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue } catch {}
    try { Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    if(-not (Get-AutoRunnerApplicationInstallDir)){
        Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SQLBackupAndFTPAuto' -Recurse -Force -ErrorAction SilentlyContinue
        $shortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Alpha Software\SQLBackupAndFTP AutoRunner.lnk'
        Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
        $shortcutFolder = Split-Path -Parent $shortcut
        if (Test-Path -LiteralPath $shortcutFolder) {
            if (@(Get-ChildItem -LiteralPath $shortcutFolder -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $shortcutFolder -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($TaskPath -ne '\') {
        try {
            $scheduler = New-Object -ComObject 'Schedule.Service'
            $scheduler.Connect()
            $normalized = $TaskPath.Trim('\')
            $separator = $normalized.LastIndexOf('\')
            if ($separator -ge 0) {
                $parentTaskPath = '\' + $normalized.Substring(0, $separator)
                $leaf = $normalized.Substring($separator + 1)
            }
            else {
                $parentTaskPath = '\'
                $leaf = $normalized
            }
            $parentFolder = $scheduler.GetFolder($parentTaskPath)
            $targetFolder = $parentFolder.GetFolder($leaf)
            if ($targetFolder.GetTasks(0).Count -eq 0 -and $targetFolder.GetFolders(0).Count -eq 0) {
                $parentFolder.DeleteFolder($leaf, 0)
            }
        } catch {}
    }
}

function Test-AutoRunnerInstallation {
    [CmdletBinding()]
    param(
        [string]$SupportDir = $script:DefaultSupportDir,
        [string]$TaskName = $script:DefaultTaskName,
        [string]$TaskPath = $script:DefaultTaskPath
    )
    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
        $checks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    }

    $supportExists = Test-Path -LiteralPath $SupportDir -PathType Container
    Add-Check 'Diretório de suporte' $supportExists $SupportDir
    if ($supportExists) {
        try {
            $supportItem = Get-Item -LiteralPath $SupportDir -Force
            Add-Check 'Diretório não é reparse point' (($supportItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) ([string]$supportItem.Attributes)
            Add-Check 'Árvore sem reparse points' (-not (Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir)) 'Verificação recursiva de junctions e links simbólicos'
        } catch { Add-Check 'Diretório não é reparse point' $false $_.Exception.Message }
    }

    $configPath = Join-Path $SupportDir 'config.json'
    $config = $null
    try { $config = Read-AutoRunnerJson -Path $configPath; Add-Check 'Configuração JSON' $true $configPath }
    catch { Add-Check 'Configuração JSON' $false $_.Exception.Message }

    foreach ($relative in @(
        'scripts\Run-SQLBackupAndFTPJob.ps1',
        'scripts\Manager.ps1',
        'scripts\Install-SQLBackupAndFTP-Auto.ps1',
        'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1',
        'modules\AutoRunner.Core.psm1',
        'manifest.json'
    )) {
        $full = Join-Path $SupportDir $relative
        Add-Check $relative (Test-Path -LiteralPath $full -PathType Leaf) $full
    }

    $manifestPath = Join-Path $SupportDir 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifestObject = Read-AutoRunnerJson -Path $manifestPath
            Add-Check 'Produto do manifesto' ([string]$manifestObject.Product -eq 'SQLBackupAndFTP AutoRunner') ([string]$manifestObject.Product)
            Add-Check 'Versão do manifesto' ([string]$manifestObject.Version -eq $script:AutoRunnerVersion) ([string]$manifestObject.Version)
            $manifest = Test-AutoRunnerManifest -RootPath $SupportDir -ManifestPath $manifestPath
            Add-Check 'Integridade do manifesto' $manifest.IsValid ($manifest.Issues -join '; ')
        } catch { Add-Check 'Integridade do manifesto' $false $_.Exception.Message }
    }

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
        Add-Check 'Tarefa agendada' $true ($TaskPath + $TaskName)
        $actionText = (@($task.Actions) | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join '; '
        $actionOk = ($actionText -match [regex]::Escape('Run-SQLBackupAndFTPJob.ps1')) -and ($actionText -match [regex]::Escape($SupportDir))
        Add-Check 'Ação da tarefa' $actionOk $actionText
        try {
            [xml]$taskXml = Export-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            $ns = New-Object Xml.XmlNamespaceManager($taskXml.NameTable)
            $ns.AddNamespace('t', $taskXml.DocumentElement.NamespaceURI)
            $userId = [string]$taskXml.SelectSingleNode('//t:Principals/t:Principal/t:UserId', $ns).InnerText
            $runLevel = [string]$taskXml.SelectSingleNode('//t:Principals/t:Principal/t:RunLevel', $ns).InnerText
            $bootTrigger = $taskXml.SelectSingleNode('//t:Triggers/t:BootTrigger', $ns)
            $multipleInstances = [string]$taskXml.SelectSingleNode('//t:Settings/t:MultipleInstancesPolicy', $ns).InnerText
            $startWhenAvailable = [string]$taskXml.SelectSingleNode('//t:Settings/t:StartWhenAvailable', $ns).InnerText
            Add-Check 'Tarefa executa como SYSTEM' ($userId -match '(?i)^(SYSTEM|S-1-5-18)$') $userId
            Add-Check 'Tarefa com privilégio máximo' ($runLevel -eq 'HighestAvailable') $runLevel
            Add-Check 'Gatilho de inicialização' ($null -ne $bootTrigger) $(if ($bootTrigger) { 'BootTrigger presente' } else { 'BootTrigger ausente' })
            Add-Check 'Política de instância única' ($multipleInstances -eq 'IgnoreNew') $multipleInstances
            Add-Check 'Iniciar quando disponível' ($startWhenAvailable -match '(?i)^true$') $startWhenAvailable
        } catch { Add-Check 'XML da tarefa' $false $_.Exception.Message }
    } catch { Add-Check 'Tarefa agendada' $false $_.Exception.Message }

    if ($config) {
        try {
            $configValidation=Test-AutoRunnerConfiguration -Config $config -RequireSecurityHashes -RequireExistingCli
            Add-Check 'Validação estrutural da configuração' $configValidation.IsValid ($configValidation.Issues -join '; ')
        } catch { Add-Check 'Validação estrutural da configuração' $false $_.Exception.Message }
        Add-Check 'Produto da configuração' ([string]$config.Product -eq 'SQLBackupAndFTP AutoRunner') ([string]$config.Product)
        Add-Check 'Schema da configuração' ([int]$config.SchemaVersion -eq $script:ConfigSchemaVersion) ('Atual={0}; Esperado={1}' -f $config.SchemaVersion, $script:ConfigSchemaVersion)
        Add-Check 'CLI configurada' (Test-Path -LiteralPath ([string]$config.SqlBackupAndFTP.CliPath) -PathType Leaf) ([string]$config.SqlBackupAndFTP.CliPath)
        try{$cliSecurity=Test-AutoRunnerExecutionPathSecurity -ExecutablePath ([string]$config.SqlBackupAndFTP.CliPath);Add-Check 'Diretório da CLI protegido' $cliSecurity.IsSafe ($cliSecurity.Issues -join '; ')}catch{Add-Check 'Diretório da CLI protegido' $false $_.Exception.Message}
        Add-Check 'Jobs configurados' (@($config.Jobs).Count -gt 0) (('{0} job(s)' -f @($config.Jobs).Count))
        $duplicates = @($config.Jobs | Group-Object { ([string]$_.Name).Trim().ToLowerInvariant() } | Where-Object Count -gt 1)
        Add-Check 'Jobs sem duplicidade' ($duplicates.Count -eq 0) (($duplicates.Name) -join ', ')
        $unconfirmed=New-Object System.Collections.Generic.List[string]
        foreach($job in @($config.Jobs)){
            try{if(-not(ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $job -Name 'ConfirmedByTechnician') -Default $false -Name 'ConfirmedByTechnician')){$unconfirmed.Add([string]$job.Name)}}catch{$unconfirmed.Add(([string]$job.Name)+': '+$_.Exception.Message)}
        }
        Add-Check 'Jobs com confirmação técnica' ($unconfirmed.Count -eq 0) ($unconfirmed -join '; ')
        $mode=[string](Get-AutoRunnerPropertyValue -InputObject $config.Execution -Name 'SqlServiceWaitMode' -Default '')
        Add-Check 'Modo de espera SQL válido' ($mode -in @('None','AnyAutomaticLocal','AllAutomaticLocal')) $mode
        try{
            $retryCli=ConvertTo-AutoRunnerBoolean -Value (Get-AutoRunnerPropertyValue -InputObject $config.Execution -Name 'RetryOnCliError') -Default $false -Name 'RetryOnCliError'
            Add-Check 'Política de repetição da CLI válida' $true ([string]$retryCli)
        }catch{Add-Check 'Política de repetição da CLI válida' $false $_.Exception.Message}

        $security=Get-AutoRunnerPropertyValue -InputObject $config -Name 'Security'
        $hashChecks=@(
            [pscustomobject]@{Name='Hash do runner';Path=(Join-Path $SupportDir 'scripts\Run-SQLBackupAndFTPJob.ps1');Expected=[string](Get-AutoRunnerPropertyValue -InputObject $security -Name 'RunnerSha256' -Default '')},
            [pscustomobject]@{Name='Hash do módulo principal';Path=(Join-Path $SupportDir 'modules\AutoRunner.Core.psm1');Expected=[string](Get-AutoRunnerPropertyValue -InputObject $security -Name 'CoreModuleSha256' -Default '')},
            [pscustomobject]@{Name='Hash do manifesto';Path=(Join-Path $SupportDir 'manifest.json');Expected=[string](Get-AutoRunnerPropertyValue -InputObject $security -Name 'ManifestSha256' -Default '')}
        )
        foreach($hashCheck in $hashChecks){
            $expected=$hashCheck.Expected
            $ok=($expected -match '^[A-Fa-f0-9]{64}$') -and (Test-Path -LiteralPath $hashCheck.Path -PathType Leaf) -and ((Get-AutoRunnerFileHash -Path $hashCheck.Path) -eq $expected.ToUpperInvariant())
            Add-Check $hashCheck.Name $ok $(if($ok){'SHA-256 confere'}else{'Ausente, inválido ou divergente'})
        }
    }

    try {
        $policy=Test-AutoRunnerProductFullControlAcl -Path $SupportDir
        Add-Check 'ACL FullControl 3.0.0-RC no diretório operacional' $policy.IsCompliant ($policy.Issues -join '; ')
    } catch { Add-Check 'ACL FullControl 3.0.0-RC no diretório operacional' $false $_.Exception.Message }

    try {
        $resourceIssues = New-Object System.Collections.Generic.List[string]
        foreach ($relative in @('config.json','state.json','manifest.json','logs','state')) {
            $resourcePath = Join-Path $SupportDir $relative
            if (-not (Test-Path -LiteralPath $resourcePath)) { continue }
            $resourcePolicy=Test-AutoRunnerProductFullControlAcl -Path $resourcePath
            foreach($issue in @($resourcePolicy.Issues)){$resourceIssues.Add("${relative}: $issue")}
        }
        Add-Check 'ACL FullControl em recursos operacionais' ($resourceIssues.Count -eq 0) ($resourceIssues -join '; ')
    } catch { Add-Check 'ACL FullControl em recursos operacionais' $false $_.Exception.Message }

    try {
        $key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SQLBackupAndFTPAuto'
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        $registeredLocation = [string](Get-AutoRunnerPropertyValue -InputObject $entry -Name 'InstallLocation' -Default '')
        $registeredUninstall = [string](Get-AutoRunnerPropertyValue -InputObject $entry -Name 'UninstallString' -Default '')
        $registryOk = -not [string]::IsNullOrWhiteSpace($registeredLocation)
        $registryOk = $registryOk -and (([IO.Path]::GetFullPath($registeredLocation).TrimEnd('\')) -ieq ([IO.Path]::GetFullPath($SupportDir).TrimEnd('\')))
        $registryOk = $registryOk -and -not [string]::IsNullOrWhiteSpace($registeredUninstall)
        $registryOk = $registryOk -and ($registeredUninstall -match [regex]::Escape($SupportDir))
        Add-Check 'Entrada em Aplicativos instalados' $registryOk $registeredUninstall
    } catch { Add-Check 'Entrada em Aplicativos instalados' $false $_.Exception.Message }

    try {
        $shortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Alpha Software\SQLBackupAndFTP AutoRunner.lnk'
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw "Atalho ausente: $shortcutPath" }
        $shell = $null; $shortcut = $null
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcutOk = ([string]$shortcut.Arguments -match [regex]::Escape($SupportDir)) -and (Test-Path -LiteralPath ([string]$shortcut.TargetPath) -PathType Leaf)
            Add-Check 'Atalho do Menu Iniciar' $shortcutOk (([string]$shortcut.TargetPath) + ' ' + ([string]$shortcut.Arguments))
        }
        finally {
            if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
            if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
        }
    } catch { Add-Check 'Atalho do Menu Iniciar' $false $_.Exception.Message }

    return [pscustomobject]@{ IsValid = (@($checks | Where-Object { -not $_.Ok }).Count -eq 0); Checks = @($checks) }
}

function Wait-AutoRunnerService {
    [CmdletBinding()]
    param([string]$Name, [int]$TimeoutSeconds = 300, [string]$LogPath)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') { return $true }
        if ($service -and $service.Status -eq 'Stopped') {
            try { Start-Service -Name $Name -ErrorAction SilentlyContinue } catch {}
        }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds ([Math]::Min(5, [Math]::Max(1, [int][Math]::Ceiling(($deadline-(Get-Date)).TotalSeconds))))
    } while ($true)
    return $false
}

function Wait-AutoRunnerSqlServices {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 300,
        [ValidateSet('None','AnyAutomaticLocal','AllAutomaticLocal')][string]$Mode = 'AnyAutomaticLocal'
    )
    if ($Mode -eq 'None') { return $true }
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.StartMode -eq 'Auto' -and ([string]$_.PathName -match '(?i)sqlservr\.exe')
    })
    if ($services.Count -eq 0) { return $true }
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $TimeoutSeconds))
    while ($true) {
        $running = 0
        foreach ($service in $services) {
            $current = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
            if ($current -and $current.Status -eq 'Running') { $running++; continue }
            if ($current -and $current.Status -eq 'Stopped') { try { Start-Service -Name $service.Name -ErrorAction SilentlyContinue } catch {} }
        }
        if ($Mode -eq 'AnyAutomaticLocal' -and $running -gt 0) { return $true }
        if ($Mode -eq 'AllAutomaticLocal' -and $running -eq $services.Count) { return $true }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds ([Math]::Min(5, [Math]::Max(1, [int][Math]::Ceiling(($deadline-(Get-Date)).TotalSeconds))))
    }
    $finalRunning = 0
    foreach($service in $services){
        $current=Get-Service -Name $service.Name -ErrorAction SilentlyContinue
        if($current -and $current.Status -eq 'Running'){$finalRunning++}
    }
    if ($Mode -eq 'AnyAutomaticLocal') { return ($finalRunning -gt 0) }
    return ($finalRunning -eq $services.Count)
}

function Get-AutoRunnerStateTemplate {
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        LastRunStartedUtc = $null
        LastRunCompletedUtc = $null
        LastSuccessfulRunUtc = $null
        LastResult = 'Nunca executado'
        LastExitCode = $null
        LastTrigger = $null
        Jobs = @()
    }
}

function ConvertTo-AutoRunnerCurrentState {
    [CmdletBinding()]
    param([AllowNull()]$State)
    $normalized = Get-AutoRunnerStateTemplate
    if ($null -eq $State -or $State -is [string] -or $State -is [ValueType]) { return $normalized }
    foreach ($name in @('LastRunStartedUtc','LastRunCompletedUtc','LastSuccessfulRunUtc','LastResult','LastExitCode','LastTrigger')) {
        $value = Get-AutoRunnerPropertyValue -InputObject $State -Name $name
        if ($null -ne $value) { $normalized.$name = $value }
    }
    $jobs = Get-AutoRunnerPropertyValue -InputObject $State -Name 'Jobs' -Default @()
    if ($jobs -is [string] -or $jobs -is [ValueType]) { $jobs = @() }
    $normalized.Jobs = @($jobs)
    return $normalized
}

function Read-AutoRunnerState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $state = Read-AutoRunnerJson -Path $Path -AllowMissing
        return ConvertTo-AutoRunnerCurrentState -State $state
    }
    catch {
        $backupPath = $Path + '.bak'
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            try {
                $backupState = ConvertTo-AutoRunnerCurrentState -State (Read-AutoRunnerJson -Path $backupPath)
                $corruptPath = $Path + '.corrupt.' + (Get-Date -Format 'yyyyMMdd_HHmmss')
                if (Test-Path -LiteralPath $Path -PathType Leaf) { Move-Item -LiteralPath $Path -Destination $corruptPath -Force -ErrorAction SilentlyContinue }
                Write-AutoRunnerJsonAtomic -InputObject $backupState -Path $Path -Depth 20
                return $backupState
            }
            catch {}
        }
        throw
    }
}

function Test-AutoRunnerMinimumInterval {
    [CmdletBinding()]
    param($State, [int]$MinimumIntervalHours)
    if ($MinimumIntervalHours -le 0) { return [pscustomobject]@{ ShouldRun = $true; Remaining = [TimeSpan]::Zero } }
    $lastSuccessful = Get-AutoRunnerPropertyValue -InputObject $State -Name 'LastSuccessfulRunUtc'
    if (-not $lastSuccessful) { return [pscustomobject]@{ ShouldRun = $true; Remaining = [TimeSpan]::Zero } }
    try { $last = [DateTime]::Parse([string]$lastSuccessful).ToUniversalTime() }
    catch { return [pscustomobject]@{ ShouldRun = $true; Remaining = [TimeSpan]::Zero } }
    $next = $last.AddHours($MinimumIntervalHours)
    $remaining = $next - [DateTime]::UtcNow
    if ($remaining.TotalSeconds -le 0) { $remaining = [TimeSpan]::Zero }
    return [pscustomobject]@{ ShouldRun = ($remaining.TotalSeconds -le 0); Remaining = $remaining }
}

function Invoke-SqlBakJobCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$JobName,
        [ValidateSet('Default','Full','FullCopy','Diff','TranLog','TranLogCopy')][string]$BackupType = 'Default'
    )
    $arguments = @('-runJob','-jobName',$JobName)
    if ($BackupType -ne 'Default') { $arguments += @('-backupType',$BackupType) }
    $started = Get-Date
    $output = & $CliPath @arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
        StartedAt = $started
        CompletedAt = Get-Date
        DurationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        Arguments = @($arguments)
    }
}

function Export-AutoRunnerDiagnostics {
    [CmdletBinding()]
    param(
        [string]$SupportDir = $script:DefaultSupportDir,
        [string]$DestinationDirectory = ([Environment]::GetFolderPath('Desktop')),
        [string]$TaskName = $script:DefaultTaskName,
        [string]$TaskPath = $script:DefaultTaskPath
    )
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if((Test-Path -LiteralPath $SupportDir -PathType Container) -and (Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir)){throw "Diagnóstico recusado: a árvore contém junction ou link simbólico: $SupportDir"}
    if(Test-AutoRunnerPathIsWithin -ChildPath $DestinationDirectory -ParentPath $SupportDir){throw 'O destino do diagnóstico não pode ficar dentro da instalação.'}
    $work = Join-Path $env:TEMP ('SQLBackupAndFTPAuto-Diagnostico-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $report = New-Object System.Collections.Generic.List[string]
        $report.Add('SQLBackupAndFTP AutoRunner - Diagnostico')
        $report.Add('Gerado em: ' + (Get-Date).ToString('s'))
        $report.Add('Versao AutoRunner: ' + $script:AutoRunnerVersion)
        $report.Add('Windows: ' + [Environment]::OSVersion.VersionString)
        $report.Add('PowerShell: ' + $PSVersionTable.PSVersion.ToString())
        $report.Add('Computador: ' + $env:COMPUTERNAME)
        $report.Add('Usuario: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
        try {
            $install = Get-SqlBackupAndFTPInstall
            $report.Add('SQLBackupAndFTP: ' + ($install | ConvertTo-Json -Depth 5 -Compress))
            try {
                $discovery = Get-SqlBakJobs -InstallInfo $install
                $report.Add('Descoberta de jobs: ' + ($discovery | ConvertTo-Json -Depth 8 -Compress))
            } catch { $report.Add('Erro descoberta jobs: ' + $_.Exception.Message) }
        } catch { $report.Add('Erro deteccao SQLBackupAndFTP: ' + $_.Exception.Message) }
        try {
            $validation = Test-AutoRunnerInstallation -SupportDir $SupportDir -TaskName $TaskName -TaskPath $TaskPath
            $report.Add('Validacao: ' + ($validation | ConvertTo-Json -Depth 8 -Compress))
        } catch { $report.Add('Erro validacao: ' + $_.Exception.Message) }
        [IO.File]::WriteAllLines((Join-Path $work 'Relatorio.txt'), $report, (New-Object Text.UTF8Encoding($false)))

        foreach ($name in @('config.json','config.json.bak','state.json','manifest.json','install.log','runner.log','manager.log','uninstall.log')) {
            $source = Join-Path $SupportDir $name
            if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $work $name) -Force }
        }
        foreach ($directoryName in @('logs','state')) {
            $sourceDirectory = Join-Path $SupportDir $directoryName
            if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
                Copy-Item -LiteralPath $sourceDirectory -Destination (Join-Path $work $directoryName) -Recurse -Force
            }
        }
        try { Export-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Out-File -LiteralPath (Join-Path $work 'TarefaAgendada.xml') -Encoding UTF8 }
        catch { $_.Exception.ToString() | Out-File -LiteralPath (Join-Path $work 'TarefaAgendada_ERRO.txt') -Encoding UTF8 }
        try { (Get-Acl -LiteralPath $SupportDir | Format-List * | Out-String) | Out-File -LiteralPath (Join-Path $work 'ACL.txt') -Encoding UTF8 } catch {}
        try {
            Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-TaskScheduler/Operational'; StartTime=(Get-Date).AddDays(-7) } -ErrorAction Stop |
                Where-Object { $_.Message -match [regex]::Escape($TaskName) } | Select-Object -First 200 |
                Format-List TimeCreated,Id,LevelDisplayName,Message | Out-File -LiteralPath (Join-Path $work 'Eventos_Tarefa.txt') -Encoding UTF8
        } catch { $_.Exception.ToString() | Out-File -LiteralPath (Join-Path $work 'Eventos_Tarefa_ERRO.txt') -Encoding UTF8 }
        try {
            Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=(Get-Date).AddDays(-7) } -ErrorAction Stop |
                Where-Object { $_.Message -match 'SQLBackupAndFTP|SqlBak|SQLBackupAndFTPAuto' } | Select-Object -First 200 |
                Format-List TimeCreated,Id,ProviderName,LevelDisplayName,Message | Out-File -LiteralPath (Join-Path $work 'Eventos_Aplicacao.txt') -Encoding UTF8
        } catch { $_.Exception.ToString() | Out-File -LiteralPath (Join-Path $work 'Eventos_Aplicacao_ERRO.txt') -Encoding UTF8 }

        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
        $zip = Join-Path $DestinationDirectory ('Diagnostico_SQLBackupAndFTP_AutoRunner_{0}.zip' -f $stamp)
        Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
        return $zip
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Export-ModuleMember -Function *
