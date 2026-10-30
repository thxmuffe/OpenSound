param([string]$OtpRoot = $env:PARVI_OTP_ROOT, [switch]$Test,
      [ValidateSet('Native', 'Legacy')][string]$Transport = 'Legacy',
      [string]$NativeLibRoot = $env:PARVI_WINDOWS_NATIVE_LIB)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$work = Join-Path $repo 'builds\intermediates\Windows'
New-Item -ItemType Directory -Force $work | Out-Null
if (!$OtpRoot) { $OtpRoot = Join-Path $work 'otp' }
$OtpRoot = (Resolve-Path -LiteralPath $OtpRoot).Path
$erlc = Join-Path $OtpRoot 'bin\erlc.exe'
$erl = Join-Path $OtpRoot 'bin\erl.exe'
if (!(Test-Path -LiteralPath $erlc)) { throw 'Set PARVI_OTP_ROOT to an extracted Windows OTP 29.1.2 archive.' }
& (Join-Path $repo 'scripts\erlang-deps.ps1') -OtpRoot $OtpRoot
if ($Transport -eq 'Native') {
    if (!$NativeLibRoot) {
        throw 'Native Windows NIF packaging is not available yet: the pinned DTLS/Unifex stack requires POSIX facilities. Supply -NativeLibRoot with Windows-built transport/Elixir applications, or explicitly use -Transport Legacy for the earlier relay app. See src/Apps/Windows/README.md.'
    }
    $NativeLibRoot = (Resolve-Path -LiteralPath $NativeLibRoot).Path
    # Verify target NIFs before modifying an existing app bundle. Mac/iOS artifacts
    # cannot be reused as Windows dynamic libraries.
    $paths = @(Get-ChildItem -LiteralPath $NativeLibRoot -Directory | ForEach-Object { Join-Path $_.FullName 'ebin' })
    $check = 'case application:ensure_all_started(parvi_transport) of {ok, _} -> ok; StartError -> io:format("~p~n", [StartError]), halt(1) end, lists:foreach(fun(M) -> case code:ensure_loaded(M) of {module, M} -> ok; LoadError -> io:format("~p: ~p~n", [M, LoadError]), halt(1) end end, [''Elixir.ExDTLS.Native.Nif'', ''Elixir.ExLibSRTP.Native.Nif'', ''Elixir.ExSCTP'', crc_nif]), halt().'
    & $erl -noshell -pa @paths -eval $check
    if ($LASTEXITCODE) { throw 'Native Windows dependency loading failed. The existing bundle was not updated.' }
}
$out = Join-Path $repo 'builds\Windows\Parvi'
$ebin = Join-Path $out 'ebin'
New-Item -ItemType Directory -Force $ebin | Out-Null
if ($Transport -eq 'Native') {
    $nativeLib = Join-Path $out 'native_lib'
    New-Item -ItemType Directory -Force $nativeLib | Out-Null
    foreach ($library in Get-ChildItem -LiteralPath $NativeLibRoot -Directory) {
        $target = Join-Path $nativeLib $library.Name
        New-Item -ItemType Directory -Force $target | Out-Null
        foreach ($folder in @('ebin', 'priv')) {
            $sourceFolder = Join-Path $library.FullName $folder
            if (Test-Path -LiteralPath $sourceFolder) {
                Copy-Item -LiteralPath $sourceFolder -Destination $target -Recurse -Force
            }
        }
        Get-ChildItem -LiteralPath $library.FullName -File | Where-Object {
            $_.Name -match '^(LICENSE|COPYING|NOTICE)'
        } | Copy-Item -Destination $target -Force
    }
}
$relayLib = Join-Path $out 'relay_lib'
New-Item -ItemType Directory -Force $relayLib | Out-Null
foreach ($dep in @('gun', 'cowlib')) {
    $sourceDep = Join-Path $repo "builds\intermediates\control\default\lib\$dep"
    $targetDep = Join-Path $relayLib $dep
    New-Item -ItemType Directory -Force $targetDep | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDep 'ebin') -Destination $targetDep -Recurse -Force
    Get-ChildItem -LiteralPath $sourceDep -Filter 'LICENSE*' | Copy-Item -Destination $targetDep
}
$sources = @('src/control/src', 'src/Audio/src', 'src/Apps/Windows/src') | ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $repo $_) -Filter '*.erl' | ForEach-Object FullName
}
& $erlc -Werror +debug_info -o $ebin @sources
if ($LASTEXITCODE) { throw 'Erlang compilation failed.' }
Copy-Item -LiteralPath (Join-Path $repo 'src/control\src\parvi.app.src') -Destination (Join-Path $ebin 'parvi.app')
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $out 'LICENSE')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY.md') -Destination $out
# Keep the runtime private to the app. No machine installation or PATH changes.
$runtime = Join-Path $out 'runtime'
if (!(Test-Path -LiteralPath (Join-Path $runtime 'bin\erl.exe'))) {
    New-Item -ItemType Directory -Force $runtime | Out-Null
    Get-ChildItem -LiteralPath $OtpRoot -Directory | Where-Object {
        $_.Name -in @('bin', 'lib', 'releases') -or $_.Name -like 'erts-*'
    } | Copy-Item -Destination $runtime -Recurse
}
$source = Join-Path $PSScriptRoot 'launcher.c'
$launcher = Join-Path $out 'Parvi.exe'
if (!(Test-Path -LiteralPath $launcher) -or
    (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $launcher).LastWriteTimeUtc) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'Install the Visual Studio Desktop development with C++ workload to build Parvi.exe.' }
    $dev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    # Compile in one shell with the Visual Studio environment.
    $compile = "`"$dev`" -no_logo -arch=x64 -host_arch=x64 && cl /nologo /W4 /MT `"$source`" /Fo`"$work\launcher.obj`" /Fe`"$launcher`" /link /SUBSYSTEM:WINDOWS user32.lib bcrypt.lib"
    & $env:ComSpec /d /s /c $compile
    if ($LASTEXITCODE) { throw 'Native launcher compilation failed. Close Parvi if its launcher needs rebuilding.' }
} else {
    Write-Host 'Native launcher unchanged; compiled Erlang modules only.'
}
# The audio input is a small user-mode WASAPI helper, not an installed driver.
$audioSource = Join-Path $repo 'src/Audio/native/Windows/audio_input.cpp'
$audioHelper = Join-Path $out 'parvi_audio_input.exe'
if (!(Test-Path -LiteralPath $audioHelper) -or
    (Get-Item -LiteralPath $audioSource).LastWriteTimeUtc -gt (Get-Item -LiteralPath $audioHelper).LastWriteTimeUtc) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'Visual Studio C++ build tools are required for WASAPI input.' }
    $dev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    & $env:ComSpec /d /s /c "`"$dev`" -no_logo -arch=x64 -host_arch=x64 && cl /nologo /W4 /WX /EHsc /std:c++17 /MT `"$audioSource`" /Fo`"$work\audio_input.obj`" /Fe`"$audioHelper`" /link ole32.lib uuid.lib"
    if ($LASTEXITCODE) { throw 'Audio input build failed. Stop input before rebuilding its executable.' }
}
if ($Test) {
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src/control\test') -Filter '*.erl' | ForEach-Object FullName)
    $tests += Join-Path $PSScriptRoot 'test\parvi_windows_model_tests.erl'
    & $erlc -Werror -o $ebin @tests
    if ($LASTEXITCODE) { throw 'Test compilation failed.' }
    & $erl -noshell -pa $ebin -eval 'case eunit:test([parvi_tests, parvi_swarms_tests, parvi_relay_tests, parvi_windows_model_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
    if ($LASTEXITCODE) { throw 'Core tests failed.' }
}
$profile = if ($Transport -eq 'Native') { 'native_cluster' } else { 'legacy_apps' }
[System.IO.File]::WriteAllText((Join-Path $out 'runtime-profile'), $profile, [System.Text.Encoding]::ASCII)
Write-Host "Built $out\Parvi.exe ($profile)"
