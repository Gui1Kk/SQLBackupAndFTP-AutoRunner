#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$TaskName = 'SQLBackupAndFTP AutoRunner',
    [string]$TaskPath = '\SQLBackupAndFTPAuto\',
    [switch]$KeepDiagnostics,
    [string]$ArchiveDirectory = ([Environment]::GetFolderPath('Desktop')),
    [switch]$Deferred,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$modulePath = Join-Path $packageRoot 'modules\AutoRunner.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    $modulePath = Join-Path $SupportDir 'modules\AutoRunner.Core.psm1'
}
Import-Module $modulePath -Force -DisableNameChecking
if (-not (Test-AutoRunnerAdministrator)) { throw 'Execute como administrador.' }
if (-not (Test-AutoRunnerSupportPath -Path $SupportDir)) { throw "Recusa de remoção: caminho inesperado ou inseguro: $SupportDir" }
if ((Test-Path -LiteralPath $SupportDir -PathType Container) -and (Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir)) {
    throw "Recusa de remoção: a árvore contém junction ou link simbólico: $SupportDir"
}
if ($KeepDiagnostics -and -not [string]::IsNullOrWhiteSpace($ArchiveDirectory) -and (Test-AutoRunnerPathIsWithin -ChildPath $ArchiveDirectory -ParentPath $SupportDir)) {
    throw 'Recusa de remoção: o diretório do arquivo de diagnóstico não pode ficar dentro da pasta que será excluída.'
}
$configPath = Join-Path $SupportDir 'config.json'
$config = Read-AutoRunnerJson -Path $configPath -AllowMissing
if ($null -eq $config -or [string](Get-AutoRunnerPropertyValue -InputObject $config -Name 'Product') -ne 'SQLBackupAndFTP AutoRunner') {
    throw 'Recusa de remoção: a pasta não contém uma instalação identificável do AutoRunner.'
}

if (-not $Deferred -and (Test-AutoRunnerPathIsWithin -ChildPath $PSCommandPath -ParentPath $SupportDir)) {
    $tempRoot = New-AutoRunnerPrivilegedScratchDirectory -Prefix 'AlphaAutoRunner-AutomationUninstall-'
    $childCode=1
    try {
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'modules') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'scripts') -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $tempRoot 'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1') -Force
        Copy-Item -LiteralPath $modulePath -Destination (Join-Path $tempRoot 'modules\AutoRunner.Core.psm1') -Force
        if(Test-AutoRunnerTreeHasReparsePoint -Path $tempRoot){throw 'Área privada da desinstalação contém junction ou link simbólico.'}
        $unsafe=@(Get-AutoRunnerUnsafeAclEntries -Path $tempRoot -CurrentOnly)
        if($unsafe.Count -gt 0){throw ('Área privada da desinstalação possui escrita ampla: '+($unsafe -join '; '))}
        $ps = Get-AutoRunnerWindowsPowerShellPath
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $tempRoot 'scripts\Uninstall-SQLBackupAndFTP-Auto.ps1'),'-SupportDir',$SupportDir,'-TaskName',$TaskName,'-TaskPath',$TaskPath,'-Deferred')
        if ($KeepDiagnostics) { $args += '-KeepDiagnostics' }
        if ($ArchiveDirectory) { $args += @('-ArchiveDirectory',$ArchiveDirectory) }
        if ($Quiet) { $args += '-Quiet' }
        $argumentLine = Join-AutoRunnerProcessArguments -Arguments $args
        $process = Start-Process -FilePath $ps -ArgumentList $argumentLine -Wait -PassThru
        try{$process.WaitForExit()}catch{}
        try{$process.Refresh()}catch{}
        try{$childCode=[int]$process.ExitCode}catch{$childCode=1}
        # Windows PowerShell/ShellExecute pode expor -1 mesmo após encerramento normal.
        # A ausência do diretório técnico é a pós-condição autoritativa.
        if($childCode -eq -1 -and -not(Test-Path -LiteralPath $SupportDir -PathType Container)){$childCode=0}
    }
    finally {
        try { Remove-AutoRunnerPrivilegedScratchDirectory -Path $tempRoot -AllowedPrefixes @('AlphaAutoRunner-AutomationUninstall-') } catch {}
    }
    exit $childCode
}

$logPath = Join-Path $SupportDir 'logs\uninstall.log'
function Write-UninstallLog {
    param([string]$Message, [string]$Level='INFO')
    try { Write-AutoRunnerLog -Path $logPath -Message $Message -Level $Level -Component 'Uninstaller' -NoConsole:$Quiet }
    catch { if (-not $Quiet) { Write-Host $Message } }
}

try {
    Write-UninstallLog 'Iniciando desinstalação.'
    if ($KeepDiagnostics -and (Test-Path -LiteralPath $SupportDir)) {
        New-Item -ItemType Directory -Path $ArchiveDirectory -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $archive = Join-Path $ArchiveDirectory ("SQLBackupAndFTP_AutoRunner_Arquivos_$stamp.zip")
        $items = @()
        foreach ($name in @('config.json','state.json','manifest.json','logs','state')) {
            $path = Join-Path $SupportDir $name
            if (Test-Path -LiteralPath $path) { $items += $path }
        }
        if ($items.Count -gt 0) {
            Compress-Archive -Path $items -DestinationPath $archive -Force
            Write-UninstallLog ("Diagnóstico preservado em: $archive") 'SUCCESS'
        }
    }

    Remove-AutoRunnerIntegration -TaskName $TaskName -TaskPath $TaskPath
    Write-UninstallLog 'Tarefa e integrações exclusivas da automação removidas.' 'SUCCESS'

    # Verificação final contra junction/symlink, inclusive em diretórios ancestrais,
    # imediatamente antes da exclusão para reduzir risco de troca de caminho durante o processo.
    if (-not (Test-AutoRunnerSupportPath -Path $SupportDir)) { throw 'O caminho de suporte se tornou inseguro; remoção recusada.' }
    $item = Get-Item -LiteralPath $SupportDir -Force -ErrorAction SilentlyContinue
    if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'A pasta se tornou um reparse point; remoção recusada.'
    }
    if ($item -and (Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir)) {
        throw 'A árvore passou a conter junction ou link simbólico; remoção recusada.'
    }

    if (Test-Path -LiteralPath $SupportDir) {
        Remove-Item -LiteralPath $SupportDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $SupportDir) { throw 'A pasta técnica não pôde ser removida.' }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'SQLBackupAndFTP AutoRunner removido com sucesso.' -ForegroundColor Green
        Write-Host 'Os jobs e as configurações do SQLBackupAndFTP não foram alterados.'
    }
    exit 0
}
catch {
    try { Write-UninstallLog $_.Exception.ToString() 'ERROR' } catch {}
    if (-not $Quiet) { Write-Host $_.Exception.Message -ForegroundColor Red }
    exit 1
}
