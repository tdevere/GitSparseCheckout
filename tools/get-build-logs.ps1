$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"
$buildId = 108

# Timeline (job/step status)
Write-Host "=== Build $buildId timeline ==="
$tl = Invoke-RestMethod -Uri "$base/build/builds/$buildId/timeline?api-version=7.1" -UseDefaultCredentials
$tl.records | Where-Object { $_.type -in 'Stage','Job','Phase','Task' } |
    Sort-Object order |
    Select-Object type, name, state, result, @{n='errorCount';e={$_.errorCount}} |
    Format-Table -AutoSize

# Log list
Write-Host ""
Write-Host "=== Log entries ==="
$logs = Invoke-RestMethod -Uri "$base/build/builds/$buildId/logs?api-version=7.1" -UseDefaultCredentials
$logs.value | Select-Object id, lineCount | Format-Table -AutoSize

# First non-empty log (usually contains the fatal error)
Write-Host ""
Write-Host "=== Log content (first log with errors) ==="
foreach ($log in ($logs.value | Sort-Object id)) {
    if ($log.lineCount -gt 0) {
        $lines = Invoke-RestMethod -Uri "$base/build/builds/$buildId/logs/$($log.id)?api-version=7.1" -UseDefaultCredentials
        Write-Host "--- Log $($log.id) ($($log.lineCount) lines) ---"
        $lines -split "`n" | Select-Object -First 60 | ForEach-Object { Write-Host $_ }
        break
    }
}
