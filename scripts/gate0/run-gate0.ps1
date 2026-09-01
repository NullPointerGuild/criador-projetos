[CmdletBinding()]
param(
  [ValidateRange(1, 20)][int]$Trials = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bootstrapOutput = & (Join-Path $repoRoot 'scripts\bootstrap-tools.ps1')
$nodePath = Join-Path $repoRoot '.tools\node-24.20.0\node-v24.20.0-win-x64\node.exe'
$fixturePath = Join-Path $PSScriptRoot 'hostile-fixture.mjs'
$jobSourcePath = Join-Path $PSScriptRoot 'JobObject.cs'
$gateRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\gate0')).TrimEnd('\')
$runId = 'GATE0-' + [Guid]::NewGuid().ToString('N')
$runRoot = [System.IO.Path]::GetFullPath((Join-Path $gateRoot $runId))
if (-not $runRoot.StartsWith($gateRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Resolved Gate 0 scratch path escaped the intended root.'
}
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

Add-Type -Path $jobSourcePath

function Quote-FixedArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value.Contains('"')) { throw 'Gate 0 fixture arguments may not contain a quote.' }
  return '"' + $Value.TrimEnd('\').Replace('\', '\') + '"'
}

function New-ScrubbedEnvironment {
  param([Parameter(Mandatory = $true)][string]$Scratch)
  $environment = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($name in @('SystemRoot', 'windir', 'SystemDrive', 'ComSpec', 'PATHEXT', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($value) { $environment[$name] = $value }
  }
  $environment['PATH'] = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot
  foreach ($name in @('TEMP', 'TMP', 'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA')) {
    $directory = Join-Path $Scratch $name.ToLowerInvariant()
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $environment[$name] = $directory
  }
  return $environment
}

function New-FixtureArguments {
  param([string]$Attack, [string]$Scratch, [string]$Ledger, [int]$Depth = 3)
  return @(
    (Quote-FixedArgument $fixturePath),
    'launcher',
    $Attack,
    (Quote-FixedArgument $Scratch),
    (Quote-FixedArgument $Ledger),
    [string]$Depth
  ) -join ' '
}

function Get-SurvivingFixtureProcesses {
  param([Parameter(Mandatory = $true)][string]$Ledger)
  if (-not (Test-Path -LiteralPath $Ledger)) { return @() }
  $survivors = @()
  foreach ($line in Get-Content -LiteralPath $Ledger -Encoding UTF8) {
    if (-not $line) { continue }
    $entry = $line | ConvertFrom-Json
    $process = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
    if ($process) {
      $startedMs = [DateTimeOffset]$process.StartTime.ToUniversalTime()
      if ($startedMs.ToUnixTimeMilliseconds() -le ([long]$entry.observed_at_ms + 2000)) {
        $survivors += [pscustomobject]@{ pid = $entry.pid; kind = $entry.kind }
      }
    }
  }
  return @($survivors)
}

function ConvertTo-SafeTerminalText {
  param([AllowEmptyString()][string]$Text)
  $safe = [regex]::Replace($Text, "`e\][^`a]*(?:`a|`e\\)", '')
  $safe = [regex]::Replace($safe, "`e\[[0-?]*[ -/]*[@-~]", '')
  $safe = [regex]::Replace($safe, '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '')
  $safe = [regex]::Replace($safe, '[\u202a-\u202e\u2066-\u2069]', '')
  return $safe
}

$canaryNames = @(
  'APF_CANARY_TOKEN', 'GITHUB_TOKEN', 'OPENAI_API_KEY', 'ANTHROPIC_API_KEY',
  'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AZURE_CLIENT_SECRET',
  'GOOGLE_APPLICATION_CREDENTIALS', 'NPM_TOKEN', 'GIT_ASKPASS', 'SSH_AUTH_SOCK'
)
$savedEnvironment = @{}
foreach ($name in $canaryNames) {
  $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
  [Environment]::SetEnvironmentVariable($name, "APF-SYNTHETIC-$name", 'Process')
}

$probeResults = @()
try {
  for ($trial = 1; $trial -le $Trials; $trial++) {
    $trialRoot = Join-Path $runRoot "tree-$trial"
    New-Item -ItemType Directory -Force -Path $trialRoot | Out-Null
    $ledger = Join-Path $trialRoot 'processes.jsonl'
    $mode = if ($trial % 2 -eq 0) { 'close' } else { 'terminate' }
    $run = [Apf.Gate0.Broker]::Run(
      $nodePath,
      (New-FixtureArguments -Attack 'tree' -Scratch $trialRoot -Ledger $ledger -Depth 3),
      $trialRoot,
      (New-ScrubbedEnvironment $trialRoot),
      16384,
      16384,
      750,
      $mode,
      16
    )
    Start-Sleep -Milliseconds 250
    $survivors = @(Get-SurvivingFixtureProcesses -Ledger $ledger)
    $probeResults += [pscustomobject]@{
      probe_id = 'T0.4.PROCESS_TREE'
      trial = $trial
      outcome = if ($survivors.Count -eq 0) { 'PASSED' } else { 'FAILED' }
      observed_enforcement = if ($survivors.Count -eq 0) { 'OS_ENFORCED' } else { 'UNKNOWN' }
      termination_mode = $mode
      survivors = $survivors
      duration_ms = $run.DurationMs
    }
  }

  for ($trial = 1; $trial -le $Trials; $trial++) {
    $trialRoot = Join-Path $runRoot "env-$trial"
    New-Item -ItemType Directory -Force -Path $trialRoot | Out-Null
    $ledger = Join-Path $trialRoot 'processes.jsonl'
    $environment = New-ScrubbedEnvironment $trialRoot
    $run = [Apf.Gate0.Broker]::Run(
      $nodePath,
      (New-FixtureArguments -Attack 'env' -Scratch $trialRoot -Ledger $ledger),
      $trialRoot,
      $environment,
      65536,
      65536,
      5000,
      'none',
      16
    )
    $payload = [Text.Encoding]::UTF8.GetString($run.Stdout.Captured).Trim() | ConvertFrom-Json
    $leaks = @($canaryNames | Where-Object { $payload.values.$_ })
    $homeMatches = $payload.home -eq $environment['HOME'] -and $payload.userprofile -eq $environment['USERPROFILE']
    $passed = $leaks.Count -eq 0 -and $homeMatches -and -not $run.TimedOut
    $probeResults += [pscustomobject]@{
      probe_id = 'T0.5.ENV_INHERITANCE'
      trial = $trial
      outcome = if ($passed) { 'PASSED' } else { 'FAILED' }
      observed_enforcement = if ($passed) { 'OS_ENFORCED' } else { 'UNKNOWN' }
      leaked_canaries = $leaks
      redirected_home = $homeMatches
      duration_ms = $run.DurationMs
    }
  }

  for ($trial = 1; $trial -le $Trials; $trial++) {
    $trialRoot = Join-Path $runRoot "output-$trial"
    New-Item -ItemType Directory -Force -Path $trialRoot | Out-Null
    $ledger = Join-Path $trialRoot 'processes.jsonl'
    $run = [Apf.Gate0.Broker]::Run(
      $nodePath,
      (New-FixtureArguments -Attack 'flood' -Scratch $trialRoot -Ledger $ledger),
      $trialRoot,
      (New-ScrubbedEnvironment $trialRoot),
      32768,
      32768,
      10000,
      'none',
      16
    )
    $passed = -not $run.TimedOut -and $run.Stdout.TotalBytes -eq 2097152 -and
      $run.Stderr.TotalBytes -eq 2097152 -and $run.Stdout.Truncated -and $run.Stderr.Truncated -and
      $run.Stdout.Captured.Length -eq 32768 -and $run.Stderr.Captured.Length -eq 32768
    $probeResults += [pscustomobject]@{
      probe_id = 'T0.5.OUTPUT_CAP'
      trial = $trial
      outcome = if ($passed) { 'PASSED' } else { 'FAILED' }
      observed_enforcement = if ($passed) { 'APF_VERIFIED' } else { 'UNKNOWN' }
      stdout_bytes = $run.Stdout.TotalBytes
      stderr_bytes = $run.Stderr.TotalBytes
      captured_each = 32768
      duration_ms = $run.DurationMs
    }
  }

  $networkRoot = Join-Path $runRoot 'network-loopback'
  New-Item -ItemType Directory -Force -Path $networkRoot | Out-Null
  $networkLedger = Join-Path $networkRoot 'processes.jsonl'
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try {
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $acceptTask = $listener.AcceptTcpClientAsync()
    $networkRun = [Apf.Gate0.Broker]::Run(
      $nodePath,
      (New-FixtureArguments -Attack 'network' -Scratch $networkRoot -Ledger $networkLedger -Depth $port),
      $networkRoot,
      (New-ScrubbedEnvironment $networkRoot),
      16384,
      16384,
      5000,
      'none',
      16
    )
    $accepted = $acceptTask.Wait(2000)
    $received = ''
    if ($accepted) {
      $client = $acceptTask.Result
      try {
        $reader = New-Object System.IO.StreamReader($client.GetStream(), [Text.Encoding]::UTF8)
        $received = $reader.ReadToEnd()
        $reader.Dispose()
      } finally {
        $client.Dispose()
      }
    }
    $networkReachable = $accepted -and $received -eq 'APF-SYNTHETIC-LOOPBACK-CANARY'
    $probeResults += [pscustomobject]@{
      probe_id = 'T0.7.LOOPBACK_EGRESS'
      trial = 1
      outcome = if ($networkReachable) { 'REACHABLE' } else { 'BLOCKED' }
      observed_enforcement = 'ADVISORY'
      interpretation = if ($networkReachable) { 'The Layer A broker does not prevent process-level network access.' } else { 'Loopback was blocked by an external mechanism.' }
      public_egress_attempted = $false
      duration_ms = $networkRun.DurationMs
    }
  } finally {
    $listener.Stop()
  }

  $sanitizerCorpus = @(
    "plain text",
    "`e[31mred`e[0m",
    "`e]8;;https://example.invalid`aclick`e]8;;`a",
    "before`rforged",
    "left$([char]0x202e)right"
  )
  $sanitizerPassed = $true
  foreach ($sample in $sanitizerCorpus) {
    $safe = ConvertTo-SafeTerminalText $sample
    if ($safe -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]') {
      $sanitizerPassed = $false
    }
  }
  $probeResults += [pscustomobject]@{
    probe_id = 'T0.5.TERMINAL_SANITIZER'
    trial = 1
    outcome = if ($sanitizerPassed) { 'PASSED' } else { 'FAILED' }
    observed_enforcement = if ($sanitizerPassed) { 'APF_VERIFIED' } else { 'UNKNOWN' }
    corpus_cases = $sanitizerCorpus.Count
  }
} finally {
  foreach ($name in $canaryNames) {
    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
  }
}

$failed = @($probeResults | Where-Object { $_.outcome -in @('FAILED', 'UNDETECTED') })
$evidence = [ordered]@{
  schema_version = 1
  run_id = $runId
  checked_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  platform = 'windows-x64'
  layer = 'A_MECHANISM_ONLY'
  trials = $Trials
  node_sha256 = (Get-FileHash -LiteralPath $nodePath -Algorithm SHA256).Hash.ToLowerInvariant()
  result = if ($failed.Count -eq 0) { 'LAYER_A_PASS_WITH_ADVISORY' } else { 'LAYER_A_FAIL' }
  limitations = @(
    'No provider process was executed.',
    'Environment enforcement covers inheritance only, not same-user files or credential stores.',
    'Output caps are broker verification, not an OS sandbox.',
    'CTRL_BREAK graceful cancellation was not tested.',
    'Only loopback reachability was tested; no public egress was attempted.'
  )
  probes = $probeResults
}
$evidencePath = Join-Path $runRoot 'evidence.json'
$evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
$evidenceSha256 = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Output "GATE 0 LAYER A: $($evidence.result)"
Write-Output "Trials: process=$Trials env=$Trials output=$Trials network-loopback=1 sanitizer=1"
Write-Output "Evidence: $evidencePath"
Write-Output "Evidence SHA-256: $evidenceSha256"

if ($failed.Count -gt 0) { exit 1 }
