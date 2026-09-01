[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolLockPath = Join-Path $PSScriptRoot 'tools.lock.json'
$toolLock = Get-Content -Raw -Encoding UTF8 -LiteralPath $toolLockPath | ConvertFrom-Json
$bootstrapOutput = & (Join-Path $PSScriptRoot 'bootstrap-tools.ps1')
$sqlitePath = @($bootstrapOutput)[-1]
$nodePath = Join-Path $repoRoot '.tools\node-24.20.0\node-v24.20.0-win-x64\node.exe'
$jsonSchemaValidatorPath = Join-Path $PSScriptRoot 'validate-json-schema.cjs'
$gate0ValidatorPath = Join-Path $PSScriptRoot 'validate-gate0-evidence.cjs'
$schemaPath = Join-Path $repoRoot 'spec\project-brain\v1\schema.sql'
$seedPath = Join-Path $repoRoot 'spec\project-brain\v1\seed.sql'
$messageSchemaPath = Join-Path $repoRoot 'spec\apf-cp\v1\message.schema.json'
$providerResultSchemaPath = Join-Path $repoRoot 'spec\apf-cp\v1\provider-result.schema.json'
$validationRoot = Join-Path $repoRoot '.tmp\foundation-validation'
$databasePath = Join-Path $validationRoot 'brain.db'
$backupPath = Join-Path $validationRoot 'brain-backup.db'
$databaseWorkOrderPath = Join-Path $validationRoot 'work-order-from-brain.json'
$databaseResultPath = Join-Path $validationRoot 'result-from-brain.json'

function Open-VerifiedToolHandle {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $stream = [System.IO.File]::Open(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::Read
  )
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $actual = ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-').ToLowerInvariant()
    } finally {
      $sha.Dispose()
    }
    if ($actual -ne $ExpectedSha256) {
      throw "$Label digest mismatch. Expected $ExpectedSha256, got $actual."
    }
    return $stream
  } catch {
    $stream.Dispose()
    throw
  }
}

function Get-TreeSha256 {
  param([Parameter(Mandatory = $true)][string]$Root)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  $files = [System.IO.Directory]::GetFiles($rootFull, '*', [System.IO.SearchOption]::AllDirectories)
  [Array]::Sort($files, [System.StringComparer]::Ordinal)
  $builder = New-Object System.Text.StringBuilder
  foreach ($file in $files) {
    $info = New-Object System.IO.FileInfo($file)
    if ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw "Tool tree contains a reparse point: $file"
    }
    $relative = $file.Substring($rootFull.Length).TrimStart('\').Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$builder.Append($relative).Append([char]0).Append($hash).Append("`n")
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

New-Item -ItemType Directory -Force -Path $validationRoot | Out-Null
foreach ($path in @(
  $databasePath,
  "$databasePath-shm",
  "$databasePath-wal",
  $backupPath,
  $databaseWorkOrderPath,
  $databaseResultPath
)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

function Invoke-SqliteScript {
  param(
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$Script
  )

  $handle = Open-VerifiedToolHandle -Path $sqlitePath -ExpectedSha256 $toolLock.sqlite.executable_sha256 -Label 'SQLite executable'
  try {
    $scriptText = "PRAGMA foreign_keys=ON;`nPRAGMA recursive_triggers=ON;`n" +
      (Get-Content -Raw -Encoding UTF8 -LiteralPath $Script)
    $scriptOutput = $scriptText | & $sqlitePath -batch -bail $Database
    $scriptExitCode = $LASTEXITCODE
    if ($scriptExitCode -ne 0) {
      throw "SQLite failed while applying $Script`: $($scriptOutput -join ' ')"
    }
  } finally {
    $handle.Dispose()
  }
}

function Invoke-SqliteScalar {
  param([Parameter(Mandatory = $true)][string]$Database, [Parameter(Mandatory = $true)][string]$Sql)
  $handle = Open-VerifiedToolHandle -Path $sqlitePath -ExpectedSha256 $toolLock.sqlite.executable_sha256 -Label 'SQLite executable'
  try {
    $queryText = "PRAGMA foreign_keys=ON; PRAGMA recursive_triggers=ON; $Sql"
    $value = & $sqlitePath -batch -noheader $Database $queryText
    $queryExitCode = $LASTEXITCODE
    if ($queryExitCode -ne 0) {
      throw "SQLite query failed: $Sql"
    }
    return ($value -join "`n").Trim()
  } finally {
    $handle.Dispose()
  }
}

function Assert-SqliteRejected {
  param(
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$Sql,
    [Parameter(Mandatory = $true)][string]$ExpectedPattern,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $handle = Open-VerifiedToolHandle -Path $sqlitePath -ExpectedSha256 $toolLock.sqlite.executable_sha256 -Label 'SQLite executable'
  $queryText = "PRAGMA foreign_keys=ON; PRAGMA recursive_triggers=ON; $Sql"
  $rejectionOutput = & $sqlitePath -batch $Database $queryText 2>&1
  $rejectionExitCode = $LASTEXITCODE
  $handle.Dispose()
  $ErrorActionPreference = $previousPreference
  if ($rejectionExitCode -eq 0 -or (($rejectionOutput -join "`n") -notmatch $ExpectedPattern)) {
    throw "$Label was not rejected as expected."
  }
}

Invoke-SqliteScript -Database $databasePath -Script $schemaPath

$schemaChecksum = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
$migrationSql = "INSERT INTO schema_migrations(version,name,checksum_sha256,applied_at) VALUES(2,'foundation_v2','$schemaChecksum','2026-08-28T00:00:00Z');"
Invoke-SqliteScalar -Database $databasePath -Sql $migrationSql | Out-Null

Invoke-SqliteScript -Database $databasePath -Script $seedPath

$sqliteVersion = Invoke-SqliteScalar -Database $databasePath -Sql 'select sqlite_version();'
if ($sqliteVersion -ne '3.53.4') { throw "Expected SQLite 3.53.4, got $sqliteVersion" }

$userVersion = Invoke-SqliteScalar -Database $databasePath -Sql 'PRAGMA user_version;'
if ($userVersion -ne '2') { throw "Expected Project Brain user_version 2, got $userVersion" }

$journalMode = Invoke-SqliteScalar -Database $databasePath -Sql 'PRAGMA journal_mode;'
if ($journalMode -ne 'wal') { throw "Expected WAL journal mode, got $journalMode" }

$ftsEnabled = Invoke-SqliteScalar -Database $databasePath -Sql "select sqlite_compileoption_used('ENABLE_FTS5');"
if ($ftsEnabled -ne '1') { throw 'SQLite FTS5 is not enabled.' }

$integrity = Invoke-SqliteScalar -Database $databasePath -Sql 'PRAGMA integrity_check;'
if ($integrity -ne 'ok') { throw "Integrity check failed: $integrity" }

$foreignKeyViolations = Invoke-SqliteScalar -Database $databasePath -Sql 'PRAGMA foreign_key_check;'
if ($foreignKeyViolations) { throw "Foreign key violations: $foreignKeyViolations" }

$ftsResult = Invoke-SqliteScalar -Database $databasePath -Sql "select group_concat(entity_ref, ',') from brain_fts where brain_fts match 'deterministic';"
if ($ftsResult -ne 'DEC-0001') { throw "Unexpected FTS result: $ftsResult" }

$taskCount = Invoke-SqliteScalar -Database $databasePath -Sql 'select count(*) from tasks;'
$runCount = Invoke-SqliteScalar -Database $databasePath -Sql 'select count(*) from runs;'
$eventCount = Invoke-SqliteScalar -Database $databasePath -Sql 'select count(*) from audit_events;'
$policyCount = Invoke-SqliteScalar -Database $databasePath -Sql 'select count(*) from policy_snapshots;'
if ($taskCount -ne '1' -or $runCount -ne '1' -or $eventCount -ne '3' -or $policyCount -ne '1') {
  throw "Unexpected seed counts: tasks=$taskCount runs=$runCount events=$eventCount policies=$policyCount"
}

Assert-SqliteRejected -Database $databasePath `
  -Sql "update audit_events set event_type='tampered' where event_id='EVT-0001';" `
  -ExpectedPattern 'append-only' -Label 'Audit UPDATE'
Assert-SqliteRejected -Database $databasePath `
  -Sql "delete from audit_events where event_id='EVT-0001';" `
  -ExpectedPattern 'append-only' -Label 'Audit DELETE'
Assert-SqliteRejected -Database $databasePath `
  -Sql "insert or replace into audit_events(sequence,project_id,event_id,occurred_at,actor_ref,event_type,data_json) values(1,1,'EVT-0001','2026-08-28T21:09:00Z','ACT-CORE-0001','replaced','{}');" `
  -ExpectedPattern 'append-only' -Label 'Audit INSERT OR REPLACE'
Assert-SqliteRejected -Database $databasePath `
  -Sql "insert into audit_events(project_id,event_id,occurred_at,actor_ref,event_type,data_json) values(1,'EVT-BACKDATED','2026-08-28T20:00:00Z','ACT-CORE-0001','late','{}');" `
  -ExpectedPattern 'backdated' -Label 'Backdated audit INSERT'
Assert-SqliteRejected -Database $databasePath `
  -Sql "update tasks set lease_owner_actor_id=1, lease_expires_at='2026-08-28T22:00:00Z' where ref='TASK-0001';" `
  -ExpectedPattern 'CHECK constraint failed' -Label 'Lease on a non-leased task'
Assert-SqliteRejected -Database $databasePath `
  -Sql "update runs set status='RUNNING' where ref='RUN-0001';" `
  -ExpectedPattern 'CHECK constraint failed' -Label 'Running process without process identity'
Assert-SqliteRejected -Database $databasePath `
  -Sql "update runs set enforcement_json=json_object('filesystem','SANDBOXED') where ref='RUN-0001';" `
  -ExpectedPattern 'invalid observed enforcement' -Label 'Unknown enforcement vocabulary'
Assert-SqliteRejected -Database $databasePath `
  -Sql "update policy_snapshots set autonomy='SHARED' where ref='POL-0001';" `
  -ExpectedPattern 'immutable' -Label 'Policy snapshot UPDATE'
Assert-SqliteRejected -Database $databasePath `
  -Sql "update cost_entries set cost_basis='LIST' where ref='COST-0001';" `
  -ExpectedPattern 'CHECK constraint failed' -Label 'Actual list-basis cost'
Assert-SqliteRejected -Database $databasePath `
  -Sql "insert into projects(id,ref,name,slug,root_path,intent_revision,intent_sha256,purpose_primary,mode,autonomy,created_at,updated_at) select 2,'PRJ-SECOND','Second','second',root_path,intent_revision,intent_sha256,purpose_primary,mode,autonomy,created_at,updated_at from projects where id=1;" `
  -ExpectedPattern 'CHECK constraint failed' -Label 'Second project in one Brain'

$escapedBackupPath = $backupPath.Replace("'", "''").Replace('\', '/')
Invoke-SqliteScalar -Database $databasePath -Sql "VACUUM INTO '$escapedBackupPath';" | Out-Null
if (-not (Test-Path -LiteralPath $backupPath)) { throw 'SQLite backup was not created.' }

$backupIntegrity = Invoke-SqliteScalar -Database $backupPath -Sql 'PRAGMA integrity_check;'
$backupDecision = Invoke-SqliteScalar -Database $backupPath -Sql "select title from knowledge_items where ref='DEC-0001';"
if ($backupIntegrity -ne 'ok' -or $backupDecision -ne 'Deterministic control plane') {
  throw 'Backup restore validation failed.'
}

$jsonFiles = @($messageSchemaPath, $providerResultSchemaPath) + @(
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'spec\apf-cp\v1\examples') -Filter '*.json' -File |
    Select-Object -ExpandProperty FullName
) + @(
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'evidence\gate0') -Filter '*.json' -File |
    Select-Object -ExpandProperty FullName
)
foreach ($jsonFile in $jsonFiles) {
  Get-Content -Raw -Encoding UTF8 -LiteralPath $jsonFile | ConvertFrom-Json | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$databaseWorkOrder = Invoke-SqliteScalar -Database $databasePath -Sql "select message_json from work_orders where ref='WO-0001';"
$databaseResult = Invoke-SqliteScalar -Database $databasePath -Sql "select result_message_json from runs where ref='RUN-0001';"
[System.IO.File]::WriteAllText($databaseWorkOrderPath, $databaseWorkOrder, $utf8NoBom)
[System.IO.File]::WriteAllText($databaseResultPath, $databaseResult, $utf8NoBom)

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$nodeHandle = Open-VerifiedToolHandle -Path $nodePath -ExpectedSha256 $toolLock.node.executable_sha256 -Label 'Node.js executable'
$jsonSchemaOutput = & $nodePath $jsonSchemaValidatorPath $databaseWorkOrderPath $databaseResultPath 2>&1
$jsonSchemaExitCode = $LASTEXITCODE
$nodeHandle.Dispose()
$ErrorActionPreference = $previousErrorActionPreference
if ($jsonSchemaExitCode -ne 0) {
  throw "APF-CP JSON Schema validation failed: $($jsonSchemaOutput -join ' ')"
}
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$nodeHandle = Open-VerifiedToolHandle -Path $nodePath -ExpectedSha256 $toolLock.node.executable_sha256 -Label 'Node.js executable'
$gate0SchemaOutput = & $nodePath $gate0ValidatorPath 2>&1
$gate0SchemaExitCode = $LASTEXITCODE
$nodeHandle.Dispose()
$ErrorActionPreference = $previousErrorActionPreference
if ($gate0SchemaExitCode -ne 0) {
  throw "Gate 0 JSON Schema validation failed: $($gate0SchemaOutput -join ' ')"
}
$validatorTree = Get-TreeSha256 -Root (Join-Path $repoRoot '.tools\schema-validator')
if ($validatorTree -ne $toolLock.schema_validator.tree_sha256) {
  throw 'The JSON Schema validator tree changed during validation.'
}

$projectPath = Join-Path $repoRoot 'PROJECT.md'
$projectYamlPath = Join-Path $repoRoot '.apf\project.yaml'
$projectHash = (Get-FileHash -LiteralPath $projectPath -Algorithm SHA256).Hash.ToLowerInvariant()
$yamlText = Get-Content -Raw -Encoding UTF8 -LiteralPath $projectYamlPath
if ($yamlText -notmatch [regex]::Escape("source_sha256: $projectHash")) {
  throw 'PROJECT.md differs from the hash recorded in .apf/project.yaml.'
}
$brainIntentHash = Invoke-SqliteScalar -Database $databasePath -Sql "select intent_sha256 from projects where ref='PRJ-APF-0001';"
if ($brainIntentHash -ne $projectHash) {
  throw 'The Project Brain seed intent hash differs from PROJECT.md.'
}

$markdownFiles = @(
  (Join-Path $repoRoot 'README.md'),
  (Join-Path $repoRoot 'PROJECT.md'),
  (Join-Path $repoRoot 'AGENTS.md')
) + @(
  Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -Recurse -Filter '*.md' -File |
    Select-Object -ExpandProperty FullName
)

$brokenLinks = @()
$linkPattern = [regex]'\[[^\]]+\]\(([^)]+)\)'
foreach ($markdownFile in $markdownFiles) {
  $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $markdownFile
  foreach ($match in $linkPattern.Matches($content)) {
    $target = $match.Groups[1].Value.Trim('<', '>')
    if ($target -match '^(https?://|mailto:|#)') { continue }
    $targetPath = ($target -split '#')[0]
    if (-not $targetPath) { continue }
    $resolved = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $markdownFile) $targetPath))
    if (-not (Test-Path -LiteralPath $resolved)) {
      $brokenLinks += "$markdownFile -> $target"
    }
  }
}
if ($brokenLinks.Count -gt 0) {
  throw "Broken local Markdown links:`n$($brokenLinks -join "`n")"
}

Write-Output 'FOUNDATION VALIDATION PASSED'
Write-Output "SQLite: $sqliteVersion, WAL, FTS5, Brain user_version=$userVersion"
Write-Output "Seed: tasks=$taskCount runs=$runCount events=$eventCount policies=$policyCount"
Write-Output 'Brain invariants: 10 negative mutations rejected'
Write-Output 'Backup: integrity and canonical decision restored'
Write-Output "APF-CP JSON Schema: $($jsonSchemaOutput -join ' ')"
Write-Output "Gate 0 JSON Schema: $($gate0SchemaOutput -join ' ')"
Write-Output "PROJECT.md semantic-source hash: $projectHash"
Write-Output "Local Markdown links: $($markdownFiles.Count) files checked"
