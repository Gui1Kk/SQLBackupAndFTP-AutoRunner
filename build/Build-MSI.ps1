#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RootDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dist'),
    [switch]$RunQA
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$wix=Get-Command wix.exe -ErrorAction SilentlyContinue
if(-not $wix){throw 'WiX Toolset v4 não encontrado. Instale o WiX em Windows e execute novamente.'}
$python=Get-Command python.exe -ErrorAction SilentlyContinue
if(-not $python){$python=Get-Command python -ErrorAction SilentlyContinue}
if(-not $python){throw 'Python 3 não encontrado para montar o payload de produção.'}
$module=Join-Path $RootDirectory 'modules\AutoRunner.Core.psm1'
Import-Module $module -Force -DisableNameChecking
if($RunQA){
    & (Get-AutoRunnerWindowsPowerShellPath) -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RootDirectory 'scripts\Invoke-QA.ps1') -Integration
    if($LASTEXITCODE -ne 0){throw 'QA nativo falhou; MSI não será gerado.'}
}
$version=Get-AutoRunnerVersion
function New-VersionGuid([string]$Value){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$bytes=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('Alpha Software|SQLBackupAndFTP AutoRunner|'+$Value))[0..15]}
    finally{$sha.Dispose()}
    $bytes[6]=($bytes[6] -band 0x0F) -bor 0x50
    $bytes[8]=($bytes[8] -band 0x3F) -bor 0x80
    return '{'+([Guid]::new([byte[]]$bytes)).ToString().ToUpperInvariant()+'}'
}
function Escape-Xml([string]$Value){return [Security.SecurityElement]::Escape($Value)}
$productCode=New-VersionGuid -Value $version
$upgradeCode='{2F689305-39C8-4D21-9AA0-E0BE43D3FA4B}'
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$stage=Join-Path $env:TEMP ('SQLBackupAndFTPAuto-MSI-'+[Guid]::NewGuid().ToString('N'))
$release=Join-Path $stage 'Release'
$sourceRoot=Join-Path $stage 'Source'
$wxs=Join-Path $stage 'SQLBackupAndFTPAuto.wxs'
try{
    New-Item -ItemType Directory -Path $release,$sourceRoot -Force|Out-Null
    & $python.Source (Join-Path $RootDirectory 'build\Build-Native.py') --root $RootDirectory | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Falha ao compilar os executáveis nativos.'}
    & $python.Source (Join-Path $RootDirectory 'build\Build-Release.py') --root $RootDirectory --output $release | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Falha ao montar o payload de produção.'}
    $portable=Join-Path $release ("SQLBackupAndFTP-AutoRunner-v$version-Portable.zip")
    if(-not(Test-Path -LiteralPath $portable)){throw "ZIP portátil ausente: $portable"}
    Expand-Archive -LiteralPath $portable -DestinationPath $stage -Force
    $expanded=Join-Path $stage ("SQLBackupAndFTP-AutoRunner-v$version")
    Copy-AutoRunnerTreeSafe -Source $expanded -Destination $sourceRoot
    Copy-Item -LiteralPath (Join-Path $RootDirectory 'scripts\Msi-Cleanup.ps1') -Destination (Join-Path $sourceRoot 'scripts\Msi-Cleanup.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $RootDirectory 'native\SQLBackupAndFTP-AutoRunner-MsiBridge.exe') -Destination (Join-Path $sourceRoot 'SQLBackupAndFTP-AutoRunner-MsiBridge.exe') -Force
    $checksumPath=Join-Path $sourceRoot 'SHA256SUMS.txt'
    $checksumLines=New-Object System.Collections.Generic.List[string]
    foreach($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force|Where-Object{$_.FullName -ine $checksumPath}|Sort-Object FullName)){
        $relative=$file.FullName.Substring($sourceRoot.Length).TrimStart('\').Replace('\','/')
        $checksumLines.Add("$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) *$relative")
    }
    [IO.File]::WriteAllText($checksumPath,(($checksumLines -join "`r`n")+"`r`n"),(New-Object Text.UTF8Encoding($false)))
    $checksumValidation=Test-AutoRunnerPackageChecksums -RootPath $sourceRoot
    if(-not $checksumValidation.IsValid){throw ('Payload MSI inválido após regenerar checksums: '+($checksumValidation.Issues -join '; '))}

    $source=Escape-Xml $sourceRoot
    $launcher=Escape-Xml (Join-Path $sourceRoot 'SQLBackupAndFTP-AutoRunner.exe')
    $bridge=Escape-Xml (Join-Path $sourceRoot 'SQLBackupAndFTP-AutoRunner-MsiBridge.exe')
    $icon=Escape-Xml (Join-Path $sourceRoot 'assets\AutoRunner.ico')
    $xml=@"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="SQLBackupAndFTP AutoRunner" Manufacturer="Alpha Software" Version="$version" ProductCode="$productCode" UpgradeCode="$upgradeCode" Scope="perMachine" InstallerVersion="500" Compressed="yes">
    <SummaryInformation Description="Instala o SQLBackupAndFTP AutoRunner $version." />
    <MajorUpgrade DowngradeErrorMessage="Já existe uma versão mais recente instalada." />
    <MediaTemplate EmbedCab="yes" />
    <Property Id="ARPPRODUCTICON" Value="AutoRunnerIcon" />
    <Property Id="CREATEDESKTOPSHORTCUT" Value="0" Secure="yes" />
    <Property Id="LAUNCHAFTERINSTALL" Value="0" Secure="yes" />
    <Property Id="PRESERVEDATA" Value="0" Secure="yes" />
    <Icon Id="AutoRunnerIcon" SourceFile="$icon" />

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="AlphaSoftwareFolder" Name="Alpha Software">
        <Directory Id="INSTALLFOLDER" Name="SQLBackupAndFTP AutoRunner" />
      </Directory>
    </StandardDirectory>
    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="AlphaProgramsFolder" Name="Alpha Software" />
    </StandardDirectory>
    <StandardDirectory Id="DesktopFolder" />

    <Feature Id="MainFeature" Title="SQLBackupAndFTP AutoRunner" Level="1">
      <Files Include="$source\**" Directory="INSTALLFOLDER">
        <Exclude Files="$launcher" />
        <Exclude Files="$bridge" />
      </Files>
      <ComponentRef Id="ApplicationIntegration" />
      <ComponentRef Id="MsiBridgeComponent" />
      <ComponentRef Id="DesktopIntegration" />
    </Feature>

    <Fragment>
      <DirectoryRef Id="INSTALLFOLDER">
        <Component Id="ApplicationIntegration" Guid="{69E6C7DB-EE84-43EE-8A6D-84A953E9D804}">
          <File Id="LauncherFile" Source="$launcher" KeyPath="yes" />
          <Shortcut Id="StartMenuShortcut" Directory="AlphaProgramsFolder" Name="SQLBackupAndFTP AutoRunner" Description="Gerenciar SQLBackupAndFTP AutoRunner" Target="[#LauncherFile]" WorkingDirectory="INSTALLFOLDER" Icon="AutoRunnerIcon" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="ApplicationInstallDir" Value="[INSTALLFOLDER]" Type="string" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="ApplicationVersion" Value="$version" Type="string" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="InstallTechnology" Value="MSI" Type="string" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="MsiProductCode" Value="[ProductCode]" Type="string" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="SetupPath" Value="" Type="string" />
          <RemoveFolder Id="RemoveAlphaProgramsFolder" Directory="AlphaProgramsFolder" On="uninstall" />
        </Component>
        <Component Id="MsiBridgeComponent" Guid="{B7CB9948-E778-4F21-965D-1858209B389C}">
          <File Id="MsiBridgeFile" Source="$bridge" KeyPath="yes" />
        </Component>
        <Component Id="DesktopIntegration" Guid="{47722068-E7D3-4376-A517-7DFA54E81580}">
          <Condition>CREATEDESKTOPSHORTCUT = 1</Condition>
          <Shortcut Id="DesktopShortcut" Directory="DesktopFolder" Name="SQLBackupAndFTP AutoRunner" Description="Gerenciar SQLBackupAndFTP AutoRunner" Target="[#LauncherFile]" WorkingDirectory="INSTALLFOLDER" Icon="AutoRunnerIcon" />
          <RegistryValue Root="HKLM" Key="Software\Alpha Software\SQLBackupAndFTP AutoRunner" Name="DesktopShortcut" Value="1" Type="integer" KeyPath="yes" />
        </Component>
      </DirectoryRef>
    </Fragment>

    <CustomAction Id="CleanupAutomation" FileRef="MsiBridgeFile" ExeCommand="PRESERVEDATA=[PRESERVEDATA]" Execute="deferred" Impersonate="no" Return="check" />
    <CustomAction Id="LaunchApplication" FileRef="LauncherFile" ExeCommand="" Execute="immediate" Impersonate="yes" Return="asyncNoWait" />
    <InstallExecuteSequence>
      <Custom Action="CleanupAutomation" Before="RemoveFiles" Condition="REMOVE~=&quot;ALL&quot; AND NOT UPGRADINGPRODUCTCODE" />
      <Custom Action="LaunchApplication" After="InstallFinalize" Condition="LAUNCHAFTERINSTALL=1 AND NOT Installed AND UILevel &gt;= 4" />
    </InstallExecuteSequence>
  </Package>
</Wix>
"@
    [IO.File]::WriteAllText($wxs,$xml,(New-Object Text.UTF8Encoding($false)))
    $msi=Join-Path $OutputDirectory ("SQLBackupAndFTP-AutoRunner-v$version-x64.msi")
    & $wix.Source build $wxs -o $msi
    if($LASTEXITCODE -ne 0){throw "WiX retornou código $LASTEXITCODE"}
    if(-not(Test-Path -LiteralPath $msi -PathType Leaf)){throw 'WiX não produziu o MSI esperado.'}
    $hash=(Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    [IO.File]::WriteAllText(($msi+'.sha256.txt'),("$hash *$([IO.Path]::GetFileName($msi))`r`n"),(New-Object Text.UTF8Encoding($false)))
    return $msi
}
finally{Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
