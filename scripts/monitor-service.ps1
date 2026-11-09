param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $true)][string]$PhasePath,
    [Parameter(Mandatory = $true)][string]$StopPath,
    [double]$RequestIntervalSeconds = 1
)

$ErrorActionPreference = 'Stop'
$logDirectory = Split-Path -Parent $LogPath
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

'"sequence","phase","start_utc","end_utc","duration_ms","http_status","version","error"' |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

$sequence = 0
while (-not (Test-Path -LiteralPath $StopPath)) {
    $sequence++
    $phase = 'unknown'
    if (Test-Path -LiteralPath $PhasePath) {
        $phase = (Get-Content -LiteralPath $PhasePath -Raw).Trim()
    }

    $started = [DateTimeOffset]::UtcNow
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $status = ''
    $version = 'unavailable'
    $errorMessage = ''

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
        $status = [string][int]$response.StatusCode
        if ($response.Headers['X-App-Version']) {
            $version = [string]$response.Headers['X-App-Version']
        }
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [string][int]$_.Exception.Response.StatusCode
        } else {
            $status = 'connection-error'
        }
        $errorMessage = ($_.Exception.Message -replace '[\r\n]+', ' ').Trim()
    } finally {
        $timer.Stop()
    }

    $ended = [DateTimeOffset]::UtcNow
    $record = [pscustomobject][ordered]@{
        sequence = $sequence
        phase = $phase
        start_utc = $started.ToString('o')
        end_utc = $ended.ToString('o')
        duration_ms = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
        http_status = $status
        version = $version
        error = $errorMessage
    }
    $csvLine = $record | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1
    Add-Content -LiteralPath $LogPath -Value $csvLine -Encoding UTF8

    Start-Sleep -Milliseconds ([int]($RequestIntervalSeconds * 1000))
}
