$ErrorActionPreference = 'Continue'
$base = "https://adoserver/DefaultCollection/ADO_TEAM_PROJECT/_apis"

# ── Inspect pipeline 15 (known-good) via build definitions API ───────────────
Write-Host "=== Pipeline 15 build definition details ==="
$def15 = Invoke-RestMethod -Uri "$base/build/definitions/15?api-version=7.1" -UseDefaultCredentials
Write-Host "Name             : $($def15.name)"
Write-Host "Queue type       : $($def15.queue.pool.name)"
Write-Host "Pool ID          : $($def15.queue.id)"
Write-Host "Pool name        : $($def15.queue.name)"
Write-Host "Process type     : $($def15.process.type)"
Write-Host ""

Write-Host "=== Pipeline 16 build definition details ==="
$def16 = Invoke-RestMethod -Uri "$base/build/definitions/16?api-version=7.1" -UseDefaultCredentials
Write-Host "Name             : $($def16.name)"
Write-Host "Queue type       : $($def16.queue.pool.name)"
Write-Host "Pool ID          : $($def16.queue.id)"
Write-Host "Pool name        : $($def16.queue.name)"
Write-Host ""

# ── Get available agent queues ────────────────────────────────────────────────
Write-Host "=== Agent queues ==="
$queues = Invoke-RestMethod -Uri "$base/distributedtask/queues?api-version=7.1" -UseDefaultCredentials
$queues.value | Select-Object id, name | Format-Table -AutoSize
