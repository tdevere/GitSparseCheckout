$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"
$buildId = 108

foreach ($logId in 2,3,4,5) {
    Write-Host "==============================="
    Write-Host "=== Log $logId ==="
    Write-Host "==============================="
    $lines = Invoke-RestMethod -Uri "$base/build/builds/$buildId/logs/$logId`?api-version=7.1" -UseDefaultCredentials
    $lines -split "`n" | ForEach-Object { Write-Host $_ }
    Write-Host ""
}
