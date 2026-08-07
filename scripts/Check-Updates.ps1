#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$IncludePrerelease
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$module=Join-Path $root 'modules\AutoRunner.Core.psm1'
Import-Module $module -Force -DisableNameChecking
try{
    $info=Get-AutoRunnerUpdateInfo -IncludePrerelease:$IncludePrerelease
    $payload=[ordered]@{
        Success=$true
        IsUpdateAvailable=[bool]$info.IsUpdateAvailable
        Current=[string]$info.Current
        Tag=[string]$info.Tag
        DisplayVersion=[string]$info.DisplayVersion
        Name=[string]$info.Name
        PublishedAt=[string]$info.PublishedAt
        HtmlUrl=[string]$info.HtmlUrl
        ReleaseNotes=[string]$info.ReleaseNotes
        Error=''
    }
}catch{
    $payload=[ordered]@{Success=$false;IsUpdateAvailable=$false;Current=(Get-AutoRunnerDisplayVersion);Tag='';DisplayVersion='';Name='';PublishedAt='';HtmlUrl='';ReleaseNotes='';Error=$_.Exception.Message}
}
Write-AutoRunnerJsonAtomic -InputObject $payload -Path $OutputPath -Depth 6
