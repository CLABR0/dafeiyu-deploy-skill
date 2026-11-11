#requires -Version 5.1
[CmdletBinding()]
param(
  [ValidateSet('Inspect','Install','Verify')][string]$Mode='Install',
  [string]$Root=(Join-Path $env:LOCALAPPDATA 'DeepSeek Harness 2'),
  [string]$AssetRoot='',
  [string]$OwnerQQ='',
  [string]$BotQQ='',
  [string]$DouyinOwnerNick=''
)
$ErrorActionPreference='Stop'
$Utf8=[Text.UTF8Encoding]::new($false)
$Asset=$null
if($Mode -ne 'Verify'){
  if([string]::IsNullOrWhiteSpace($AssetRoot)){throw 'Public source edition: provide -AssetRoot pointing to your trusted, complete local DSH2 bundle assets.'}
  $Asset=(Resolve-Path -LiteralPath $AssetRoot).Path
}
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($Root -eq [IO.Path]::GetPathRoot($Root).TrimEnd('\') -or $Root -match '["\r\n]') { throw 'Choose a dedicated DSH2 directory.' }
$App=Join-Path $Root 'app'
$HomeDir=Join-Path $Root 'harness'
$Desktop=Join-Path $HomeDir 'profiles\desktop'
$Headless=Join-Path $HomeDir 'profiles\headless'
$Marker=Join-Path $Root '.dsh2-setup.json'
$Deps=Join-Path $Root 'deps'
$Python=Join-Path $App 'resources\runtime\primary-runtime\dependencies\python\python.exe'
$Tar=(Get-Command tar.exe -ErrorAction Stop).Source
$List=@('dsh-fish-memory','dsh-feiyu-mood','dsh-aurabot-qq','dsh-speak-up','dsh-whale-widget','dsh-douyin-life','dsh-builtin-browser','dsh-douyin-creator','dsh-video-tool','dsh-douyin-publish')

function Write-Text($Path,$Text) { [IO.File]::WriteAllText($Path,[string]$Text,$Utf8) }
function Write-New($Path,$Text) { if(!(Test-Path -LiteralPath $Path)){ Write-Text $Path $Text } }
function Read-Json($Path){ Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save-State($Step) {
  $tmp=$Marker+'.tmp'
  Write-Text $tmp (([ordered]@{format=1;kind='dsh2-setup';stage=$Step;root=$Root;time=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json))
  if(Test-Path -LiteralPath $Marker){[IO.File]::Replace($tmp,$Marker,$Marker+'.previous')}else{[IO.File]::Move($tmp,$Marker)}
}
function Assert-Bundle {
  $manifest=Read-Json (Join-Path $Asset 'manifest.json')
  foreach($item in $manifest.files){
    $path=[IO.Path]::GetFullPath((Join-Path $Asset $item.path))
    if(!$path.StartsWith($Asset+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Bundle file missing: '+$item.path)}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $item.sha256){throw ('Bundle hash mismatch: '+$item.path)}
  }
}
function Expand-Bundle($File,$To,[int]$Strip=0) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  $argsList=@('-xf',$File,'-C',$To)
  if($Strip){$argsList+=@('--strip-components',$Strip)}
  & $Tar @argsList
  if($LASTEXITCODE -ne 0){throw ('Cannot extract '+(Split-Path $File -Leaf))}
}
function Test-Static {
  $files=@('app\DSH2.exe','app\resources\app.asar','deps\browser\electron.exe','deps\media\ffmpeg\ffmpeg.exe','deps\media\ffmpeg\ffprobe.exe','deps\media\whisper-base\model.bin','deps\python\mcp','Start-DSH2.cmd','harness\profiles\desktop\package.json')
  $missing=@($files|Where-Object{!(Test-Path -LiteralPath (Join-Path $Root $_))})
  $plugins=@($List|Where-Object {Test-Path -LiteralPath (Join-Path $Desktop "node_modules\$_\package.json")})
  $modules=@('feiyu-douyin-bridge','dsh-persona','browser-ops','companion-context','douyin-creator-flow'|Where-Object {Test-Path -LiteralPath (Join-Path $HomeDir "plugins-data\aurabot\modules\$_\module.json")})
  $loginActions=@('DSH account if needed','QQ bot QR via official client','Douyin QR')
  [pscustomobject]@{mode=$Mode;ready=($missing.Count -eq 0 -and $plugins.Count -eq $List.Count -and $modules.Count -eq 5);root=$Root;missing=$missing;plugins=$plugins;modules=$modules;loginActions=$loginActions}
}

if($Mode -eq 'Inspect') {
  Assert-Bundle
  [pscustomobject]@{bundleVerified=$true;root=$Root;existing=(Test-Path -LiteralPath $HomeDir);managed=(Test-Path -LiteralPath $Marker);plugins=$List}|ConvertTo-Json -Compress
  return
}
if($Mode -eq 'Verify'){ Test-Static|ConvertTo-Json -Depth 5 -Compress; return }
if($env:PROCESSOR_ARCHITECTURE -notmatch '^(AMD64|x86)$' -or (![Environment]::Is64BitOperatingSystem)){throw 'This bundle targets Windows x64.'}
if($OwnerQQ -and $OwnerQQ -notmatch '^\d{5,12}$'){throw 'Invalid owner QQ number.'}
if($BotQQ -and $BotQQ -notmatch '^\d{5,12}$'){throw 'Invalid bot QQ number.'}
if($OwnerQQ -and $OwnerQQ -eq $BotQQ){throw 'Owner and bot QQ must be different.'}
if((Test-Path -LiteralPath $Root) -and !(Test-Path -LiteralPath $Marker) -and @(Get-ChildItem -LiteralPath $Root -Force).Count){throw 'Existing unowned DSH2 directory; do not overlay it. Verify it or choose an empty installation directory.'}
if(Test-Path -LiteralPath $Marker) {
  $state=Read-Json $Marker
  if($state.kind -ne 'dsh2-setup' -or $state.root -ne $Root){throw 'Unexpected installation marker.'}
  if($state.stage -eq 'installed') { Test-Static|ConvertTo-Json -Depth 5 -Compress; return }
}
Assert-Bundle
New-Item -ItemType Directory -Force -Path $Root,$Desktop,$Headless,$Deps | Out-Null
Save-State 'extracting'
Expand-Bundle (Join-Path $Asset 'dsh2-runtime.tar.gz') $App
Expand-Bundle (Join-Path $Asset 'browser-runtime.tar.gz') (Join-Path $Deps 'browser')
Expand-Bundle (Join-Path $Asset 'media-runtime.tar.gz') (Join-Path $Deps 'media')
Expand-Bundle (Join-Path $Asset 'node-dependencies.tar.gz') (Join-Path $Desktop 'node_modules')
Save-State 'plugins'
$sources=Join-Path $HomeDir 'bundle-sources'
New-Item -ItemType Directory -Force -Path $sources|Out-Null
$packageDeps=[ordered]@{}
foreach($name in $List) {
  $archive=Join-Path $Asset "plugins\$name.tgz"
  Copy-Item -LiteralPath $archive -Destination (Join-Path $sources "$name.tgz") -Force
  $dir=Join-Path $Desktop "node_modules\$name"
  & $Python (Join-Path $PSScriptRoot 'unpack-plugin.py') $archive $dir
  if($LASTEXITCODE){throw "Cannot extract plugin: $name"}
  $pkg=Read-Json (Join-Path $dir 'package.json')
  if($pkg.name -ne $name){throw "Plugin identity mismatch: $name"}
  $packageDeps[$name]="file:../../bundle-sources/$name.tgz"
}
$manifest=[ordered]@{name='dsh-profile-desktop';private=$true;dependencies=$packageDeps;dsh=@{profile=@{bundles=@('@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app')+$List}}}
Write-New (Join-Path $Desktop 'package.json') ($manifest|ConvertTo-Json -Depth 8)
Write-New (Join-Path $Desktop 'cordis.yml') '[]'
Write-New (Join-Path $Desktop 'cordis.patch.yml') '[]'
Write-New (Join-Path $Desktop 'pnpm-workspace.yaml') "packages:`n  - .`nnodeLinker: hoisted`nautoInstallPeers: false`n"
Write-New (Join-Path $Headless 'package.json') (@{name='dsh-profile-headless';private=$true;dsh=@{profile=@{bundles=@('@deepseek-ai/dsh-base','@deepseek-ai/dsh-headless')}}}|ConvertTo-Json -Depth 7)
Write-New (Join-Path $Headless 'cordis.yml') '[]'
Write-New (Join-Path $Headless 'cordis.patch.yml') '[]'
$Aura=Join-Path $HomeDir 'plugins-data\aurabot'
$moduleDir=Join-Path $Aura 'modules'
$douyinDir=Join-Path $HomeDir 'douyin-duty'
New-Item -ItemType Directory -Force -Path $moduleDir,$douyinDir|Out-Null
foreach($module in Get-ChildItem -LiteralPath (Join-Path $Asset 'modules') -Directory) {
  $dest=Join-Path $moduleDir $module.Name
  if(!(Test-Path -LiteralPath $dest)){Copy-Item -LiteralPath $module.FullName -Destination $dest -Recurse}
}
$auraCfg=[ordered]@{setupDone=$false;snowluma=@{autoStart=$false}}
if($OwnerQQ){$auraCfg.ownerQQ=$OwnerQQ};if($BotQQ){$auraCfg.botQQ=$BotQQ}
Write-New (Join-Path $Aura 'config.json') ($auraCfg|ConvertTo-Json -Depth 5)
$dConfig=[ordered]@{pythonPath=$Python;headlessProfile='headless';headlessModel='deepseek-account/deepseek-flash';dmFastProvider='deepseek-account';dmFastModel='deepseek-flash';dmFastReply=$true;dmAutoReply=$false;dmReply=$false;dmReplyPerContact=1;dmReplyPerDay=5;replyIntervalMin=30;shareWithNote=$false;autoLike=$false;autoComment=$false;autoCommentPlain=$false;autoPublish=$false;autoReply=$false;peakValley=$false;noon=$false;night=$false;publishDraft=$true}
if($DouyinOwnerNick){$dConfig.shareToNick=$DouyinOwnerNick;$dConfig.msgAllowTo=$DouyinOwnerNick}
Write-New (Join-Path $douyinDir 'config.json') ($dConfig|ConvertTo-Json -Depth 6)
Save-State 'python'
$wheelDir=Join-Path $Asset 'wheelhouse'
$target=Join-Path $Deps 'python'
$oldPip=$env:PIP_CONFIG_FILE
try {
  $env:PIP_CONFIG_FILE='NUL'
  & $Python -m pip install --disable-pip-version-check --no-index --no-warn-script-location --find-links $wheelDir --target $target --requirement (Join-Path $Asset 'defaults\python-requirements.txt') | Out-Host
  if($LASTEXITCODE){throw 'Offline Python dependency installation failed'}
} finally { $env:PIP_CONFIG_FILE=$oldPip }
$launcher=@'
@echo off
setlocal
set "DSH_HOME=%~dp0harness"
set "DSH_DOUYIN_HOME=%~dp0harness\douyin-duty"
set "ELECTRON_RUN_AS_NODE="
set "ELECTRON_PATH=%~dp0deps\browser\electron.exe"
set "PYTHONPATH=%~dp0deps\python;%~dp0deps\python\win32;%~dp0deps\python\win32\lib;%~dp0deps\python\pythonwin"
set "DOUYIN_WHISPER_MODEL=%~dp0deps\media\whisper-base"
set "DOUYIN_WHISPER_OFFLINE=1"
set "PATH=%~dp0deps\media\ffmpeg;%PATH%"
start "" "%~dp0app\DSH2.exe" "--user-data-dir=%~dp0electron"
endlocal
'@
Write-New (Join-Path $Root 'Start-DSH2.cmd') $launcher
Save-State 'installed'
$verified=Test-Static
$verified|ConvertTo-Json -Depth 5 -Compress
if(!$verified.ready){throw 'Installation file verification failed'}
