$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"
$buildId = 109

# ── Timeline ─────────────────────────────────────────────────────────────────
Write-Host "=== Timeline ==="
$tl = Invoke-RestMethod -Uri "$base/build/builds/$buildId/timeline?api-version=7.1" -UseDefaultCredentials
$tl.records | Where-Object { $_.type -in 'Job', 'Phase', 'Task' } |
    Sort-Object order |
    Select-Object type, name, state, result |
    Format-Table -AutoSize

# ── Log list ─────────────────────────────────────────────────────────────────
Write-Host "=== Log list ==="
$logs = Invoke-RestMethod -Uri "$base/build/builds/$buildId/logs?api-version=7.1" -UseDefaultCredentials
$logs.value | Select-Object id, lineCount | Format-Table -AutoSize

# ── Dump all logs ─────────────────────────────────────────────────────────────
foreach ($log in ($logs.value | Sort-Object id)) {
    if ($log.lineCount -gt 0) {
        Write-Host "==============================="
        Write-Host "=== Log $($log.id) ($($log.lineCount) lines) ==="
        Write-Host "==============================="
        $content = Invoke-RestMethod -Uri "$base/build/builds/$buildId/logs/$($log.id)?api-version=7.1" -UseDefaultCredentials
        $content -split "`n" | ForEach-Object { Write-Host $_ }
    }
}
