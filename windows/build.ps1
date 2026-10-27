param([string]$OtpRoot = $env:PARVI_OTP_ROOT, [switch]$Test)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$OtpRoot) { $OtpRoot = Join-Path $PSScriptRoot '_build\otp' }
$OtpRoot = (Resolve-Path -LiteralPath $OtpRoot).Path
$erlc = Join-Path $OtpRoot 'bin\erlc.exe'
$erl = Join-Path $OtpRoot 'bin\erl.exe'
if (!(Test-Path -LiteralPath $erlc)) { throw 'Set PARVI_OTP_ROOT to an extracted Windows OTP 29.1.2 archive.' }
$out = Join-Path $PSScriptRoot '_build\Parvi'
$ebin = Join-Path $out 'ebin'
New-Item -ItemType Directory -Force $ebin | Out-Null
$sources = @('control\src', 'windows\src') | ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $repo $_) -Filter '*.erl' | ForEach-Object FullName
}
& $erlc -Werror +debug_info -o $ebin @sources
if ($LASTEXITCODE) { throw 'Erlang compilation failed.' }
Copy-Item -LiteralPath (Join-Path $repo 'control\src\parvi.app.src') -Destination (Join-Path $ebin 'parvi.app')
# Keep the runtime private to the app. No machine installation or PATH changes.
$runtime = Join-Path $out 'runtime'
if (!(Test-Path -LiteralPath (Join-Path $runtime 'bin\erl.exe'))) {
    New-Item -ItemType Directory -Force $runtime | Out-Null
    Get-ChildItem -LiteralPath $OtpRoot -Directory | Where-Object {
        $_.Name -in @('bin', 'lib', 'releases') -or $_.Name -like 'erts-*'
    } | Copy-Item -Destination $runtime -Recurse
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Install the Visual Studio Desktop development with C++ workload to build Parvi.exe.' }
$dev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$source = Join-Path $PSScriptRoot 'launcher.c'
# Compiler environment and compilation run in the same shell; no filesystem mutation through cmd.
$compile = "`"$dev`" -no_logo -arch=x64 -host_arch=x64 && cl /nologo /W4 /MT `"$source`" /Fo`"$out\launcher.obj`" /Fe`"$out\Parvi.exe`" /link /SUBSYSTEM:WINDOWS user32.lib bcrypt.lib"
& $env:ComSpec /d /s /c $compile
if ($LASTEXITCODE) { throw 'Native launcher compilation failed.' }
if ($Test) {
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $repo 'control\test') -Filter '*.erl' | ForEach-Object FullName)
    & $erlc -Werror -o $ebin @tests
    if ($LASTEXITCODE) { throw 'Test compilation failed.' }
    & $erl -noshell -pa $ebin -eval 'case eunit:test(parvi_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
    if ($LASTEXITCODE) { throw 'Core tests failed.' }
}
Write-Host "Built $out\Parvi.exe"
