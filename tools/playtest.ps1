# Automated playtest batch: runs bot-vs-bot matches across class matchups
# and collects the host's [telemetry] JSON lines into playtest_results.jsonl.
#
# Usage: powershell -File tools\playtest.ps1 [-Matches 2] [-MatchSeconds 30]

param(
    [int]$Matches = 2,
    [int]$MatchSeconds = 30,
    [string]$GodotExe = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.4.1-stable_win64_console.exe"
)

$proj = Join-Path $PSScriptRoot "..\godot"
$out = Join-Path $PSScriptRoot "..\playtest_results.jsonl"
Remove-Item $out -ErrorAction SilentlyContinue

$matchups = @(
    @("slipper", "anchor"),
    @("swapper", "slipper"),
    @("anchor", "swapper"),
    @("slipper", "slipper")
)

$port = 7860
foreach ($pair in $matchups) {
    for ($i = 0; $i -lt $Matches; $i++) {
        $port++
        Write-Host "match: $($pair[0]) vs $($pair[1]) (port $port)"
        $hostJob = Start-Job -ScriptBlock {
            param($g, $p, $port, $cls, $secs)
            & $g --headless --path $p -- --auto=host --port=$port --match-seconds=$secs --bot-style=smart --class=$cls --map=playtest_seed 2>&1
        } -ArgumentList $GodotExe, $proj, $port, $pair[0], $MatchSeconds
        Start-Sleep -Milliseconds 700
        $joinJob = Start-Job -ScriptBlock {
            param($g, $p, $port, $cls)
            & $g --headless --path $p -- --auto=join --port=$port --bot-style=smart --class=$cls 2>&1
        } -ArgumentList $GodotExe, $proj, $port, $pair[1]
        Wait-Job $hostJob, $joinJob -Timeout ($MatchSeconds + 75) | Out-Null
        # Force everything to strings: Receive-Job can yield objects that
        # break -match.
        $lines = @(Receive-Job $hostJob; Receive-Job $joinJob) | ForEach-Object { "$_" }
        Stop-Job $hostJob, $joinJob -ErrorAction SilentlyContinue
        Remove-Job $hostJob, $joinJob -Force
        Get-Process Slippington -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
        $telemetry = $lines | Where-Object { $_ -match "^\[telemetry\] " }
        foreach ($t in $telemetry) {
            $t -replace "^\[telemetry\] ", "" | Add-Content $out
        }
        if (-not $telemetry) { Write-Host "  (no telemetry captured!)" }
    }
}
Write-Host "results -> $out"
Get-Content $out | Measure-Object -Line | Select-Object -ExpandProperty Lines

