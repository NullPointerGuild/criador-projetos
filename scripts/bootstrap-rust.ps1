[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolLockPath = Join-Path $PSScriptRoot 'tools.lock.json'
$toolLock = Get-Content -Raw -Encoding UTF8 -LiteralPath $toolLockPath | ConvertFrom-Json
if ($toolLock.schema_version -ne 1 -or $toolLock.platform -ne 'windows-x64') {
  throw 'Unsupported or invalid scripts/tools.lock.json.'
}

function Assert-Sha256Value {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if ($Value -notmatch '^[0-9a-f]{64}$') {
    throw "$Label must be a lowercase SHA-256 digest."
  }
}

function Assert-FileSha256 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Label is missing: $Path"
  }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) {
    throw "$Label digest mismatch. Expected $Expected, got $actual."
  }
}

function Get-TreeSha256 {
  param([Parameter(Mandatory = $true)][string]$Root)

  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
  [string[]]$entries = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -File | ForEach-Object {
    $relative = $_.FullName.Substring($resolvedRoot.Length).TrimStart('\').Replace('\', '/')
    $digest = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relative`t$($_.Length)`t$digest"
  })
  [Array]::Sort($entries, [StringComparer]::Ordinal)
  $payload = ($entries -join "`n") + "`n"
  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($payload)
    return ($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
  } finally {
    $sha256.Dispose()
  }
}

function Invoke-PinnedDownload {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    Assert-FileSha256 -Path $Path -Expected $ExpectedSha256 -Label $Label
    return
  }
  $partialPath = "$Path.partial-$PID-$([guid]::NewGuid().ToString('N'))"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $partialPath
    Assert-FileSha256 -Path $partialPath -Expected $ExpectedSha256 -Label $Label
    Move-Item -LiteralPath $partialPath -Destination $Path
  } finally {
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-NativeCapture {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = @(& $Path @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousPreference
  return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
}

foreach ($entry in @(
  @([string]$toolLock.rust.rustup_init_sha256, 'rustup-init'),
  @([string]$toolLock.rust.toolchain_tree_sha256, 'Rust toolchain tree'),
  @([string]$toolLock.c_toolchain.archive_sha256, 'LLVM-MinGW archive'),
  @([string]$toolLock.c_toolchain.clang_executable_sha256, 'clang executable'),
  @([string]$toolLock.c_toolchain.dlltool_executable_sha256, 'dlltool executable'),
  @([string]$toolLock.c_toolchain.llvm_ar_executable_sha256, 'llvm-ar executable')
)) {
  Assert-Sha256Value -Value $entry[0] -Label $entry[1]
}
foreach ($fileName in @(
  [string]$toolLock.rust.rustup_init_file,
  [string]$toolLock.c_toolchain.archive_file,
  [string]$toolLock.c_toolchain.distribution_directory
)) {
  if (
    $fileName -in @('.', '..') -or
    $fileName -notmatch '^[A-Za-z0-9._-]+$' -or
    [IO.Path]::GetFileName($fileName) -ne $fileName
  ) {
    throw "Tool lock file/directory names must be bounded plain names: $fileName"
  }
}
if ([string]$toolLock.rust.toolchain -notmatch '^1\.98\.0-x86_64-pc-windows-gnu$') {
  throw 'Rust toolchain must match the reviewed Windows GNU toolchain.'
}
if ([string]$toolLock.c_toolchain.version -notmatch '^20260826$') {
  throw 'LLVM-MinGW version must match the reviewed distribution.'
}
if ([string]$toolLock.rust.rustup_init_url -notmatch '^https://static\.rust-lang\.org/rustup/dist/') {
  throw 'rustup-init URL is outside the allowed official origin.'
}
if ([string]$toolLock.c_toolchain.archive_url -notmatch '^https://github\.com/mstorsjo/llvm-mingw/releases/download/') {
  throw 'LLVM-MinGW URL is outside the allowed official release origin.'
}

$toolsRoot = Join-Path $repoRoot '.tools'
$downloadsRoot = Join-Path $toolsRoot 'downloads'
$rustupHome = Join-Path $toolsRoot 'rustup-home'
$cargoHome = Join-Path $toolsRoot 'cargo-home'
$rustupInitPath = Join-Path $downloadsRoot ([string]$toolLock.rust.rustup_init_file)
$rustupPath = Join-Path $cargoHome 'bin\rustup.exe'
$toolchain = [string]$toolLock.rust.toolchain
$toolchainRoot = Join-Path $rustupHome "toolchains\$toolchain"
$toolchainBin = Join-Path $toolchainRoot 'bin'
$cargoPath = Join-Path $toolchainBin 'cargo.exe'
$rustcPath = Join-Path $toolchainBin 'rustc.exe'
$rustfmtPath = Join-Path $toolchainBin 'rustfmt.exe'
$clippyPath = Join-Path $toolchainBin 'clippy-driver.exe'
$llvmMingwRoot = Join-Path $toolsRoot "llvm-mingw-$($toolLock.c_toolchain.version)"
$llvmMingwDistributionRoot = Join-Path $llvmMingwRoot ([string]$toolLock.c_toolchain.distribution_directory)
$llvmMingwArchivePath = Join-Path $downloadsRoot ([string]$toolLock.c_toolchain.archive_file)
$clangPath = Join-Path $llvmMingwDistributionRoot 'bin\clang.exe'
$llvmArPath = Join-Path $llvmMingwDistributionRoot 'bin\llvm-ar.exe'
$dlltoolSourcePath = Join-Path $llvmMingwDistributionRoot 'bin\dlltool.exe'
$rustLinkToolsRoot = Join-Path $toolsRoot 'rust-link-tools'
$dlltoolPath = Join-Path $rustLinkToolsRoot 'dlltool.exe'

$environmentNames = @(
  'CARGO_HOME', 'CARGO_TARGET_DIR', 'RUSTFLAGS', 'RUSTDOCFLAGS', 'RUSTC_WRAPPER',
  'RUSTC_WORKSPACE_WRAPPER', 'RUSTUP_HOME', 'RUSTUP_TOOLCHAIN', 'RUSTUP_DIST_SERVER',
  'RUSTUP_UPDATE_ROOT'
)
$environmentSnapshot = @{}
foreach ($name in $environmentNames) {
  $environmentSnapshot[$name] = [pscustomobject]@{
    Exists = Test-Path -LiteralPath "Env:$name"
    Value = [Environment]::GetEnvironmentVariable($name, 'Process')
  }
}
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory -Force -Path $downloadsRoot, $rustupHome, $cargoHome, $llvmMingwRoot, $rustLinkToolsRoot | Out-Null

  Invoke-PinnedDownload -Uri ([string]$toolLock.rust.rustup_init_url) -Path $rustupInitPath -ExpectedSha256 $toolLock.rust.rustup_init_sha256 -Label 'rustup-init executable'
  Invoke-PinnedDownload -Uri ([string]$toolLock.c_toolchain.archive_url) -Path $llvmMingwArchivePath -ExpectedSha256 $toolLock.c_toolchain.archive_sha256 -Label 'LLVM-MinGW archive'

  if (-not (Test-Path -LiteralPath $llvmMingwDistributionRoot -PathType Container)) {
    $extractRoot = Join-Path $llvmMingwRoot ".extract-$PID-$([guid]::NewGuid().ToString('N'))"
    try {
      New-Item -ItemType Directory -Path $extractRoot | Out-Null
      Expand-Archive -LiteralPath $llvmMingwArchivePath -DestinationPath $extractRoot
      $extractedDistribution = Join-Path $extractRoot ([string]$toolLock.c_toolchain.distribution_directory)
      Assert-FileSha256 -Path (Join-Path $extractedDistribution 'bin\clang.exe') -Expected $toolLock.c_toolchain.clang_executable_sha256 -Label 'extracted LLVM-MinGW clang executable'
      Assert-FileSha256 -Path (Join-Path $extractedDistribution 'bin\llvm-ar.exe') -Expected $toolLock.c_toolchain.llvm_ar_executable_sha256 -Label 'extracted LLVM-MinGW llvm-ar executable'
      Assert-FileSha256 -Path (Join-Path $extractedDistribution 'bin\dlltool.exe') -Expected $toolLock.c_toolchain.dlltool_executable_sha256 -Label 'extracted LLVM-MinGW dlltool executable'
      Move-Item -LiteralPath $extractedDistribution -Destination $llvmMingwDistributionRoot
    } finally {
      Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  Assert-FileSha256 -Path $clangPath -Expected $toolLock.c_toolchain.clang_executable_sha256 -Label 'LLVM-MinGW clang executable'
  Assert-FileSha256 -Path $llvmArPath -Expected $toolLock.c_toolchain.llvm_ar_executable_sha256 -Label 'LLVM-MinGW llvm-ar executable'
  Assert-FileSha256 -Path $dlltoolSourcePath -Expected $toolLock.c_toolchain.dlltool_executable_sha256 -Label 'LLVM-MinGW dlltool executable'
  if (-not (Test-Path -LiteralPath $dlltoolPath -PathType Leaf)) {
    Copy-Item -LiteralPath $dlltoolSourcePath -Destination $dlltoolPath
  }
  Assert-FileSha256 -Path $dlltoolPath -Expected $toolLock.c_toolchain.dlltool_executable_sha256 -Label 'Rust link dlltool executable'

  $clangVersionResult = Invoke-NativeCapture -Path $clangPath -Arguments @('--version')
  $clangVersion = $clangVersionResult.Output -join "`n"
  if (
    $clangVersionResult.ExitCode -ne 0 -or
    $clangVersion -notmatch [regex]::Escape("clang version $($toolLock.c_toolchain.llvm_version)") -or
    $clangVersion -notmatch [regex]::Escape("Target: $($toolLock.c_toolchain.target)")
  ) {
    throw "Unexpected LLVM-MinGW clang version or target: $clangVersion"
  }

  foreach ($name in $environmentNames | Where-Object { $_ -notin @('RUSTUP_HOME', 'CARGO_HOME') }) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
  }
  $env:RUSTUP_HOME = $rustupHome
  $env:CARGO_HOME = $cargoHome

  if (-not (Test-Path -LiteralPath $rustupPath -PathType Leaf)) {
    $installArgs = @('-y', '--no-modify-path', '--profile', 'minimal', '--default-toolchain', 'none')
    & $rustupInitPath @installArgs
    if ($LASTEXITCODE -ne 0) {
      throw 'rustup-init failed.'
    }
  }
  Assert-FileSha256 -Path $rustupPath -Expected $toolLock.rust.rustup_init_sha256 -Label 'repository-local rustup executable'

  $rustupVersionResult = Invoke-NativeCapture -Path $rustupPath -Arguments @('--version')
  $rustupVersion = $rustupVersionResult.Output -join "`n"
  if ($rustupVersionResult.ExitCode -ne 0 -or $rustupVersion -notmatch [regex]::Escape("rustup $($toolLock.rust.rustup_version)")) {
    throw "Unexpected rustup version: $rustupVersion"
  }

  $autoUpdateResult = Invoke-NativeCapture -Path $rustupPath -Arguments @('set', 'auto-self-update', 'disable')
  if ($autoUpdateResult.ExitCode -ne 0) {
    throw 'Could not disable rustup self-update in the repository-local home.'
  }

  $toolchainListResult = Invoke-NativeCapture -Path $rustupPath -Arguments @('toolchain', 'list')
  $installedToolchains = $toolchainListResult.Output
  if ($toolchainListResult.ExitCode -ne 0) {
    throw "Could not list Rust toolchains: $($toolchainListResult.Output -join ' ')"
  }
  if (-not ($installedToolchains | Where-Object { $_ -match "^$([regex]::Escape($toolchain))(\s|$)" })) {
    $toolchainArgs = @(
      'toolchain', 'install', $toolchain,
      '--profile', 'minimal',
      '--component', 'clippy',
      '--component', 'rustfmt',
      '--no-self-update'
    )
    $toolchainInstallResult = Invoke-NativeCapture -Path $rustupPath -Arguments $toolchainArgs
    if ($toolchainInstallResult.ExitCode -ne 0) {
      throw "Could not install pinned Rust toolchain $toolchain`: $($toolchainInstallResult.Output -join ' ')"
    }
  }

  $toolchainTreeSha256 = Get-TreeSha256 -Root $toolchainRoot
  if ($toolchainTreeSha256 -ne $toolLock.rust.toolchain_tree_sha256) {
    throw "Rust toolchain tree digest mismatch. Expected $($toolLock.rust.toolchain_tree_sha256), got $toolchainTreeSha256."
  }

  $rustcVersionResult = Invoke-NativeCapture -Path $rustcPath -Arguments @('--version', '--verbose')
  $rustcVersion = $rustcVersionResult.Output -join "`n"
  if (
    $rustcVersionResult.ExitCode -ne 0 -or
    $rustcVersion -notmatch "^rustc $([regex]::Escape([string]$toolLock.rust.version))\b" -or
    $rustcVersion -notmatch [regex]::Escape("commit-hash: $($toolLock.rust.rustc_commit)") -or
    $rustcVersion -notmatch [regex]::Escape("host: $($toolLock.rust.target)")
  ) {
    throw "Unexpected rustc version, commit or target: $rustcVersion"
  }
  $cargoVersionResult = Invoke-NativeCapture -Path $cargoPath -Arguments @('--version', '--verbose')
  $cargoVersion = $cargoVersionResult.Output -join "`n"
  if (
    $cargoVersionResult.ExitCode -ne 0 -or
    $cargoVersion -notmatch "^cargo $([regex]::Escape([string]$toolLock.rust.cargo_version))\b" -or
    $cargoVersion -notmatch [regex]::Escape("commit-hash: $($toolLock.rust.cargo_commit)")
  ) {
    throw "Unexpected Cargo version or commit: $cargoVersion"
  }
  $rustfmtVersionResult = Invoke-NativeCapture -Path $rustfmtPath -Arguments @('--version')
  if ($rustfmtVersionResult.ExitCode -ne 0 -or ($rustfmtVersionResult.Output -join "`n") -notmatch "^rustfmt $([regex]::Escape([string]$toolLock.rust.rustfmt_version))\b") {
    throw "Unexpected rustfmt version: $($rustfmtVersionResult.Output -join ' ')"
  }
  $clippyVersionResult = Invoke-NativeCapture -Path $clippyPath -Arguments @('--version')
  if ($clippyVersionResult.ExitCode -ne 0 -or ($clippyVersionResult.Output -join "`n") -notmatch "^clippy $([regex]::Escape([string]$toolLock.rust.clippy_version))\b") {
    throw "Unexpected Clippy version: $($clippyVersionResult.Output -join ' ')"
  }

  Get-ChildItem -LiteralPath (Join-Path $cargoHome 'bin') -Filter '*.exe' -File |
    Where-Object { $_.Name -ne 'rustup.exe' } |
    ForEach-Object {
      Assert-FileSha256 -Path $_.FullName -Expected $toolLock.rust.rustup_init_sha256 -Label "rustup proxy $($_.Name)"
      Remove-Item -LiteralPath $_.FullName -Force
    }

  Write-Output $cargoPath
} finally {
  foreach ($name in $environmentNames) {
    $snapshot = $environmentSnapshot[$name]
    [Environment]::SetEnvironmentVariable(
      $name,
      $(if ($snapshot.Exists) { $snapshot.Value } else { $null }),
      'Process'
    )
  }
  [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}
