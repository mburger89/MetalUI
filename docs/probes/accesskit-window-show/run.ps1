# Builds probe.c with the Swift toolchain's clang and runs every arm, one
# process each (a panic aborts). ASCII only (PowerShell 5.1). Paths are the
# UTM VM's (CLAUDE.md "Windows locally"); override with -Sdl / -AccessKit.
# Plain SSH is enough: the probe creates windows but no GPU swapchain.
param(
    [string]$Sdl = "C:\src\SDL3-3.4.16",
    [string]$AccessKit = "C:\src\accesskit",
    [string]$Arch = "arm64"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $env:TEMP "accesskit-window-show"
New-Item -ItemType Directory -Force $out | Out-Null
$libs = "bcrypt","ntdll","propsys","runtimeobject","uiautomationcore","userenv","ws2_32","ole32","oleaut32","user32","advapi32" | ForEach-Object { "-l$_" }
& clang (Join-Path $here "probe.c") -o (Join-Path $out "probe.exe") `
    "-I$Sdl\include" "-I$AccessKit\accesskit-c-0.23.0\include" `
    "-L$Sdl\lib\$Arch" "-L$AccessKit\lib" -lSDL3 -laccesskit @libs
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Copy-Item "$Sdl\lib\$Arch\SDL3.dll" $out -Force
foreach ($arm in "V","H","S","N") {
    $p = Start-Process -FilePath (Join-Path $out "probe.exe") -ArgumentList $arm -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $out "$arm.out") -RedirectStandardError (Join-Path $out "$arm.err")
    $line = (Get-Content (Join-Path $out "$arm.out") -Raw)
    $err = (Get-Content (Join-Path $out "$arm.err") -Raw)
    Write-Output ("arm {0}: exit {1} (0x{1:X8})" -f $arm, $p.ExitCode)
    Write-Output ("  stdout: " + $line)
    if ($err) { Write-Output ("  stderr: " + ($err -split "`n" | Select-Object -First 3) -join " | ") }
}
