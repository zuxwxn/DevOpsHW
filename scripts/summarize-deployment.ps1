param(
    [Parameter(Mandatory = $true)][string]$MonitorLogPath,
    [Parameter(Mandatory = $true)][string]$MetadataPath,
    [Parameter(Mandatory = $true)][string]$FunctionalResultPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [Parameter(Mandatory = $true)][string]$ServiceUrl,
    [Parameter(Mandatory = $true)][string]$DeployVersion
)

$ErrorActionPreference = 'Stop'

function Format-Record {
    param($Record)
    if (-not $Record) { return '관측 없음' }
    $version = if ($Record.version) { $Record.version } else { 'unavailable' }
    return "seq=$($Record.sequence), $($Record.start_utc) → $($Record.end_utc), $($Record.duration_ms)ms, HTTP=$($Record.http_status), version=$version"
}

$records = @()
if (Test-Path -LiteralPath $MonitorLogPath) {
    $records = @(Import-Csv -LiteralPath $MonitorLogPath)
}

$metadata = $null
if (Test-Path -LiteralPath $MetadataPath) {
    $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
}

$functional = $null
if (Test-Path -LiteralPath $FunctionalResultPath) {
    $functional = Get-Content -LiteralPath $FunctionalResultPath -Raw | ConvertFrom-Json
}

$successes = @($records | Where-Object { $_.http_status -eq '200' }).Count
$failures = $records.Count - $successes
$durations = @($records | ForEach-Object { [double]$_.duration_ms })
$maxDuration = if ($durations.Count) { [math]::Round(($durations | Measure-Object -Maximum).Maximum, 2) } else { 0 }
$averageDuration = if ($durations.Count) { [math]::Round(($durations | Measure-Object -Average).Average, 2) } else { 0 }

$intervals = @()
$gaps = @()
for ($index = 1; $index -lt $records.Count; $index++) {
    $previousStart = [DateTimeOffset]::Parse($records[$index - 1].start_utc)
    $previousEnd = [DateTimeOffset]::Parse($records[$index - 1].end_utc)
    $currentStart = [DateTimeOffset]::Parse($records[$index].start_utc)
    $intervals += ($currentStart - $previousStart).TotalSeconds
    $gaps += ($currentStart - $previousEnd).TotalSeconds
}
$averageInterval = if ($intervals.Count) { [math]::Round(($intervals | Measure-Object -Average).Average, 3) } else { 0 }
$maxGap = if ($gaps.Count) { [math]::Round(($gaps | Measure-Object -Maximum).Maximum, 3) } else { 0 }

$before = $records | Where-Object { $_.phase -eq 'before' } | Select-Object -Last 1
$during = $records | Where-Object { $_.phase -eq 'deploying' } | Select-Object -First 1
$after = $records | Where-Object { $_.phase -eq 'after' } | Select-Object -Last 1
$versions = @($records | Where-Object { $_.version -and $_.version -ne 'unavailable' } | Select-Object -ExpandProperty version -Unique)
$versionTransition = if ($versions.Count) { $versions -join ' → ' } else { '응답에서 버전 확인 불가' }

$deploymentResult = if ($metadata) { $metadata.result } else { 'not-recorded' }
$previousImage = if ($metadata -and $metadata.previous_image_id) { $metadata.previous_image_id } else { '없음/확인 불가' }
$newImage = if ($metadata -and $metadata.new_image_id) { $metadata.new_image_id } else { '확인 불가' }
$repoDigest = if ($metadata -and $metadata.repo_digest) { $metadata.repo_digest } else { '확인 불가' }
$colorResult = if ($functional) { "$($functional.extracted_hex) (expected $($functional.expected_hex), pass=$($functional.color_test_passed))" } else { '검증 미실행' }
$copyResult = if ($functional) { "pass=$($functional.copy_message_asset_passed), expected='$($functional.expected_copy_message)'" } else { '검증 미실행' }
$healthResult = if ($functional) { "HTTP=$($functional.health_http_status), version=$($functional.health_version), pass=$($functional.health_test_passed)" } else { '검증 미실행' }
$continuity = if ($records.Count -eq 0) {
    '관측 기록이 없어 판단할 수 없음'
} elseif ($failures -eq 0) {
    "관측한 $($records.Count)건에서는 HTTP 실패가 없었습니다. 최대 관측 공백 ${maxGap}s 바깥은 관측하지 못한 구간입니다."
} else {
    "관측한 $($records.Count)건 중 실패 $failures건이 있었습니다. 최대 관측 공백 ${maxGap}s 바깥은 관측하지 못한 구간입니다."
}

$summary = @"
# 로컬 자동 재배포 검증

| 항목 | 결과 |
|---|---|
| 서비스 주소 | [$ServiceUrl]($ServiceUrl) |
| 배포 대상 커밋 | $DeployVersion |
| 배포 결과 | **$deploymentResult** |
| 버전 전환 | $versionTransition |
| 이전 이미지 ID | $previousImage |
| 새 이미지 ID | $newImage |
| Docker Hub digest | $repoDigest |
| 요청 결과 | 총 $($records.Count) / 성공 $successes / 실패 $failures |
| 응답 시간 | 평균 ${averageDuration}ms / 최대 ${maxDuration}ms |
| 실제 요청 시작 간격 | 평균 ${averageInterval}s (각 응답 종료 후 1초 대기 정책) |
| 최대 관측 공백 | ${maxGap}s |
| 색상 추출 | $colorResult |
| 복사 완료 문구 자산 | $copyResult |
| 헬스/버전 API | $healthResult |

## 대표 응답

| 구간 | 관측값 |
|---|---|
| 배포 전 | $(Format-Record $before) |
| 배포 중 | $(Format-Record $during) |
| 배포 후 | $(Format-Record $after) |

## 무중단 관측 결론

$continuity

> 모니터는 각 요청이 끝난 뒤 1초 후 다음 요청을 시작합니다. 요청 사이의 시간과 모니터 시작 전·종료 후는 관측하지 못한 구간입니다.
"@

$summary | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) {
    $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Append
}

Write-Host $summary
