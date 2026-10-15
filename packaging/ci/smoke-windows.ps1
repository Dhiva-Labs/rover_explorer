<#
.SYNOPSIS
Starts Rover Explorer and waits for proof that its Dart code is running.

.DESCRIPTION
The native runner only shows the window once Flutter has drawn its first
frame, so a main window handle means the engine and the app's AOT snapshot ran
on this CPU. main() then starts the indexer isolate, which scans the home
folder and writes rover_index.txt into the application-support folder. HOME is
pointed at a throwaway folder holding one marker file (the app prefers HOME
over USERPROFILE), so finding the marker in that cache shows the Dart file
system code and the kernel32 FFI call ran as well.

  packaging\ci\smoke-windows.ps1 -Exe <path to rover_explorer.exe>
#>
param(
    [Parameter(Mandatory)][string]$Exe
)
$ErrorActionPreference = 'Stop'

$dataDir = Join-Path $env:APPDATA 'Dhiva Labs\Rover Explorer'
$cache = Join-Path $dataDir 'rover_index.txt'
$fixture = Join-Path ([IO.Path]::GetTempPath()) "rover-smoke-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path (Join-Path $fixture 'Documents') | Out-Null
New-Item -ItemType File -Path (Join-Path $fixture 'Documents\rover-smoke-marker.txt') | Out-Null
if (Test-Path $dataDir) { Remove-Item -Recurse -Force $dataDir }

$env:HOME = $fixture
$p = Start-Process -FilePath $Exe -PassThru
try {
    $up = $false
    for ($i = 1; $i -le 90; $i++) {
        Start-Sleep -Seconds 1
        $p.Refresh()
        if ($p.HasExited) { throw "$Exe exited early with code $($p.ExitCode)" }
        if ($p.MainWindowHandle -ne 0 -and (Test-Path $cache)) {
            $found = $false
            try { $found = Select-String -Path $cache -SimpleMatch 'rover-smoke-marker.txt' -Quiet } catch { }
            if ($found) {
                "window '$($p.MainWindowTitle)' is up and the index holds the marker after ${i}s"
                $up = $true
                break
            }
        }
    }
    if (-not $up) {
        throw "no window and index marker after 90 s (window handle $($p.MainWindowHandle), cache exists: $(Test-Path $cache))"
    }
    Start-Sleep -Seconds 5
    $p.Refresh()
    if ($p.HasExited) { throw "$Exe died after showing its window (code $($p.ExitCode))" }
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Remove-Item -Recurse -Force $fixture -ErrorAction SilentlyContinue
}
