param([string]$OtpRoot = $env:PARVI_OTP_ROOT)
$ErrorActionPreference = 'Stop'
if (!$OtpRoot) { $OtpRoot = Join-Path $PSScriptRoot '..\windows\_build\otp' }
$OtpRoot = (Resolve-Path -LiteralPath $OtpRoot).Path
$out = Join-Path $PSScriptRoot '_build\windows\lib\parvi_broker'
$ebin = Join-Path $out 'ebin'
New-Item -ItemType Directory -Force $ebin | Out-Null
$sources = Get-ChildItem -LiteralPath "$PSScriptRoot\src" -Filter '*.erl' | ForEach-Object FullName
& "$OtpRoot\bin\erlc.exe" -Werror -o $ebin @sources
if ($LASTEXITCODE) { throw 'Reception desk compilation failed.' }
Copy-Item -LiteralPath "$PSScriptRoot\src\parvi_broker.app.src" -Destination "$ebin\parvi_broker.app"
Copy-Item -LiteralPath "$PSScriptRoot\priv" -Destination $out -Recurse -Force
& "$OtpRoot\bin\erl.exe" -noshell -pa $ebin -eval '
  application:load(parvi_broker),
  case os:getenv("PARVI_BROKER_BIND") of
    false -> ok;
    Address -> {ok, IP} = inet:parse_address(Address),
               application:set_env(parvi_broker, bind_address, IP)
  end,
  case os:getenv("PARVI_BROKER_PORT") of
    false -> ok;
    Port -> application:set_env(parvi_broker, port, list_to_integer(Port))
  end,
  {ok, _} = application:ensure_all_started(parvi_broker),
  receive stop -> ok end.'
if ($LASTEXITCODE) { throw 'Reception desk stopped unexpectedly.' }
