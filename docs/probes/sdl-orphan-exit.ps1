# Probe WG-2 (item WG, rulings WG-B, WG-I): an orphaned MetalUISDLTests helper exits on Windows.
# STATUS: UNRUN. Written 2026-10-26 without a Windows machine (the UTM VM timed out); the Windows half of
# SDLTestProcessGuard was never compiled or run locally either (WG-I). Record the first run's output here.
# Windows twin of sdl-orphan-exit.sh. Run from the repository root after `swift build --build-tests` in
# Backends/SDL (PowerShell 5.1; ASCII only), in the console session if the tests need a window:
#   powershell -File docs\probes\sdl-orphan-exit.ps1
# Starts `swift test --skip-build --filter theProbeHoldBlocksTheHelper` with METALUI_TL_HOLD=1 (TL7 blocks the
# helper 120 s), finds the helper child of the runner, force-stops the runner (not the helper) and asserts the
# helper is gone within 3 s (the watcher's WaitForSingleObject on the runner handle signals, exit 70).
# Prints "ok orphan exited after <n> s", "FAIL helper <pid> survived 3 s" or "inconclusive: ...".
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location (Join-Path $root 'Backends\SDL')
$flags = @(python scripts\fetch-accesskit.py --print-flags)
$env:METALUI_TL_HOLD = '1'
$env:METALUI_REQUIRE_GPU = '1'
$runner = Start-Process -FilePath swift -ArgumentList (@('test','--skip-build','--no-parallel','--filter','theProbeHoldBlocksTheHelper') + $flags) -PassThru -WindowStyle Hidden
function Find-Helper($parentId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$parentId" |
        Where-Object { $_.Name -like 'swiftpm-testing-helper*' } | Select-Object -Last 1
}
$helper = $null
for ($i = 0; $i -lt 300 -and -not $helper; $i++) {
    $helper = Find-Helper $runner.Id
    if (-not $helper) { Start-Sleep -Milliseconds 100 }
}
if (-not $helper) { Write-Output 'inconclusive: no helper found'; exit 3 }
Start-Sleep -Seconds 2
# swift test starts a helper per phase (listing, then the run): take the one alive now.
$helper = Find-Helper $runner.Id
if (-not $helper) { Write-Output 'inconclusive: no helper alive after 2 s'; exit 3 }
$helperId = $helper.ProcessId
Stop-Process -Id $runner.Id -Force
$sw = [Diagnostics.Stopwatch]::StartNew()
while (Get-Process -Id $helperId -ErrorAction SilentlyContinue) {
    if ($sw.Elapsed.TotalSeconds -ge 3) {
        Write-Output "FAIL helper $helperId survived 3 s"
        Stop-Process -Id $helperId -Force
        exit 1
    }
    Start-Sleep -Milliseconds 50
}
Write-Output ("ok orphan exited after {0:N0} s" -f $sw.Elapsed.TotalSeconds)
