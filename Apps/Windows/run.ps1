$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$app = Join-Path $repo 'builds\Windows\Parvi'
if (!(Test-Path -LiteralPath (Join-Path $app 'ebin\parvi_windows.beam'))) { & "$PSScriptRoot\build.ps1" }
$cookie = [Guid]::NewGuid().ToString('N')
$env:ERL_LIBS = Join-Path $app 'native_lib'
$profile = Get-Content -Raw -LiteralPath (Join-Path $app 'runtime-profile')
$options = switch ($profile) {
    'native_cluster' { @('-start_epmd', 'false', '-proto_dist', 'parvi_webrtc', '-kernel', 'connect_all', 'false', 'dist_auto_connect', 'never', '-parvi', 'runtime_profile', 'native_cluster', 'native_desk', 'true') }
    'legacy_apps' { $env:ERL_EPMD_ADDRESS = '127.0.0.1'; @('-kernel', 'inet_dist_use_interface', '{127,0,0,1}') }
    default { throw 'Unknown runtime profile. Rebuild the Windows app.' }
}
& "$app\runtime\bin\erl.exe" -noshell -noinput -name "parvi_windows_$PID@127.0.0.1" -setcookie $cookie @options -pa "$app\ebin" -s parvi_windows main
if ($LASTEXITCODE) { throw "Parvi exited with code $LASTEXITCODE" }
