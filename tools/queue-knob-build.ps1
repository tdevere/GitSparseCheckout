$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"

# ── Queue pipeline 16 via the build/builds endpoint ──────────────────────────
Write-Host "=== Queueing build for pipeline 16 ==="
$queueBody = @{
    definition = @{ id = 16 }
    queue      = @{ id = 1 }   # Default pool queue ID = 1
} | ConvertTo-Json -Depth 3

$buildResp = Invoke-RestMethod -Uri "$base/build/builds?api-version=7.1" `
    -Method Post -UseDefaultCredentials -ContentType "application/json" -Body $queueBody
Write-Host "BUILD_ID         : $($buildResp.id)"
Write-Host "BUILD_NUMBER     : $($buildResp.buildNumber)"
Write-Host "BUILD_STATUS     : $($buildResp.status)"
Write-Host "BUILD_URL        : https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_build/results?buildId=$($buildResp.id)"
$buildId = $buildResp.id

if (-not $buildId) {
    Write-Host "ERROR: Queue failed — no build ID returned."
    exit 0
}

# ── Poll until completed ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Polling (15-second intervals) ==="
$maxWait = 60
$i = 0
do {
    Start-Sleep -Seconds 15
    $status = Invoke-RestMethod -Uri "$base/build/builds/$buildId`?api-version=7.1" -UseDefaultCredentials
    $i++
    Write-Host "POLL_$($i.ToString('00'))           : status=$($status.status)  result=$($status.result)"
} until ($status.status -eq "completed" -or $i -ge $maxWait)

Write-Host ""
Write-Host "=== Final result ==="
Write-Host "FINAL_STATUS     : $($status.status)"
Write-Host "FINAL_RESULT     : $($status.result)"
Write-Host "BUILD_URL        : https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_build/results?buildId=$buildId"
