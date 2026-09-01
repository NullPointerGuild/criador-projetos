[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gateRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\gate0')).TrimEnd('\')
$runId = 'PATH-' + [Guid]::NewGuid().ToString('N')
$runRoot = [System.IO.Path]::GetFullPath((Join-Path $gateRoot $runId))
if (-not $runRoot.StartsWith($gateRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Resolved Gate 0 path-probe root escaped the intended directory.'
}
$workspace = Join-Path $runRoot 'workspace'
$outside = Join-Path $runRoot 'outside'
New-Item -ItemType Directory -Force -Path $workspace, $outside | Out-Null
Add-Type -Path (Join-Path $PSScriptRoot 'JobObject.cs')

$results = @()

$outsideSentinel = Join-Path $outside 'sentinel.txt'
$hardlinkPath = Join-Path $workspace 'hardlink.txt'
[System.IO.File]::WriteAllText($outsideSentinel, 'before', (New-Object System.Text.UTF8Encoding($false)))
New-Item -ItemType HardLink -Path $hardlinkPath -Target $outsideSentinel | Out-Null
$outsideIdentity = [Apf.Gate0.FileIdentity]::Inspect($outsideSentinel)
$hardlinkIdentity = [Apf.Gate0.FileIdentity]::Inspect($hardlinkPath)
[System.IO.File]::WriteAllText($hardlinkPath, 'mutated-through-hardlink', (New-Object System.Text.UTF8Encoding($false)))
$hardlinkDetected = $outsideIdentity.VolumeSerialNumber -eq $hardlinkIdentity.VolumeSerialNumber -and
  $outsideIdentity.FileId -eq $hardlinkIdentity.FileId -and $hardlinkIdentity.LinkCount -ge 2 -and
  (Get-Content -LiteralPath $outsideSentinel -Raw -Encoding UTF8) -eq 'mutated-through-hardlink'
$results += [pscustomobject]@{
  probe_id = 'T0.6.HARDLINK_ESCAPE'
  outcome = if ($hardlinkDetected) { 'DETECTED' } else { 'UNDETECTED' }
  prevention = 'ADVISORY'
  detection = if ($hardlinkDetected) { 'APF_VERIFIED' } else { 'UNKNOWN' }
  link_count = $hardlinkIdentity.LinkCount
  same_file_identity = $outsideIdentity.FileId -eq $hardlinkIdentity.FileId
}

$junctionPath = Join-Path $workspace 'junction'
New-Item -ItemType Junction -Path $junctionPath -Target $outside | Out-Null
$junctionIdentity = [Apf.Gate0.FileIdentity]::Inspect($junctionPath)
$junctionWrite = Join-Path $junctionPath 'junction-write.txt'
[System.IO.File]::WriteAllText($junctionWrite, 'junction-escape', (New-Object System.Text.UTF8Encoding($false)))
$junctionDetected = $junctionIdentity.IsReparsePoint -and
  $junctionIdentity.FinalPath.StartsWith('\\?\' + $outside, [System.StringComparison]::OrdinalIgnoreCase) -and
  (Test-Path -LiteralPath (Join-Path $outside 'junction-write.txt'))
$results += [pscustomobject]@{
  probe_id = 'T0.6.JUNCTION_ESCAPE'
  outcome = if ($junctionDetected) { 'DETECTED' } else { 'UNDETECTED' }
  prevention = 'ADVISORY'
  detection = if ($junctionDetected) { 'APF_VERIFIED' } else { 'UNKNOWN' }
  reparse_point = $junctionIdentity.IsReparsePoint
  final_path = $junctionIdentity.FinalPath
}

$toctouPath = Join-Path $workspace 'toctou-slot'
$retiredPath = Join-Path $workspace 'toctou-retired'
New-Item -ItemType Directory -Path $toctouPath | Out-Null
$toctouBefore = [Apf.Gate0.FileIdentity]::Inspect($toctouPath)
Rename-Item -LiteralPath $toctouPath -NewName (Split-Path -Leaf $retiredPath)
New-Item -ItemType Junction -Path $toctouPath -Target $outside | Out-Null
$toctouAfter = [Apf.Gate0.FileIdentity]::Inspect($toctouPath)
$toctouEscapedFile = Join-Path $toctouPath 'toctou-write.txt'
[System.IO.File]::WriteAllText($toctouEscapedFile, 'validate-then-swap-escape', (New-Object System.Text.UTF8Encoding($false)))
$toctouDetected = -not $toctouBefore.IsReparsePoint -and
  $toctouBefore.FinalPath.StartsWith('\\?\' + $workspace, [System.StringComparison]::OrdinalIgnoreCase) -and
  $toctouAfter.IsReparsePoint -and
  $toctouAfter.FinalPath.StartsWith('\\?\' + $outside, [System.StringComparison]::OrdinalIgnoreCase) -and
  (Test-Path -LiteralPath (Join-Path $outside 'toctou-write.txt'))
$results += [pscustomobject]@{
  probe_id = 'T0.6.TOCTOU_VALIDATE_THEN_OPEN'
  outcome = if ($toctouDetected) { 'DETECTED' } else { 'UNDETECTED' }
  prevention = 'ADVISORY'
  detection = if ($toctouDetected) { 'APF_VERIFIED' } else { 'UNKNOWN' }
  initially_reparse_point = $toctouBefore.IsReparsePoint
  after_swap_reparse_point = $toctouAfter.IsReparsePoint
  after_swap_final_path = $toctouAfter.FinalPath
}

$symlinkPath = Join-Path $workspace 'symlink'
try {
  New-Item -ItemType SymbolicLink -Path $symlinkPath -Target $outside -ErrorAction Stop | Out-Null
  $symlinkIdentity = [Apf.Gate0.FileIdentity]::Inspect($symlinkPath)
  $symlinkDetected = $symlinkIdentity.IsReparsePoint
  $results += [pscustomobject]@{
    probe_id = 'T0.6.SYMLINK_ESCAPE'
    outcome = if ($symlinkDetected) { 'DETECTED' } else { 'UNDETECTED' }
    prevention = 'ADVISORY'
    detection = if ($symlinkDetected) { 'APF_VERIFIED' } else { 'UNKNOWN' }
    reparse_point = $symlinkIdentity.IsReparsePoint
    final_path = $symlinkIdentity.FinalPath
  }
} catch {
  $results += [pscustomobject]@{
    probe_id = 'T0.6.SYMLINK_ESCAPE'
    outcome = 'SKIPPED'
    prevention = 'UNKNOWN'
    detection = 'UNKNOWN'
    reason = $_.Exception.Message
  }
}

$failed = @($results | Where-Object { $_.outcome -eq 'UNDETECTED' })
$unknown = @($results | Where-Object { $_.outcome -eq 'SKIPPED' })
$evidence = [ordered]@{
  schema_version = 1
  run_id = $runId
  checked_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  platform = 'windows-x64'
  layer = 'A_SYNTHETIC_PATHS'
  result = if ($failed.Count -gt 0) { 'LAYER_A_FAIL' } elseif ($unknown.Count -gt 0) { 'LAYER_A_PASS_WITH_UNKNOWN' } else { 'LAYER_A_PASS' }
  limitations = @(
    'Detection was measured on synthetic files only.',
    'Hardlink and reparse detection do not prevent a write.',
    'The measured validate-then-open TOCTOU attack escaped; handle-relative writes or OS containment are still required for prevention.',
    'Provider-native filesystem tools remain untested by this path harness.',
    'Prefix comparison alone is not accepted as a control.'
  )
  probes = $results
}
$evidencePath = Join-Path $runRoot 'evidence.json'
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
$hash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "GATE 0 PATH LAYER A: $($evidence.result)"
Write-Output "Evidence: $evidencePath"
Write-Output "Evidence SHA-256: $hash"
if ($failed.Count -gt 0) { exit 1 }
