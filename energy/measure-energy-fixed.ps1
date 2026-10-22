# Battery energy experiment for Ubuntu WSL2 (Windows PowerShell 5.1 compatible)
# Run while unplugged. Records whole-laptop battery drain, NOT direct per-process energy.
$ErrorActionPreference = 'Stop'
$folder = Join-Path $HOME 'Desktop\energy-results-v2'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$iterations = 18000  # Same workload for O0 and O3; about 4.5 min vs 1.5 min
$intervalMs = 2000
$results = New-Object 'System.Collections.Generic.List[object]'

function Battery-Reading([double]$seconds) {
    $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
    if ($null -eq $b) { throw 'BatteryStatus is unavailable' }
    [pscustomobject]@{
        Timestamp      = (Get-Date).ToString('o')
        Seconds        = [math]::Round($seconds, 3)
        Capacity_mWh   = [double]$b.RemainingCapacity
        Discharge_mW   = [double]$b.DischargeRate
        Discharging    = [bool]$b.Discharging
        PowerOnline    = [bool]$b.PowerOnline
    }
}

function Run-Test([string]$name, [int]$idleSeconds = 0, [string]$binary = '') {
    Write-Host "`nStarting $name..." -ForegroundColor Cyan
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $samples.Add((Battery-Reading $sw.Elapsed.TotalSeconds))
    if (-not $samples[0].Discharging -or $samples[0].PowerOnline) {
        throw 'Laptop must be unplugged and discharging. No test started.'
    }
    if ($samples[0].Capacity_mWh -lt 6000) {
        throw 'Battery energy is low; charge before running long tests.'
    }

    $p = $null
    $exitCode = 0
    $outText = ''
    $errText = ''
    try {
        if ($binary -ne '') {
            $start = New-Object System.Diagnostics.ProcessStartInfo
            $start.FileName = 'wsl.exe'
            $start.Arguments = "-d Ubuntu -- /home/simunwy/performance-lab/$binary $iterations"
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $start
            if (-not $p.Start()) { throw "Failed to start WSL for $name" }
        }

        while ($true) {
            if ($null -ne $p) {
                $done = $p.WaitForExit($intervalMs)
            } else {
                Start-Sleep -Milliseconds $intervalMs
                $done = $sw.Elapsed.TotalSeconds -ge $idleSeconds
            }
            $samples.Add((Battery-Reading $sw.Elapsed.TotalSeconds))
            if ($done) { break }
        }

        if ($null -ne $p) {
            $p.WaitForExit()
            $exitCode = $p.ExitCode
            $outText = $p.StandardOutput.ReadToEnd()
            $errText = $p.StandardError.ReadToEnd()
            [System.IO.File]::WriteAllText((Join-Path $folder "$name-output.txt"), $outText)
            [System.IO.File]::WriteAllText((Join-Path $folder "$name-error.txt"), $errText)
        }
    } finally {
        $sw.Stop()
        if ($null -ne $p) { $p.Dispose() }
    }

    $csv = Join-Path $folder "$name.csv"
    $samples | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $first = $samples[0]
    $last = $samples[$samples.Count - 1]
    $duration = $sw.Elapsed.TotalSeconds
    $energy = ($first.Capacity_mWh - $last.Capacity_mWh) * 3.6
    $uniqueCapacity = @($samples | Select-Object -ExpandProperty Capacity_mWh -Unique).Count
    $validBattery = @($samples | Where-Object { -not $_.Discharging -or $_.PowerOnline }).Count -eq 0
    $quality = if (-not $validBattery) {'POWER_CHANGED'} elseif ($energy -le 0 -or $uniqueCapacity -lt 3) {'LOW_RESOLUTION'} else {'CHECK_CSV'}

    $record = [pscustomobject]@{
        Test = $name
        Iterations = if ($binary -ne '') {$iterations} else {0}
        Seconds = [math]::Round($duration, 3)
        Start_mWh = $first.Capacity_mWh
        End_mWh = $last.Capacity_mWh
        Delta_J = [math]::Round($energy, 3)
        Average_W = [math]::Round(($energy / $duration), 3)
        UniqueCapacityValues = $uniqueCapacity
        ExitCode = $exitCode
        Quality = $quality
    }
    $results.Add($record)
    $record | Format-List | Out-Host
    if ($binary -ne '') { Write-Host "Program output: $outText" }
    if ($exitCode -ne 0) { throw "$name failed with exit code $exitCode. See $name-error.txt" }
    if (-not $validBattery) { throw 'Power source changed during a test. Repeat it.' }
}

try {
    Run-Test -name 'idle' -idleSeconds 120
    Start-Sleep -Seconds 10
    Run-Test -name 'O0' -binary 'program_O0'
    Start-Sleep -Seconds 10
    Run-Test -name 'O3' -binary 'program_O3'
} finally {
    $results | Export-Csv -Path (Join-Path $folder 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "`nSaved to $folder" -ForegroundColor Green
}
