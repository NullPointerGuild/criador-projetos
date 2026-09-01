[CmdletBinding()]
param(
  [ValidateSet('GenerateLock', 'Check', 'Build', 'Test', 'Format', 'FormatWrite', 'Clippy')]
  [string]$Task = 'Check'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $repoRoot '.tools'
$toolLock = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'tools.lock.json') | ConvertFrom-Json
$fixedEnvironmentNames = @(
  'AR', 'CARGO_HOME', 'CARGO_TARGET_DIR', 'CC', 'CFLAGS', 'LIBSQLITE3_FLAGS',
  'LIBSQLITE3_SYS_USE_PKG_CONFIG', 'PATH', 'PKG_CONFIG_PATH', 'RUSTC', 'RUSTDOC',
  'RUSTFLAGS', 'RUSTDOCFLAGS', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER',
  'RUSTUP_HOME', 'RUSTUP_TOOLCHAIN', 'RUSTUP_DIST_SERVER', 'RUSTUP_UPDATE_ROOT',
  'SQLITE_MAX_VARIABLE_NUMBER', 'SQLITE_MAX_EXPR_DEPTH', 'SQLITE3_LIB_DIR',
  'SQLITE3_INCLUDE_DIR', 'VCPKG_ROOT'
)
$secretEnvironmentNames = @(Get-ChildItem Env: | Where-Object {
  $_.Name -match '(^|_)(TOKEN|KEY|SECRET|PASSWORD)$' -or
  $_.Name -match '^(AWS|AZURE|GOOGLE|GCP|OPENAI|ANTHROPIC|GITHUB|GITLAB)_'
} | Select-Object -ExpandProperty Name)
$environmentNames = @($fixedEnvironmentNames + $secretEnvironmentNames | Select-Object -Unique)
$environmentSnapshot = @{}
foreach ($name in $environmentNames) {
  $environmentSnapshot[$name] = [pscustomobject]@{
    Exists = Test-Path -LiteralPath "Env:$name"
    Value = [Environment]::GetEnvironmentVariable($name, 'Process')
  }
}

$locationPushed = $false
try {
  foreach ($name in $environmentNames | Where-Object { $_ -ne 'PATH' }) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
  }

  $env:RUSTUP_HOME = Join-Path $toolsRoot 'rustup-home'
  $env:CARGO_HOME = Join-Path $toolsRoot 'cargo-home'
  $cargoPath = @(& (Join-Path $PSScriptRoot 'bootstrap-rust.ps1'))[-1]
  if (-not (Test-Path -LiteralPath $cargoPath -PathType Leaf)) {
    throw "Repository-local Cargo executable was not found: $cargoPath"
  }

  $toolchainBin = Split-Path -Parent $cargoPath
  $env:RUSTC = Join-Path $toolchainBin 'rustc.exe'
  $env:RUSTDOC = Join-Path $toolchainBin 'rustdoc.exe'
  $env:CARGO_TARGET_DIR = Join-Path $repoRoot '.tmp\cargo-target'
  $llvmMingwBin = Join-Path $toolsRoot "llvm-mingw-$($toolLock.c_toolchain.version)\$($toolLock.c_toolchain.distribution_directory)\bin"
  $env:CC = Join-Path $llvmMingwBin 'clang.exe'
  $env:AR = Join-Path $llvmMingwBin 'llvm-ar.exe'
  $env:PATH = "$toolchainBin;$(Join-Path $toolsRoot 'rust-link-tools');$($environmentSnapshot['PATH'].Value)"

  [string[]]$cargoArguments = @(switch ($Task) {
    'GenerateLock' { @('generate-lockfile') }
    'Check' { @('check', '--workspace', '--frozen') }
    'Build' { @('build', '--workspace', '--frozen') }
    'Test' { @('test', '--workspace', '--frozen') }
    'Format' { @('fmt', '--all', '--check') }
    'FormatWrite' { @('fmt', '--all') }
    'Clippy' { @('clippy', '--workspace', '--all-targets', '--frozen', '--', '-D', 'warnings') }
  })

  Push-Location -LiteralPath $repoRoot
  $locationPushed = $true
  if ($Task -ne 'GenerateLock') {
    & $cargoPath fetch --locked
    if ($LASTEXITCODE -ne 0) {
      throw "Cargo fetch failed with exit code $LASTEXITCODE."
    }
  }
  & $cargoPath @cargoArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Cargo failed with exit code $LASTEXITCODE."
  }
} finally {
  if ($locationPushed) {
    Pop-Location
  }
  foreach ($name in $environmentNames) {
    $snapshot = $environmentSnapshot[$name]
    [Environment]::SetEnvironmentVariable(
      $name,
      $(if ($snapshot.Exists) { $snapshot.Value } else { $null }),
      'Process'
    )
  }
}
