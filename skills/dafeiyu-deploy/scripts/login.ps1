#requires -Version 5.1
[CmdletBinding()]
param(
  [ValidateSet('Status','DouyinQR','DouyinPoll','DouyinBrowser','ModelProbe','QQFinish','EnableReplies')][string]$Action='Status',
  [string]$Root=(Join-Path $env:LOCALAPPDATA 'DeepSeek Harness 2'),
  [string]$Provider='deepseek-account',
  [string]$Model='deepseek-flash',
  [string]$DouyinOwnerNick='',
  [switch]$IncludeStrangers
)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$exe=Join-Path $Root 'app\DSH2.exe'
if(!(Test-Path -LiteralPath $exe)){ $exe=Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness 2\DSH2.exe' }
$wantedHome=[IO.Path]::GetFullPath((Join-Path $Root 'harness'))
$wantedDuty=Join-Path $wantedHome 'douyin-duty'
if(!(Test-Path -LiteralPath $exe)){throw 'DSH2 executable missing.'}
$processes=@(Get-CimInstance Win32_Process -Filter "Name='DSH2.exe'" | Where-Object {$_.ExecutablePath -ieq $exe})
if(!$processes.Count){throw 'Launch the isolated DSH2 shortcut, then retry.'}
$base=$null
foreach($l in Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {$_.OwningProcess -in $processes.ProcessId -and $_.LocalAddress -eq '127.0.0.1'}){
  $u='http://127.0.0.1:'+[string]$l.LocalPort
  try{$r=Invoke-RestMethod ($u+'/api/douyin-duty/status') -TimeoutSec 3;if($r.ok -and $r.home -and [IO.Path]::GetFullPath($r.home) -ieq $wantedDuty){$base=$u;break}}catch{}
}
if(!$base){throw 'DSH2 Douyin runtime not ready or its data directory did not match.'}
function Call-Local($Path,$Method='Get',$Body='{}'){
  if($Method -eq 'Get'){Invoke-RestMethod ($base+$Path) -TimeoutSec 8}
  else{Invoke-RestMethod ($base+$Path) -Method Post -ContentType 'application/json' -Body $Body -TimeoutSec 110}
}
$p='/api/douyin-duty'
switch($Action) {
  'Status' {
    $d=Call-Local "$p/status"; $m=Call-Local "$p/dm"; $q=Call-Local '/aurabot/api/state'; $link=Call-Local "$p/aurabot-link"
    $tools=Call-Local '/aurabot/api/modules/tools?as=owner'
    [pscustomobject]@{base=$base;douyinLoggedIn=$d.loggedIn;douyinWatcher=$m.watcher.connected;replyRouting=$m.replyRouting;mediaPolicy=$m.dmMediaPolicy;followupPolicy=$m.dmFollowupPolicy;persona=$link.personaShared;seenBridge=$link.seenBridge;privateDmMemory=$link.privateDmMemoryShared;qqState=$q.onebot.state;qqBotVerified=[bool]$q.onebot.login;qqBotConfigured=[bool]$q.config.botQQ;qqOwnerConfigured=[bool]$q.config.ownerQQ;qqSetupDone=$q.config.setupDone;snowlumaInstalled=$q.snowluma.installed;snowlumaConsented=$q.snowluma.consented;qqDouyinTools=@($tools.list|Where-Object name -Match 'douyin'|ForEach-Object name)}|ConvertTo-Json -Depth 5 -Compress
  }
  'DouyinQR' {
    $d=Call-Local "$p/status"
    if($d.loggedIn -eq $true){[pscustomobject]@{state='already-logged-in';base=$base}|ConvertTo-Json -Compress;break}
    $started=[DateTime]::UtcNow
    $r=Call-Local "$p/login/qr" 'Post'
    $qr=[regex]::Match([string]$r.qr,'^data:image/png;base64,([A-Za-z0-9+/=]+)$')
    if(!$r.ok -or !$qr.Success -or [string]::IsNullOrWhiteSpace([string]$r.png)) {
      [pscustomobject]@{state='use-official-login-window';base=$base}|ConvertTo-Json -Compress;break
    }
    $png=[IO.Path]::GetFullPath([string]$r.png)
    if(!$png.StartsWith($wantedHome+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $png -PathType Leaf) -or (Get-Item -LiteralPath $png).LastWriteTimeUtc -lt $started.AddSeconds(-1)){
      [pscustomobject]@{state='no-fresh-qr';base=$base}|ConvertTo-Json -Compress;break
    }
    $bytes=[Convert]::FromBase64String($qr.Groups[1].Value)
    if($bytes.Length -lt 16 -or ([BitConverter]::ToString($bytes,0,8)) -ne '89-50-4E-47-0D-0A-1A-0A'){throw 'Invalid PNG QR.'}
    $out=Join-Path ([IO.Path]::GetTempPath()) ('dsh2-douyin-qr-'+[guid]::NewGuid().ToString('N')+'.png')
    [IO.File]::WriteAllBytes($out,$bytes)
    [pscustomobject]@{state='scan-douyin';base=$base;qrPath=$out}|ConvertTo-Json -Compress
  }
  'DouyinPoll' {
    $r=Call-Local "$p/login/poll" 'Post'
    [pscustomobject]@{loggedIn=$r.loggedIn;state=$r.state;needCaptcha=$r.needCaptcha;receiveVisible=$r.receiveVisible;hint=$r.hint}|ConvertTo-Json -Compress
  }
  'DouyinBrowser' {
    $r=Call-Local "$p/login/browser" 'Post'
    [pscustomobject]@{ok=$r.ok;hint=$r.hint}|ConvertTo-Json -Compress
  }
  'ModelProbe' {
    $r=Call-Local '/aurabot/api/model/ping' 'Post' (@{provider=$Provider;model=$Model}|ConvertTo-Json -Compress)
    [pscustomobject]@{ok=$r.ok;provider=$Provider;model=$Model;message=$r.message}|ConvertTo-Json -Compress
  }
  'QQFinish' {
    $q=Call-Local '/aurabot/api/state'
    if(!$q.config.botQQ -or !$q.config.ownerQQ -or $q.config.botQQ -eq $q.config.ownerQQ -or $q.onebot.state -ne 'connected' -or !$q.onebot.login){throw 'QQ identity or verified gateway connection still missing.'}
    $r=Call-Local '/aurabot/api/setup/done' 'Post' '{"existingConnection":true}'
    [pscustomobject]@{ok=$r.ok;setupDone=$r.config.setupDone;gateway=$r.onebot.state}|ConvertTo-Json -Compress
  }
  'EnableReplies' {
    $s=Call-Local "$p/status"
    if(!$s.loggedIn){throw 'Douyin needs a verified login first.'}
    $probe=Call-Local '/aurabot/api/model/ping' 'Post' (@{provider=$Provider;model=$Model}|ConvertTo-Json -Compress)
    if(!$probe.ok){throw 'Model probe did not succeed; leave automatic replies off.'}
    $target=$DouyinOwnerNick.Trim()
    if(!$target){$target=[string]$s.config.shareToNick}
    if(!$target -or $target -match '[,，、\r\n]'){throw 'A verified single owner Douyin nickname is required.'}
    if($Provider -ne 'deepseek-account'){
      throw 'For a third-party model, first install and verify its headless provider separately; this helper only activates the built-in account route.'
    }
    $names=@(([string]$s.config.msgAllowTo -split '[,，、\r\n]+')|ForEach-Object{$_.Trim()}|Where-Object{$_})
    $names=@(($names+@($target))|Select-Object -Unique)
    $patch=@{shareToNick=$target;msgAllowTo=($names -join ', ');dmFastProvider=$Provider;dmFastModel=$Model;headlessModel="$Provider/$Model";dmAutoReply=$true;dmReply=[bool]$IncludeStrangers}
    $r=Call-Local "$p/config" 'Post' ($patch|ConvertTo-Json -Compress)
    [pscustomobject]@{ok=$r.ok;model=$r.config.dmFastModel;allowlistReply=$r.config.dmAutoReply;strangerReply=$r.config.dmReply}|ConvertTo-Json -Compress
  }
}
