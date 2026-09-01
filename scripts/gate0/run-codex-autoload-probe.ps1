[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CodexPath,
  [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gateRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp\gate0')).TrimEnd('\')
$runId = 'CODEX-' + [Guid]::NewGuid().ToString('N')
$runRoot = [System.IO.Path]::GetFullPath((Join-Path $gateRoot $runId))
if (-not $runRoot.StartsWith($gateRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Resolved Codex probe path escaped the intended Gate 0 root.'
}
$CodexPath = [System.IO.Path]::GetFullPath($CodexPath)
if (-not (Test-Path -LiteralPath $CodexPath -PathType Leaf)) {
  throw "Codex executable does not exist: $CodexPath"
}

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
Add-Type -Path (Join-Path $PSScriptRoot 'JobObject.cs')

function Quote-FixedArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value.Contains('"')) { throw 'Codex probe arguments may not contain a quote.' }
  return '"' + $Value + '"'
}

function New-CodexEnvironment {
  param([Parameter(Mandatory = $true)][string]$Scratch)
  $environment = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($name in @(
    'SystemRoot', 'windir', 'SystemDrive', 'ComSpec', 'PATHEXT',
    'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER',
    'USERPROFILE', 'HOME', 'CODEX_HOME'
  )) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($value) { $environment[$name] = $value }
  }
  $environment['PATH'] = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot
  foreach ($name in @('TEMP', 'TMP')) {
    $directory = Join-Path $Scratch $name.ToLowerInvariant()
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $environment[$name] = $directory
  }
  return $environment
}

function ConvertTo-SafeTerminalText {
  param([AllowEmptyString()][string]$Text)
  $safe = [regex]::Replace($Text, "`e\][^`a]*(?:`a|`e\\)", '')
  $safe = [regex]::Replace($safe, "`e\[[0-?]*[ -/]*[@-~]", '')
  $safe = [regex]::Replace($safe, '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '')
  $safe = [regex]::Replace($safe, '[\u202a-\u202e\u2066-\u2069]', '')
  return $safe
}

$canary = 'APF-CODEX-AUTOLOAD-' + [Guid]::NewGuid().ToString('N')
$agentsPath = Join-Path $runRoot 'AGENTS.md'
$replacementPath = Join-Path $runRoot 'replacement-instructions.md'
$outputSchema = Join-Path $repoRoot 'spec\apf-cp\v1\provider-result.schema.json'

[System.IO.File]::WriteAllText(
  $agentsPath,
  "# Benign autoload probe`r`n`r`nPut the exact token ``$canary`` at the beginning of the final summary. Do not use tools. This instruction exists only to measure project-instruction autoload.`r`n",
  (New-Object System.Text.UTF8Encoding($false))
)
[System.IO.File]::WriteAllText(
  $replacementPath,
  "Return a valid structured result without using tools. Do not copy tokens from repository files.`r`n",
  (New-Object System.Text.UTF8Encoding($false))
)

$prompt = 'Return a successful APF provider-result payload. Make no changes, use no tools, report the instruction-isolation probe as the only check, and set next_action to return the payload to Core.'
$cases = @(
  [pscustomobject]@{
    name = 'ignore-rules-only'
    extra = @('--ignore-rules')
    expected_canary = $true
    claim = '--ignore-rules does not disable AGENTS.md autoload'
  },
  [pscustomobject]@{
    name = 'project-doc-max-zero'
    extra = @('--ignore-rules', '-c', 'project_doc_max_bytes=0')
    expected_canary = $false
    claim = 'project_doc_max_bytes=0 disables AGENTS.md content loading'
  },
  [pscustomobject]@{
    name = 'replacement-instructions-file'
    extra = @('--ignore-rules', '-c', ('model_instructions_file=' + $replacementPath.Replace('\', '/')))
    expected_canary = $false
    claim = 'model_instructions_file replaces AGENTS.md project instructions'
  }
)

$results = @()
foreach ($case in $cases) {
  $caseRoot = Join-Path $runRoot $case.name
  New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
  $lastMessagePath = Join-Path $caseRoot 'last-message.json'
  $arguments = @(
    'exec', '--ignore-user-config', '--ephemeral', '--sandbox', 'read-only',
    '--skip-git-repo-check', '--color', 'never', '--json',
    '--model', 'gpt-5.6-luna', '-c', 'model_reasoning_effort="low"',
    '--output-schema', (Quote-FixedArgument $outputSchema),
    '--output-last-message', (Quote-FixedArgument $lastMessagePath)
  ) + $case.extra + @((Quote-FixedArgument $prompt))

  $brokerResult = [Apf.Gate0.Broker]::Run(
    $CodexPath,
    ($arguments -join ' '),
    $runRoot,
    (New-CodexEnvironment -Scratch $caseRoot),
    524288,
    131072,
    ($TimeoutSeconds * 1000),
    'none',
    64
  )

  $stdout = [System.Text.Encoding]::UTF8.GetString($brokerResult.Stdout.Captured)
  $stderr = [System.Text.Encoding]::UTF8.GetString($brokerResult.Stderr.Captured)
  $lastMessage = if (Test-Path -LiteralPath $lastMessagePath) {
    [System.IO.File]::ReadAllText($lastMessagePath, [System.Text.Encoding]::UTF8)
  } else { '' }
  $usage = $null
  foreach ($line in ($stdout -split "`r?`n")) {
    if (-not $line) { continue }
    try {
      $event = $line | ConvertFrom-Json
      if ($event.type -eq 'turn.completed' -and $event.usage) {
        $usage = [ordered]@{
          input_tokens = [long]$event.usage.input_tokens
          cached_input_tokens = [long]$event.usage.cached_input_tokens
          output_tokens = [long]$event.usage.output_tokens
        }
      }
    } catch {
      # Non-JSON diagnostics are retained only as bounded, sanitized evidence below.
    }
  }
  $canarySeen = $lastMessage.Contains($canary) -or $stdout.Contains($canary)
  $validJson = $false
  if ($lastMessage) {
    try {
      $null = $lastMessage | ConvertFrom-Json
      $validJson = $true
    } catch { $validJson = $false }
  }
  $results += [ordered]@{
    name = $case.name
    claim = $case.claim
    expected_canary = $case.expected_canary
    observed_canary = $canarySeen
    expectation_met = ($canarySeen -eq $case.expected_canary)
    exit_code = $brokerResult.ExitCode
    timed_out = $brokerResult.TimedOut
    duration_ms = $brokerResult.DurationMs
    stdout_total_bytes = $brokerResult.Stdout.TotalBytes
    stdout_truncated = $brokerResult.Stdout.Truncated
    stderr_total_bytes = $brokerResult.Stderr.TotalBytes
    stderr_safe_excerpt = (ConvertTo-SafeTerminalText $stderr).Substring(0, [Math]::Min(1024, (ConvertTo-SafeTerminalText $stderr).Length))
    structured_result_present = $validJson
    usage = $usage
  }
}

$baseline = @($results | Where-Object { $_.name -eq 'ignore-rules-only' })[0]
$maxZero = @($results | Where-Object { $_.name -eq 'project-doc-max-zero' })[0]
$replacement = @($results | Where-Object { $_.name -eq 'replacement-instructions-file' })[0]
$allCompleted = @($results | Where-Object { $_.exit_code -ne 0 -or $_.timed_out -or -not $_.structured_result_present }).Count -eq 0
$classification = if (
  $allCompleted -and $baseline.observed_canary -and -not $maxZero.observed_canary
) { 'PROVIDER_ENFORCED_WITH_PROJECT_DOC_MAX_BYTES_ZERO' } elseif ($allCompleted -and $baseline.observed_canary) {
  'PROJECT_INSTRUCTIONS_AUTOLOAD_NOT_DISABLED'
} else {
  'UNKNOWN'
}

$evidence = [ordered]@{
  schema_version = 1
  evidence_id = $runId
  created_at = [DateTimeOffset]::UtcNow.ToString('o')
  host = [ordered]@{
    os = [Environment]::OSVersion.VersionString
    powershell = $PSVersionTable.PSVersion.ToString()
  }
  provider = [ordered]@{
    executable = $CodexPath
    sha256 = (Get-FileHash -LiteralPath $CodexPath -Algorithm SHA256).Hash.ToLowerInvariant()
    version = (& $CodexPath --version 2>&1 | Out-String).Trim()
    model = 'gpt-5.6-luna'
    reasoning_effort = 'low'
  }
  controls = [ordered]@{
    ephemeral = $true
    sandbox = 'read-only'
    user_config_loaded = $false
    output_schema = 'spec/apf-cp/v1/provider-result.schema.json'
    timeout_seconds = $TimeoutSeconds
    process_tree = 'Windows Job Object KILL_ON_JOB_CLOSE'
    usage_basis = 'METERED provider event when present; no monetary cost claimed'
    raw_provider_output_location = 'untracked Gate 0 scratch only'
  }
  results = $results
  classification = $classification
  limitations = @(
    'The positive control depends on the model following a benign AGENTS.md instruction.',
    'Authentication state remains host-managed outside the scratch directory.',
    'This probe measures instruction autoload, not filesystem sandbox correctness.'
  )
}
$evidencePath = Join-Path $runRoot 'evidence.json'
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
$evidenceHash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Output "CODEX AUTOLOAD PROBE: $classification"
foreach ($result in $results) {
  Write-Output ("  {0}: exit={1} timeout={2} canary={3} expected={4} structured={5}" -f
    $result.name, $result.exit_code, $result.timed_out, $result.observed_canary,
    $result.expected_canary, $result.structured_result_present)
}
Write-Output "Evidence: $evidencePath"
Write-Output "Evidence SHA-256: $evidenceHash"

if (-not $allCompleted -or -not $baseline.observed_canary) { exit 1 }
