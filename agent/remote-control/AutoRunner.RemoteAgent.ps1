#Requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Run')]
param(
 [Parameter(ParameterSetName='Run')][switch]$Run,
 [Parameter(ParameterSetName='Enroll',Mandatory=$true)][switch]$Enroll,
 [Parameter(ParameterSetName='Enroll',Mandatory=$true)][string]$BaseUrl,
 [Parameter(ParameterSetName='Enroll',Mandatory=$true)][string]$Token,
 [Parameter(ParameterSetName='Enroll')][switch]$AllowInsecureTransport,
 [Parameter(ParameterSetName='EnrollFile',Mandatory=$true)][string]$EnrollmentRequestPath,
 [Parameter(ParameterSetName='EnrollFile',Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$EnrollmentRequestSha256,
 [Parameter(ParameterSetName='Install')][switch]$InstallTask,
 [Parameter(ParameterSetName='Uninstall')][switch]$UninstallTask,
 [Parameter(ParameterSetName='Inventory')][switch]$Inventory
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'AutoRunner.RemoteAgent.psm1') -Force -DisableNameChecking

function Read-EnrollmentRequestPinned {
    param([string]$Path,[string]$ExpectedSha256)
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'Arquivo de enrollment não encontrado.'}
    $bytes=[IO.File]::ReadAllBytes($full)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
    if($actual.ToUpperInvariant() -cne $ExpectedSha256.ToUpperInvariant()){throw 'SHA-256 da solicitação de enrollment divergente.'}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    try{return ($text|ConvertFrom-Json -ErrorAction Stop)}catch{throw 'Solicitação de enrollment inválida.'}
}

switch($PSCmdlet.ParameterSetName){
 'Enroll'{
   $identity=Invoke-AgentEnrollment -BaseUrl $BaseUrl -Token $Token -AllowInsecureTransport:$AllowInsecureTransport
   Install-RemoteAgentTask
   $identity|Select-Object AgentId,MachineId,BaseUrl,WsUrl
 }
 'EnrollFile'{
   $request=Read-EnrollmentRequestPinned -Path $EnrollmentRequestPath -ExpectedSha256 $EnrollmentRequestSha256
   if([string]::IsNullOrWhiteSpace([string]$request.BaseUrl) -or [string]::IsNullOrWhiteSpace([string]$request.Token)){throw 'Solicitação de enrollment sem URL ou token.'}
   $identity=Invoke-AgentEnrollment -BaseUrl ([string]$request.BaseUrl) -Token ([string]$request.Token) -AllowInsecureTransport:([bool]$request.AllowInsecureTransport)
   Install-RemoteAgentTask
   $identity|Select-Object AgentId,MachineId,BaseUrl,WsUrl
 }
 'Install'{Install-RemoteAgentTask;Write-Host 'Tarefa do Remote Agent instalada.'}
 'Uninstall'{Uninstall-RemoteAgentTask;Write-Host 'Remote Agent removido.'}
 'Inventory'{Get-RemoteAgentInventory|ConvertTo-Json -Depth 12}
 default{Start-RemoteAgentLoop}
}
