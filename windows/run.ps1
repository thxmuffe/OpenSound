$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '_build\Parvi'
if (!(Test-Path -LiteralPath (Join-Path $app 'ebin\parvi_windows.beam'))) { & "$PSScriptRoot\build.ps1" }
$cookie = [Guid]::NewGuid().ToString('N')
$env:ERL_EPMD_ADDRESS = '127.0.0.1'
& "$app\runtime\bin\erl.exe" -noshell -noinput -name "parvi_windows_$PID@127.0.0.1" -setcookie $cookie -kernel inet_dist_use_interface '{127,0,0,1}' -pa "$app\ebin" -s parvi_windows main
if ($LASTEXITCODE) { throw "Parvi exited with code $LASTEXITCODE" }
