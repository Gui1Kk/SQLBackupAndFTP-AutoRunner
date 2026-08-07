#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Tag,
    [switch]$NoLaunchAfterUpdate
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$module=Join-Path $root 'modules\AutoRunner.Core.psm1'
Import-Module $module -Force -DisableNameChecking
if(-not(Test-AutoRunnerAdministrator)){throw 'A atualização exige privilégios de administrador.'}
$descriptor=ConvertTo-AutoRunnerReleaseDescriptor -Tag $Tag
if(-not $descriptor){throw "Tag de atualização inválida: $Tag"}
$current=Get-AutoRunnerCurrentReleaseDescriptor
if((Compare-AutoRunnerReleaseDescriptor -Left $descriptor -Right $current) -le 0){throw "A versão solicitada ($($descriptor.Display)) não é mais nova que a versão instalada ($($current.Display))."}

$repo=Get-AutoRunnerRepository
$escaped=[Uri]::EscapeDataString($Tag)
$api='https://api.github.com/repos/'+$repo+'/releases/tags/'+$escaped
$headers=@{'User-Agent'=('SQLBackupAndFTP-AutoRunner-Updater/'+(Get-AutoRunnerVersion));'Accept'='application/vnd.github+json'}
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}catch{}
$release=Invoke-RestMethod -Uri $api -Headers $headers -Method Get -TimeoutSec 12 -ErrorAction Stop
if([bool](Get-AutoRunnerPropertyValue -InputObject $release -Name 'draft' -Default $false)){throw 'A release solicitada ainda está em rascunho.'}
if(([string](Get-AutoRunnerPropertyValue -InputObject $release -Name 'tag_name' -Default '')) -ine $Tag){throw 'A API do GitHub retornou uma tag diferente da solicitada.'}
$assets=@(Get-AutoRunnerPropertyValue -InputObject $release -Name 'assets' -Default @())
$label=$Tag;if($label.StartsWith('v',[StringComparison]::OrdinalIgnoreCase)){$label=$label.Substring(1)}
$setupName='SQLBackupAndFTP-AutoRunner-Setup-v'+$label+'.exe'
$setupAsset=$assets|Where-Object{[string](Get-AutoRunnerPropertyValue -InputObject $_ -Name 'name' -Default '') -ieq $setupName}|Select-Object -First 1
$sumAsset=$assets|Where-Object{[string](Get-AutoRunnerPropertyValue -InputObject $_ -Name 'name' -Default '') -ieq 'SHA256SUMS.txt'}|Select-Object -First 1
if(-not $setupAsset -or -not $sumAsset){throw 'A release não contém o Setup e o SHA256SUMS.txt obrigatórios.'}
$setupUrl=[string](Get-AutoRunnerPropertyValue -InputObject $setupAsset -Name 'browser_download_url' -Default '')
$sumUrl=[string](Get-AutoRunnerPropertyValue -InputObject $sumAsset -Name 'browser_download_url' -Default '')
foreach($url in @($setupUrl,$sumUrl)){
    $uri=[Uri]$url
    if($uri.Scheme -ne 'https' -or $uri.Host -ine 'github.com' -or -not $uri.AbsolutePath.StartsWith('/'+$repo+'/releases/download/',[StringComparison]::OrdinalIgnoreCase)){throw "URL de asset recusada: $url"}
}

# Never place an elevated update payload below the interactive user's writable
# TEMP tree. A low-privilege process could otherwise rename/replace the child via
# permissions on its parent between validation and execution. The operational
# ProgramData root is already protected and is normalized again before use.
$supportRoot=Get-AutoRunnerDefaultSupportDir
if(-not(Test-AutoRunnerSupportPath -Path $supportRoot)){throw "Diretório de suporte inválido para atualização: $supportRoot"}
[void](Protect-AutoRunnerDirectory -Path $supportRoot)
if(Test-AutoRunnerPathHasReparsePoint -Path $supportRoot -StopAtPath ([IO.Path]::GetPathRoot($supportRoot))){throw "Diretório de suporte contém junction ou link simbólico: $supportRoot"}
$work=Join-Path $supportRoot ('.update-'+[Guid]::NewGuid().ToString('N'))
$security=New-Object Security.AccessControl.DirectorySecurity
$security.SetAccessRuleProtection($true,$false)
$inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
foreach($sidText in @('S-1-5-18','S-1-5-32-544')){
    $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
    $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    [void]$security.AddAccessRule($rule)
}
[IO.Directory]::CreateDirectory($work,$security)|Out-Null
$setupPath=Join-Path $work $setupName
$sumPath=Join-Path $work 'SHA256SUMS.txt'
try{
    Invoke-WebRequest -Uri $sumUrl -Headers $headers -UseBasicParsing -TimeoutSec 30 -OutFile $sumPath -ErrorAction Stop
    Invoke-WebRequest -Uri $setupUrl -Headers $headers -UseBasicParsing -TimeoutSec 120 -OutFile $setupPath -ErrorAction Stop
    $expectedHashes=New-Object System.Collections.Generic.List[string]
    foreach($line in @(Get-Content -LiteralPath $sumPath -Encoding UTF8)){
        if($line -match '^([A-Fa-f0-9]{64})\s+\*?(.+)$' -and $Matches[2].Trim() -ieq $setupName){$expectedHashes.Add($Matches[1].ToUpperInvariant())}
    }
    if($expectedHashes.Count -ne 1){throw "SHA256SUMS.txt não contém exatamente uma entrada para $setupName."}
    $actual=(Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expectedHashes[0]){throw "Hash SHA-256 divergente para o instalador baixado. Esperado $($expectedHashes[0]); recebido $actual."}

    $currentSetup=Get-AutoRunnerSetupPath
    $currentSignature=$null;$newSignature=$null
    try{if($currentSetup){$currentSignature=Get-AuthenticodeSignature -FilePath $currentSetup}}catch{}
    try{$newSignature=Get-AuthenticodeSignature -FilePath $setupPath}catch{}
    if($currentSignature -and $currentSignature.Status -eq 'Valid'){
        if(-not $newSignature -or $newSignature.Status -ne 'Valid'){throw 'A instalação atual é assinada, mas a atualização baixada não possui assinatura Authenticode válida.'}
        if($currentSignature.SignerCertificate.Thumbprint -ne $newSignature.SignerCertificate.Thumbprint){throw 'O certificado da atualização é diferente do certificado da instalação atual.'}
    }

    $arguments=@()
    if($NoLaunchAfterUpdate){$arguments+='/nolaunch'}
    $argLine=($arguments -join ' ').Trim()
    $process=if($argLine){Start-Process -FilePath $setupPath -ArgumentList $argLine -Wait -PassThru}else{Start-Process -FilePath $setupPath -Wait -PassThru}
    try{$process.Refresh()}catch{}
    $code=[int]$process.ExitCode
    if($code -notin @(0,1602)){throw "O instalador da atualização encerrou com código $code."}
    exit $code
}
finally{
    try{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}
