[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-cargo.ps1'
foreach ($task in @('Check', 'Test', 'Format', 'Clippy', 'Build')) {
  Write-Output "Slice 1 Cargo task: $task"
  & $runner -Task $task
  if ($LASTEXITCODE -ne 0) {
    throw "Slice 1 Cargo task $task failed with exit code $LASTEXITCODE."
  }
}

Write-Output 'SLICE 1 PARTIAL VALIDATION PASSED'
Write-Output 'Completed: T1.1, T1.2, T1.3, T1.4'
Write-Output 'Pending acceptance: T1.5 capability fingerprint, T1.6 startup recovery'
