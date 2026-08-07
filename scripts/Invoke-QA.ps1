#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Integration,
    [switch]$KeepArtifacts,
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$module = Join-Path $root 'modules\AutoRunner.Core.psm1'
Import-Module $module -Force -DisableNameChecking
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'test-results' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$reportPath = Join-Path $OutputDirectory ('QA_Windows_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Name,[ValidateSet('PASS','FAIL','SKIP')][string]$Status,[string]$Detail)
    $results.Add([pscustomobject]@{Name=$Name;Status=$Status;Detail=$Detail})
    $color = if ($Status -eq 'PASS') {'Green'} elseif ($Status -eq 'FAIL') {'Red'} else {'Yellow'}
    Write-Host "[$Status] $Name - $Detail" -ForegroundColor $color
}
function Invoke-TestCase {
    param([string]$Name,[scriptblock]$Body)
    try {
        $detail = & $Body
        if ($detail -is [array]) { $detail = $detail -join '; ' }
        Add-Result $Name 'PASS' ([string]$detail)
    }
    catch { Add-Result $Name 'FAIL' $_.Exception.ToString() }
}
function Assert-QA {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

$work = Join-Path $env:TEMP ('SQLBackupAndFTPAuto-QA-' + [Guid]::NewGuid().ToString('N'))
$sim = $null
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    Invoke-TestCase 'Sintaxe PowerShell AST' {
        $errors = New-Object System.Collections.Generic.List[string]
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
            $tokens=$null;$parseErrors=$null
            [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
            foreach ($error in @($parseErrors)) { $errors.Add("$($file.FullName): $($error.Message) linha $($error.Extent.StartLineNumber)") }
        }
        Assert-QA ($errors.Count -eq 0) ($errors -join '; ')
        "Todos os scripts analisados pelo parser nativo: $(@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') }).Count)"
    }

    Invoke-TestCase 'Acesso seguro a propriedade opcional ausente' {
        $entry=[pscustomobject]@{InstallLocation='C:\Exemplo'}
        $display=Get-AutoRunnerPropertyValue -InputObject $entry -Name 'DisplayName' -Default ''
        $location=Get-AutoRunnerPropertyValue -InputObject $entry -Name 'InstallLocation' -Default ''
        Assert-QA ([string]$display -eq '') 'Propriedade ausente não retornou o padrão.'
        Assert-QA ([string]$location -eq 'C:\Exemplo') 'Propriedade existente não foi lida.'
        'StrictMode não provoca falha quando DisplayName não existe.'
    }

    Invoke-TestCase 'Detecção preferencial por SqlBak.Job.Cli.exe' {
        $fakeInstall=Join-Path $work 'SQLBackupAndFTP-Fake'
        New-Item -ItemType Directory -Path $fakeInstall -Force|Out-Null
        [IO.File]::WriteAllBytes((Join-Path $fakeInstall 'SqlBak.Job.Cli.exe'),[byte[]](77,90,0,0))
        [IO.File]::WriteAllBytes((Join-Path $fakeInstall 'SBF.Application.exe'),[byte[]](77,90,0,0))
        $detected=Get-SqlBackupAndFTPInstall -PreferredPath $fakeInstall -AllowNotFound
        Assert-QA ($null -ne $detected) 'Instalação preferencial válida não foi detectada.'
        Assert-QA ([IO.Path]::GetFullPath([string]$detected.InstallDir).TrimEnd('\') -ieq [IO.Path]::GetFullPath($fakeInstall).TrimEnd('\')) 'Diretório detectado diverge do preferencial.'
        Assert-QA ([IO.Path]::GetFileName([string]$detected.CliPath) -ieq 'SqlBak.Job.Cli.exe') 'CLI incorreta.'
        ('Fonte=' + (@($detected.DetectionSources) -join ', '))
    }

    Invoke-TestCase 'Launcher gráfico de produção presente' {
        $launcher=Join-Path $root 'SQLBackupAndFTP-AutoRunner.exe'
        Assert-QA (Test-Path -LiteralPath $launcher -PathType Leaf) 'Launcher não encontrado.'
        $header=[IO.File]::ReadAllBytes($launcher)
        Assert-QA ($header.Length -gt 512 -and $header[0] -eq 77 -and $header[1] -eq 90) 'Launcher não possui cabeçalho PE/MZ.'
        ('Bytes=' + $header.Length)
    }

    Invoke-TestCase 'Escrita JSON atômica e backup' {
        $path=Join-Path $work 'atomic.json'
        Write-AutoRunnerJsonAtomic -InputObject ([pscustomobject]@{A=1;B='ç'}) -Path $path
        Write-AutoRunnerJsonAtomic -InputObject ([pscustomobject]@{A=2}) -Path $path -CreateBackup
        $obj=Read-AutoRunnerJson -Path $path
        Assert-QA ([int]$obj.A -eq 2) 'Conteúdo final incorreto.'
        Assert-QA (Test-Path -LiteralPath ($path+'.bak')) 'Backup não criado.'
        'Conteúdo final e backup validados.'
    }

    Invoke-TestCase 'Validação segura de caminhos' {
        $safe=Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'
        Assert-QA (Test-AutoRunnerSupportPath -Path $safe) 'Caminho padrão recusado.'
        Assert-QA (-not (Test-AutoRunnerSupportPath -Path $env:ProgramData)) 'Raiz ProgramData aceita indevidamente.'
        Assert-QA (-not (Test-AutoRunnerSupportPath -Path ($env:ProgramData+'Outra\SQLBackupAndFTPAuto'))) 'Prefixo falso aceito.'
        Assert-QA (Test-AutoRunnerPathIsWithin -ChildPath (Join-Path $safe 'scripts\x.ps1') -ParentPath $safe) 'Filho válido recusado.'
        Assert-QA (-not (Test-AutoRunnerPathIsWithin -ChildPath ($safe+'2\x.ps1') -ParentPath $safe)) 'Prefixo falso aceito por PathIsWithin.'
        'Caminhos válidos e falsos prefixos tratados.'
    }

    Invoke-TestCase 'Manifesto detecta adulteração' {
        $dir=Join-Path $work 'manifest';New-Item -ItemType Directory -Path $dir -Force|Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'A' -Encoding UTF8
        New-AutoRunnerManifest -RootPath $dir -RelativePaths @('a.txt') -OutputPath (Join-Path $dir 'manifest.json')|Out-Null
        $before=Test-AutoRunnerManifest -RootPath $dir -ManifestPath (Join-Path $dir 'manifest.json') -RequiredPaths @('a.txt')
        Add-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'B'
        $after=Test-AutoRunnerManifest -RootPath $dir -ManifestPath (Join-Path $dir 'manifest.json') -RequiredPaths @('a.txt')
        Assert-QA ($before.IsValid -and -not $after.IsValid) 'Alteração não foi detectada.'
        'Arquivo alterado foi identificado.'
    }

    Invoke-TestCase 'Manifesto rejeita traversal explícito' {
        $dir=Join-Path $work 'manifest-traversal';New-Item -ItemType Directory -Path $dir -Force|Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'A' -Encoding UTF8
        $hash=(Get-FileHash -LiteralPath (Join-Path $dir 'a.txt') -Algorithm SHA256).Hash
        $malicious=[pscustomobject]@{Product='SQLBackupAndFTP AutoRunner';Version=(Get-AutoRunnerVersion);CreatedAtUtc=[DateTime]::UtcNow.ToString('o');Files=@([pscustomobject]@{Path='../a.txt';Sha256=$hash;Length=(Get-Item -LiteralPath (Join-Path $dir 'a.txt')).Length})}
        Write-AutoRunnerJsonAtomic -InputObject $malicious -Path (Join-Path $dir 'manifest.json')
        $test=Test-AutoRunnerManifest -RootPath $dir -ManifestPath (Join-Path $dir 'manifest.json') -RequiredPaths @('a.txt')
        Assert-QA (-not $test.IsValid) 'Traversal do manifesto foi aceito.'
        ($test.Issues -join '; ')
    }

    Invoke-TestCase 'Nomes de artefato evitam colisão simples' {
        $a=Get-AutoRunnerJobArtifactName -JobName 'Backup: Matriz'
        $b=Get-AutoRunnerJobArtifactName -JobName 'Backup? Matriz'
        Assert-QA ($a -ne $b) "Colisão: $a"
        Assert-QA ($a.Length -le 91 -and $b.Length -le 91) 'Nome excessivo.'
        "$a | $b"
    }

    Invoke-TestCase 'Migração de configuração preserva opções' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake'}
        $old=[pscustomobject]@{SchemaVersion=1;InstallId='ID-ANTIGO';Jobs=@('Job A');Execution=[pscustomobject]@{StartupDelayMinutes=17;RetryCount=4};Logging=[pscustomobject]@{MaxSizeMB=20}}
        $new=ConvertTo-AutoRunnerCurrentConfig -Config $old -InstallInfo $install
        Assert-QA ($new.SchemaVersion -eq (Get-AutoRunnerSchemaVersion)) 'Schema não migrado.'
        Assert-QA ($new.InstallId -eq 'ID-ANTIGO') 'InstallId perdido.'
        Assert-QA ($new.Execution.StartupDelayMinutes -eq 17 -and $new.Execution.RetryCount -eq 4) 'Execução perdida.'
        Assert-QA ($new.Logging.MaxSizeMB -eq 20) 'Log perdido.'
        'Schema e propriedades conhecidas preservados.'
    }

    Invoke-TestCase 'Normalização completa mesmo no schema atual' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake'}
        $partial=[pscustomobject]@{SchemaVersion=(Get-AutoRunnerSchemaVersion);Product='SQLBackupAndFTP AutoRunner';InstallId='ID';Jobs=@([pscustomobject]@{Name='Job A';ConfirmedByTechnician=$true})}
        $normalized=ConvertTo-AutoRunnerCurrentConfig -Config $partial -InstallInfo $install
        Assert-QA ($null -ne $normalized.Execution -and $null -ne $normalized.Logging -and $normalized.Jobs[0].BackupType -eq 'Default') 'Propriedades padrão não foram recompostas.'
        'Configuração parcial foi completada com padrões.'
    }

    Invoke-TestCase 'Normalização não inventa confirmação técnica' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake';ConfigRoot='D:\SqlBakConfig'}
        $partial=[pscustomobject]@{SchemaVersion=(Get-AutoRunnerSchemaVersion);Product='SQLBackupAndFTP AutoRunner';InstallId='ID';SqlBackupAndFTP=[pscustomobject]@{ConfigRoot='E:\Anterior'};Jobs=@([pscustomobject]@{Name='Job não confirmado';ConfirmedByTechnician=$false})}
        $normalized=ConvertTo-AutoRunnerCurrentConfig -Config $partial -InstallInfo $install
        Assert-QA (-not [bool]$normalized.Jobs[0].ConfirmedByTechnician) 'Confirmação falsa foi convertida em verdadeira.'
        Assert-QA ([string]$normalized.SqlBackupAndFTP.ConfigRoot -eq 'D:\SqlBakConfig') 'ConfigRoot detectado não foi preservado.'
        'Confirmação e raiz de configuração preservadas sem elevação indevida de confiança.'
    }

    Invoke-TestCase 'Schema futuro é recusado' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake'}
        $future=[pscustomobject]@{SchemaVersion=((Get-AutoRunnerSchemaVersion)+1);Product='SQLBackupAndFTP AutoRunner';Jobs=@()}
        $thrown=$false
        try{[void](ConvertTo-AutoRunnerCurrentConfig -Config $future -InstallInfo $install)}catch{$thrown=$true}
        Assert-QA $thrown 'Schema futuro foi aceito.'
        'Migração falhou de forma fechada.'
    }

    Invoke-TestCase 'Schema legado recebe confirmação de migração auditável' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake'}
        $legacy=[pscustomobject]@{SchemaVersion=1;Product='SQLBackupAndFTP AutoRunner';InstallId='ID';Jobs=@('Job legado')}
        $normalized=ConvertTo-AutoRunnerCurrentConfig -Config $legacy -InstallInfo $install
        Assert-QA ([bool]$normalized.Jobs[0].ConfirmedByTechnician) 'Compatibilidade legada não preservada.'
        Assert-QA ([string]$normalized.Jobs[0].ConfirmationReason -match 'schema legado') 'Migração não foi auditada.'
        'Compatibilidade antiga preservada com motivo explícito.'
    }

    Invoke-TestCase 'Validador estrutural recusa configuração insegura' {
        $install=[pscustomobject]@{InstallDir='C:\Fake';CliPath='C:\Fake\Cli.exe';CliVersion='1';AppPath=$null;AppVersion='1';ServiceName='Fake';ServiceDisplayName='Fake'}
        $cfg=New-AutoRunnerDefaultConfig -InstallInfo $install -Jobs @([pscustomobject]@{Name='Duplicado';BackupType='Default';ConfirmedByTechnician=$true},[pscustomobject]@{Name='duplicado';BackupType='Default';ConfirmedByTechnician=$true})
        $cfg.Execution.StartupDelayMinutes=999
        $cfg.Security.RunnerSha256='x';$cfg.Security.CoreModuleSha256='x';$cfg.Security.ManifestSha256='x'
        $validation=Test-AutoRunnerConfiguration -Config $cfg -RequireSecurityHashes
        Assert-QA (-not $validation.IsValid) 'Configuração inválida foi aceita.'
        Assert-QA (($validation.Issues -join '; ') -match 'duplicado|faixa|Sha256') 'Motivos esperados ausentes.'
        ($validation.Issues -join '; ')
    }

    Invoke-TestCase 'Checksum de pacote detecta arquivo injetado e traversal' {
        $package=Join-Path $work 'package-check';New-Item -ItemType Directory -Path $package -Force|Out-Null
        Set-Content -LiteralPath (Join-Path $package 'a.txt') -Value 'A' -Encoding UTF8
        $hash=(Get-FileHash -LiteralPath (Join-Path $package 'a.txt') -Algorithm SHA256).Hash
        [IO.File]::WriteAllLines((Join-Path $package 'SHA256SUMS.txt'),@("$hash *a.txt"),(New-Object Text.UTF8Encoding($false)))
        Assert-QA (Test-AutoRunnerPackageChecksums -RootPath $package).IsValid 'Pacote válido foi recusado.'
        Set-Content -LiteralPath (Join-Path $package 'injetado.txt') -Value 'X' -Encoding UTF8
        Assert-QA (-not (Test-AutoRunnerPackageChecksums -RootPath $package).IsValid) 'Arquivo injetado não foi detectado.'
        Remove-Item -LiteralPath (Join-Path $package 'injetado.txt') -Force
        Set-Content -LiteralPath (Join-Path $package 'injetado.bak') -Value 'X' -Encoding UTF8
        Assert-QA (-not (Test-AutoRunnerPackageChecksums -RootPath $package).IsValid) 'Arquivo .bak injetado foi ignorado.'
        Remove-Item -LiteralPath (Join-Path $package 'injetado.bak') -Force
        [IO.File]::WriteAllLines((Join-Path $package 'SHA256SUMS.txt'),@("$hash *..\a.txt"),(New-Object Text.UTF8Encoding($false)))
        Assert-QA (-not (Test-AutoRunnerPackageChecksums -RootPath $package).IsValid) 'Traversal não foi detectado.'
        'Completude e limite de caminho validados.'
    }

    Invoke-TestCase 'Cálculo de intervalo mínimo' {
        $state=Get-AutoRunnerStateTemplate;$state.LastSuccessfulRunUtc=[DateTime]::UtcNow.ToString('o')
        $interval=Test-AutoRunnerMinimumInterval -State $state -MinimumIntervalHours 12
        Assert-QA (-not $interval.ShouldRun) 'Intervalo não bloqueou.'
        ('Restante=' + $interval.Remaining)
    }

    # Os testes práticos do runner exigem ProgramData/ACL/execução administrativa.
    # Sem -Integration são marcados como SKIP, nunca como aprovação implícita.
    if ($Integration) {
    # Ambiente de simulação do runner.
    $sim=Join-Path $env:ProgramData ('SQLBackupAndFTPAuto-QA-Sim-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $sim 'modules') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sim 'scripts') -Force|Out-Null
    Copy-Item -LiteralPath $module -Destination (Join-Path $sim 'modules\AutoRunner.Core.psm1') -Force
    foreach($scriptName in @('Run-SQLBackupAndFTPJob.ps1','Manager.ps1','Install-SQLBackupAndFTP-Auto.ps1','Uninstall-SQLBackupAndFTP-Auto.ps1','Export-Diagnostics.ps1','Invoke-QA.ps1')){
        Copy-Item -LiteralPath (Join-Path $root ('scripts\'+$scriptName)) -Destination (Join-Path $sim ('scripts\'+$scriptName)) -Force
    }
    $fake=Join-Path $sim 'fake-cli.exe'
    $fakeSource=@'
using System;
using System.IO;
using System.Linq;
using System.Threading;
public static class FakeCli {
  public static int Main(string[] args) {
    string root = AppDomain.CurrentDomain.BaseDirectory;
    string joined = String.Join(" | ", args);
    File.AppendAllText(Path.Combine(root, "calls.log"), joined + Environment.NewLine);
    Console.WriteLine("ARGS=" + joined);
    if (args.Any(a => a.IndexOf("Dormir", StringComparison.OrdinalIgnoreCase) >= 0)) Thread.Sleep(6000);
    if (args.Any(a => a.IndexOf("Recuperar", StringComparison.OrdinalIgnoreCase) >= 0)) {
      string marker = Path.Combine(root, "retry-once.marker");
      if (!File.Exists(marker)) { File.WriteAllText(marker, "1"); return 7; }
    }
    return args.Any(a => a.IndexOf("Falhar", StringComparison.OrdinalIgnoreCase) >= 0) ? 7 : 0;
  }
}
'@
    Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fake -OutputType ConsoleApplication
    $install=[pscustomobject]@{InstallDir=$sim;CliPath=$fake;CliVersion='FAKE';AppPath=$null;AppVersion='FAKE';ServiceName=$null;ServiceDisplayName=$null}
    $ps=Get-AutoRunnerWindowsPowerShellPath

    $manifestFiles=@('modules\AutoRunner.Core.psm1','scripts\Run-SQLBackupAndFTPJob.ps1','scripts\Manager.ps1','scripts\Install-SQLBackupAndFTP-Auto.ps1','scripts\Uninstall-SQLBackupAndFTP-Auto.ps1','scripts\Export-Diagnostics.ps1','scripts\Invoke-QA.ps1')
    $simManifest=Join-Path $sim 'manifest.json'
    New-AutoRunnerManifest -RootPath $sim -RelativePaths $manifestFiles -OutputPath $simManifest|Out-Null
    function New-SimConfig([object[]]$Jobs) {
        $safeJobs=@($Jobs|ForEach-Object{[pscustomobject]@{Name=[string]$_.Name;BackupType=if($_.BackupType){[string]$_.BackupType}else{'Default'};Source='QA';Type='Backup';IsScheduled=$true;LastRunAt=$null;ConfirmedByTechnician=$true;ConfirmedAtUtc=[DateTime]::UtcNow.ToString('o');ConfirmedBy='QA';ConfirmationReason='Teste integrado'}})
        $cfg=New-AutoRunnerDefaultConfig -InstallInfo $install -Jobs $safeJobs
        $cfg.Execution.MinimumIntervalHours=0;$cfg.Execution.RetryCount=0;$cfg.Execution.RetryDelayMinutes=0;$cfg.Execution.RetryOnCliError=$false;$cfg.Execution.PostJobDelaySeconds=0;$cfg.Execution.ServiceWaitSeconds=0;$cfg.Execution.SqlServiceWaitSeconds=0;$cfg.Execution.SqlServiceWaitMode='None'
        $cfg.Security.EnforceManifest=$true
        $cfg.Security.RunnerSha256=Get-AutoRunnerFileHash -Path (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1')
        $cfg.Security.CoreModuleSha256=Get-AutoRunnerFileHash -Path (Join-Path $sim 'modules\AutoRunner.Core.psm1')
        $cfg.Security.ManifestSha256=Get-AutoRunnerFileHash -Path $simManifest
        return $cfg
    }
    function Write-SimConfig($Config){Write-AutoRunnerJsonAtomic -InputObject $Config -Path (Join-Path $sim 'config.json') -Depth 30}
    $initialCfg=New-SimConfig @([pscustomobject]@{Name='Inicial';BackupType='Default'})
    Write-SimConfig $initialCfg
    [void](Protect-AutoRunnerDirectory -Path $sim)
    function Reset-Sim {
        Remove-Item -LiteralPath (Join-Path $sim 'calls.log') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $sim 'retry-once.marker') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $sim 'state.json') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $sim 'state') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $sim 'logs') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $sim 'runner.log') -Force -ErrorAction SilentlyContinue
    }

    Invoke-TestCase 'Runner executa todos os jobs com sucesso' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Sucesso A';BackupType='Default'},[pscustomobject]@{Name='Sucesso B';BackupType='Default'})
        Write-SimConfig $cfg
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Test -Force -SupportDir $sim
        $rc=$LASTEXITCODE;$state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($rc -eq 0 -and @($state.Jobs).Count -eq 2) "Exit=$rc; Jobs=$(@($state.Jobs).Count)"
        'Dois jobs executados.'
    }

    Invoke-TestCase 'Falha de um job não impede o seguinte' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Falhar';BackupType='Default'},[pscustomobject]@{Name='Sucesso posterior';BackupType='Default'})
        Write-SimConfig $cfg
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Test -Force -SupportDir $sim
        $rc=$LASTEXITCODE;$calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'))
        Assert-QA ($rc -eq 10) "Código inesperado: $rc"
        Assert-QA ($calls.Count -eq 2 -and ($calls -join ' ') -match 'Sucesso posterior') 'Segundo job não executou.'
        'Falha parcial reportada e sequência mantida.'
    }

    Invoke-TestCase 'Parar após primeira falha é respeitado' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Falhar';BackupType='Default'},[pscustomobject]@{Name='Não deve chamar';BackupType='Default'})
        $cfg.Execution.StopOnFirstFailure=$true
        Write-SimConfig $cfg
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Test -Force -SupportDir $sim
        $calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'))
        $state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($calls.Count -eq 1) "Chamadas=$($calls.Count)"
        $pending=@($state.Jobs|Where-Object{$_.Result -eq 'Não executado após falha anterior'})
        Assert-QA ($pending.Count -eq 1 -and [int]$pending[0].ExitCode -eq 14) 'Job pendente não foi auditado.'
        'Somente o primeiro job foi chamado e o seguinte foi registrado como não executado.'
    }

    Invoke-TestCase 'Código não zero não repete por padrão na CLI falsa' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Recuperar';BackupType='Default'})
        $cfg.Execution.RetryCount=3;$cfg.Execution.RetryDelayMinutes=0;$cfg.Execution.RetryOnCliError=$false
        Write-SimConfig $cfg
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Test -Force -SupportDir $sim
        $rc=$LASTEXITCODE;$calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'));$state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($rc -eq 11 -and $calls.Count -eq 1) "Exit=$rc; Chamadas=$($calls.Count)"
        Assert-QA ([int]$state.Jobs[0].Attempts -eq 1) "Tentativas=$($state.Jobs[0].Attempts)"
        'A repetição de código de erro permaneceu desabilitada.'
    }

    Invoke-TestCase 'Retentativa opt-in recupera falha transitória real da CLI falsa' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Recuperar';BackupType='Default'})
        $cfg.Execution.RetryCount=1;$cfg.Execution.RetryDelayMinutes=0;$cfg.Execution.RetryOnCliError=$true
        Write-SimConfig $cfg
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Test -Force -SupportDir $sim
        $rc=$LASTEXITCODE;$calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'));$state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($rc -eq 0 -and $calls.Count -eq 2) "Exit=$rc; Chamadas=$($calls.Count)"
        Assert-QA ([int]$state.Jobs[0].Attempts -eq 2) "Tentativas=$($state.Jobs[0].Attempts)"
        'Primeira chamada falhou e a segunda concluiu sem erro de CLI.'
    }

    Invoke-TestCase 'Execução concorrente é ignorada sem código de falha' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Dormir';BackupType='Default'})
        Write-SimConfig $cfg
        $runnerPath=Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1'
        $firstArgs=Join-AutoRunnerProcessArguments -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerPath,'-Trigger','Test','-Force','-SupportDir',$sim)
        $first=Start-Process -FilePath $ps -ArgumentList $firstArgs -PassThru
        $deadline=(Get-Date).AddSeconds(10)
        while(-not (Test-Path -LiteralPath (Join-Path $sim 'calls.log')) -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 200}
        Assert-QA (Test-Path -LiteralPath (Join-Path $sim 'calls.log')) 'A primeira execução não chegou à CLI.'
        & $ps -NoProfile -ExecutionPolicy Bypass -File $runnerPath -Trigger Test -Force -SupportDir $sim
        $secondRc=$LASTEXITCODE
        if(-not $first.WaitForExit(15000)){try{$first.Kill()}catch{};throw 'A primeira execução não finalizou no prazo.'}
        $calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'))
        Assert-QA ($secondRc -eq 13) "Segunda execução manual retornou $secondRc"
        Assert-QA ($first.ExitCode -eq 0 -and $calls.Count -eq 1) "Primeira=$($first.ExitCode); Chamadas=$($calls.Count)"
        'A segunda instância não disparou outro job e retornou código informativo 13.'
    }

    Invoke-TestCase 'Intervalo mínimo individual preserva job bem-sucedido' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Já executado';BackupType='Default'},[pscustomobject]@{Name='Executar agora';BackupType='Default'})
        $cfg.Execution.MinimumIntervalHours=12
        Write-SimConfig $cfg
        $jobStateDir=Join-Path $sim 'state\jobs';New-Item -ItemType Directory -Path $jobStateDir -Force|Out-Null
        $artifact=Get-AutoRunnerJobArtifactName -JobName 'Já executado'
        Write-AutoRunnerJsonAtomic -InputObject ([pscustomobject]@{LastSuccessfulRunUtc=[DateTime]::UtcNow.ToString('o')}) -Path (Join-Path $jobStateDir ($artifact+'.json'))
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Startup -SupportDir $sim
        $rc=$LASTEXITCODE;$calls=@(Get-Content -LiteralPath (Join-Path $sim 'calls.log'));$state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($rc -eq 0) "Exit=$rc"
        Assert-QA ($calls.Count -eq 1 -and ($calls[0] -match 'Executar agora')) "Chamadas=$($calls -join '; ')"
        Assert-QA (@($state.Jobs | Where-Object {$_.Result -eq 'Ignorado pelo intervalo mínimo'}).Count -eq 1) 'Ignorado não registrado.'
        'Job anterior ignorado e job pendente executado.'
    }

    Invoke-TestCase 'Todos os jobs no intervalo encerram normalmente sem chamar CLI' {
        Reset-Sim
        $cfg=New-SimConfig @([pscustomobject]@{Name='Intervalo A';BackupType='Default'},[pscustomobject]@{Name='Intervalo B';BackupType='Default'})
        $cfg.Execution.MinimumIntervalHours=12
        Write-SimConfig $cfg
        $jobStateDir=Join-Path $sim 'state\jobs';New-Item -ItemType Directory -Path $jobStateDir -Force|Out-Null
        foreach($name in @('Intervalo A','Intervalo B')){$artifact=Get-AutoRunnerJobArtifactName -JobName $name;Write-AutoRunnerJsonAtomic -InputObject ([pscustomobject]@{LastSuccessfulRunUtc=[DateTime]::UtcNow.ToString('o')}) -Path (Join-Path $jobStateDir ($artifact+'.json'))}
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sim 'scripts\Run-SQLBackupAndFTPJob.ps1') -Trigger Startup -SupportDir $sim
        $rc=$LASTEXITCODE;$state=Read-AutoRunnerJson -Path (Join-Path $sim 'state.json')
        Assert-QA ($rc -eq 0 -and [int]$state.LastExitCode -eq 12) "Processo=$rc; Estado=$($state.LastExitCode)"
        Assert-QA (-not (Test-Path -LiteralPath (Join-Path $sim 'calls.log'))) 'CLI foi chamada indevidamente.'
        'Condição normal: processo 0, estado informativo 12.'
    }

    Invoke-TestCase 'Estado global corrompido recupera backup' {
        $statePath=Join-Path $work 'recover-state.json'
        Write-AutoRunnerJsonAtomic -InputObject ([pscustomobject]@{LastResult='Bom';LastSuccessfulRunUtc=$null}) -Path $statePath
        Copy-Item -LiteralPath $statePath -Destination ($statePath+'.bak') -Force
        Set-Content -LiteralPath $statePath -Value '{invalido' -Encoding UTF8
        $state=Read-AutoRunnerState -Path $statePath
        Assert-QA ($state.LastResult -eq 'Bom') 'Backup não foi recuperado.'
        Assert-QA (@(Get-ChildItem -LiteralPath (Split-Path -Parent $statePath) -Filter 'recover-state.json.corrupt.*').Count -ge 1) 'Arquivo corrompido não foi preservado.'
        'Estado recuperado e arquivo inválido preservado.'
    }

    Invoke-TestCase 'Rotação de logs' {
        $log=Join-Path $work 'rotate.log'
        [IO.File]::WriteAllBytes($log,(New-Object byte[] (2MB)))
        Invoke-AutoRunnerLogRotation -Path $log -MaxSizeMB 1 -KeepFiles 3 -RetentionDays 90
        Assert-QA (Test-Path -LiteralPath (Join-Path $work 'rotate.1.log')) 'Arquivo rotacionado ausente.'
        'Arquivo acima do limite foi rotacionado.'
    }

    }
    else {
        foreach($skippedRunnerTest in @('Runner com CLI falsa','Concorrência real do runner','Intervalo mínimo real','Tarefa real registra e executa')){Add-Result $skippedRunnerTest 'SKIP' 'Use -Integration em Windows como administrador.'}
    }

    if ($Integration) {
        Invoke-TestCase 'Integração exige administrador' {
            Assert-QA (Test-AutoRunnerAdministrator) 'Execute como administrador.'
            'Execução elevada.'
        }
        Invoke-TestCase 'ACL real em ProgramData' {
            $aclDir=Join-Path $env:ProgramData ('SQLBackupAndFTPAuto-QA-'+[Guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $aclDir 'scripts') -Force|Out-Null
                New-Item -ItemType Directory -Path (Join-Path $aclDir 'logs') -Force|Out-Null
                Set-Content -LiteralPath (Join-Path $aclDir 'config.json') -Value '{}' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $aclDir 'scripts\Manager.ps1') -Value '# teste' -Encoding UTF8
                [void](Protect-AutoRunnerDirectory -Path $aclDir)
                $acl=Get-Acl -LiteralPath $aclDir
                $unsafe=@($acl.Access|Where-Object{$_.IdentityReference.Value -match 'Users|Usuarios|S-1-5-32-545' -and $_.AccessControlType -eq 'Allow' -and (($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -ne 0)})
                $configAcl=@((Get-Acl -LiteralPath (Join-Path $aclDir 'config.json')).Access|Where-Object{$_.IdentityReference.Value -match 'Users|Usuarios|S-1-5-32-545' -and $_.AccessControlType -eq 'Allow'})
                $configWrite=@($configAcl|Where-Object{($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -ne 0})
                $configRead=@($configAcl|Where-Object{($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Read) -ne 0 -or ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadAndExecute) -ne 0})
                Assert-QA ($unsafe.Count -eq 0) 'Users possui escrita na raiz.'
                Assert-QA ($configWrite.Count -eq 0) 'Users possui escrita no config.json.'
                Assert-QA ($configRead.Count -ge 1) 'Users não possui leitura operacional do config.json.'
                'ACL aplicada: usuários possuem leitura operacional sem permissão de escrita.'
            } finally { if(Test-Path -LiteralPath $aclDir){& (Join-Path $env:SystemRoot 'System32\icacls.exe') $aclDir '/grant:r' '*S-1-5-32-544:(OI)(CI)F'|Out-Null;Remove-Item -LiteralPath $aclDir -Recurse -Force -ErrorAction SilentlyContinue} }
        }
        Invoke-TestCase 'Caminho sob junction é recusado' {
            $real=Join-Path $env:ProgramData ('SQLBackupAndFTPAuto-QA-Real-'+[Guid]::NewGuid().ToString('N'))
            $junction=Join-Path $env:ProgramData ('SQLBackupAndFTPAuto-QA-Link-'+[Guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $real -Force|Out-Null
                New-Item -ItemType Junction -Path $junction -Target $real -Force|Out-Null
                Assert-QA (-not (Test-AutoRunnerSupportPath -Path (Join-Path $junction 'Nested'))) 'Caminho sob junction foi aceito.'
                'Reparse point ancestral identificado.'
            } finally {
                Remove-Item -LiteralPath $junction -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $real -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Invoke-TestCase 'Tarefa real registra e executa' {
            $taskName='SQLBackupAndFTP AutoRunner QA '+[Guid]::NewGuid().ToString('N');$taskPath='\SQLBackupAndFTPAuto\QA\'
            try {
                $cfg=New-SimConfig @([pscustomobject]@{Name='Sucesso Task';BackupType='Default'});$cfg.Execution.StartupDelayMinutes=0
                Write-SimConfig $cfg
                Register-AutoRunnerScheduledTask -SupportDir $sim -Config $cfg -TaskName $taskName -TaskPath $taskPath|Out-Null
                $task=Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
                $action=(@($task.Actions)|ForEach-Object{$_.Arguments}) -join ';'
                Assert-QA ($action -match [regex]::Escape($sim)) 'SupportDir ausente da ação.'
                $beforeInfo=Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
                Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
                $deadline=(Get-Date).AddMinutes(2)
                do{
                    Start-Sleep 2
                    $task=Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
                    $info=Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
                    $hasNewRun=($info.LastRunTime -gt $beforeInfo.LastRunTime)
                }while(((-not $hasNewRun) -or $task.State -eq 'Running') -and (Get-Date)-lt $deadline)
                Assert-QA $hasNewRun 'A tarefa não registrou nova execução no prazo.'
                Assert-QA ($info.LastTaskResult -eq 0) "LastTaskResult=$($info.LastTaskResult)"
                "LastTaskResult=$($info.LastTaskResult)"
            } finally { Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue }
        }
    }
    else {
        Add-Result 'ACL real em ProgramData' 'SKIP' 'Use -Integration em Windows como administrador.'
        Add-Result 'Tarefa real registra e executa' 'SKIP' 'Use -Integration em Windows como administrador.'
    }

    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Invoke-TestCase 'PSScriptAnalyzer' {
            Import-Module PSScriptAnalyzer
            $issues=@(Invoke-ScriptAnalyzer -Path $root -Recurse -Severity Error,Warning)
            Assert-QA ($issues.Count -eq 0) (($issues|Select-Object -First 50|ForEach-Object{"$($_.ScriptName):$($_.Line):$($_.RuleName):$($_.Message)"}) -join '; ')
            'Sem alertas Error/Warning.'
        }
    }
    else { Add-Result 'PSScriptAnalyzer' 'SKIP' 'Módulo não instalado; nenhuma aprovação foi inferida.' }
}
finally {
    $summary=New-Object System.Collections.Generic.List[string]
    $summary.Add('SQLBackupAndFTP AutoRunner - Relatório de QA Windows')
    $summary.Add('Data: '+(Get-Date).ToString('s'))
    $summary.Add('Versão: '+(Get-AutoRunnerVersion))
    $summary.Add('Windows: '+[Environment]::OSVersion.VersionString)
    $summary.Add('PowerShell: '+$PSVersionTable.PSVersion.ToString())
    $summary.Add('Integração solicitada: '+[bool]$Integration)
    $summary.Add('')
    foreach($result in $results){$summary.Add(('[{0}] {1} - {2}' -f $result.Status,$result.Name,$result.Detail))}
    $summary.Add('')
    foreach($status in @('PASS','FAIL','SKIP')){$summary.Add("${status}: $(@($results|Where-Object{$_.Status -eq $status}).Count)")}
    [IO.File]::WriteAllLines($reportPath,$summary,(New-Object Text.UTF8Encoding($false)))
    Write-Host "Relatório: $reportPath"
    if($sim -and (Test-Path -LiteralPath $sim)){try{& (Join-Path $env:SystemRoot 'System32\icacls.exe') $sim '/grant:r' '*S-1-5-32-544:(OI)(CI)F'|Out-Null}catch{};Remove-Item -LiteralPath $sim -Recurse -Force -ErrorAction SilentlyContinue}
    if($KeepArtifacts){Write-Host "Artefatos: $work"}else{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
}
if(@($results|Where-Object{$_.Status -eq 'FAIL'}).Count -gt 0){exit 1}else{exit 0}
