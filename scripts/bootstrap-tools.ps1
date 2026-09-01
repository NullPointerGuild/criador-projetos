[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolLockPath = Join-Path $PSScriptRoot 'tools.lock.json'
$toolLock = Get-Content -Raw -Encoding UTF8 -LiteralPath $toolLockPath | ConvertFrom-Json
if ($toolLock.schema_version -ne 1 -or $toolLock.platform -ne 'windows-x64') {
  throw 'Unsupported or invalid scripts/tools.lock.json.'
}
$toolsRoot = Join-Path $repoRoot '.tools'
$downloadsRoot = Join-Path $toolsRoot 'downloads'
$sqliteRoot = Join-Path $toolsRoot 'sqlite-3.53.4'
$archivePath = Join-Path $downloadsRoot 'sqlite-tools-win-x64-3530400.zip'
$sqlitePath = Join-Path $sqliteRoot 'sqlite3.exe'
$downloadUri = 'https://www.sqlite.org/2026/sqlite-tools-win-x64-3530400.zip'
$expectedSha3 = $toolLock.sqlite.archive_sha3_256
$expectedSqliteArchiveSha256 = $toolLock.sqlite.archive_sha256
$expectedSqliteExeSha256 = $toolLock.sqlite.executable_sha256
$nodeRoot = Join-Path $toolsRoot 'node-24.20.0'
$nodeArchivePath = Join-Path $downloadsRoot 'node-v24.20.0-win-x64.zip'
$nodeDistributionRoot = Join-Path $nodeRoot 'node-v24.20.0-win-x64'
$nodePath = Join-Path $nodeDistributionRoot 'node.exe'
$npmPath = Join-Path $nodeDistributionRoot 'npm.cmd'
$nodeDownloadUri = 'https://nodejs.org/dist/v24.20.0/node-v24.20.0-win-x64.zip'
$expectedNodeSha256 = $toolLock.node.archive_sha256
$expectedNodeExeSha256 = $toolLock.node.executable_sha256
$expectedNodeTreeSha256 = $toolLock.node.distribution_tree_sha256
$schemaValidatorRoot = Join-Path $toolsRoot 'schema-validator'
$schemaValidatorManifestRoot = Join-Path $PSScriptRoot 'schema-validator'
$schemaValidatorManifestPath = Join-Path $schemaValidatorManifestRoot 'package.json'
$schemaValidatorLockPath = Join-Path $schemaValidatorManifestRoot 'package-lock.json'
$installedValidatorManifestPath = Join-Path $schemaValidatorRoot 'package.json'
$installedValidatorLockPath = Join-Path $schemaValidatorRoot 'package-lock.json'
$expectedValidatorLockSha256 = $toolLock.schema_validator.package_lock_sha256
$expectedValidatorTreeSha256 = $toolLock.schema_validator.tree_sha256
$npmConfigRoot = Join-Path $toolsRoot 'npm-config'

function Assert-FileSha256 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) { throw "$Label digest mismatch. Expected $Expected, got $actual." }
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

function Assert-TreeSha256 {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $actual = Get-TreeSha256 -Root $Root
  if ($actual -ne $Expected) { throw "$Label tree digest mismatch. Expected $Expected, got $actual." }
}

New-Item -ItemType Directory -Force -Path $downloadsRoot, $sqliteRoot, $nodeRoot, $schemaValidatorRoot, $npmConfigRoot | Out-Null
[System.IO.File]::WriteAllText((Join-Path $npmConfigRoot 'empty-user.ini'), '', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $npmConfigRoot 'empty-global.ini'), '', (New-Object System.Text.UTF8Encoding($false)))
foreach ($name in @('NODE_OPTIONS', 'NODE_PATH', 'NODE_REPL_EXTERNAL_MODULE', 'NODE_EXTRA_CA_CERTS', 'NPM_TOKEN')) {
  Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
}
$env:NPM_CONFIG_USERCONFIG = Join-Path $npmConfigRoot 'empty-user.ini'
$env:NPM_CONFIG_GLOBALCONFIG = Join-Path $npmConfigRoot 'empty-global.ini'
$env:NPM_CONFIG_CACHE = Join-Path $npmConfigRoot 'cache'

if (-not (Test-Path -LiteralPath $archivePath)) {
  Invoke-WebRequest -UseBasicParsing -Uri $downloadUri -OutFile $archivePath
}

Assert-FileSha256 -Path $archivePath -Expected $expectedSqliteArchiveSha256 -Label 'SQLite archive'

$openssl = Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'
if (-not (Test-Path -LiteralPath $openssl -PathType Leaf)) {
  throw 'The Git-for-Windows OpenSSL binary is required to verify the SQLite SHA3-256 digest.'
}

$digestOutput = & $openssl dgst -sha3-256 $archivePath
if ($LASTEXITCODE -ne 0) {
  throw 'Could not calculate the SQLite archive SHA3-256 digest.'
}

$actualSha3 = (($digestOutput -split '=')[-1]).Trim().ToLowerInvariant()
if ($actualSha3 -ne $expectedSha3) {
  throw "SQLite archive digest mismatch. Expected $expectedSha3, got $actualSha3."
}

if (-not (Test-Path -LiteralPath $sqlitePath)) {
  Expand-Archive -LiteralPath $archivePath -DestinationPath $sqliteRoot -Force
}

if (-not (Test-Path -LiteralPath $sqlitePath)) {
  throw 'sqlite3.exe was not found after extracting the verified archive.'
}
Assert-FileSha256 -Path $sqlitePath -Expected $expectedSqliteExeSha256 -Label 'SQLite executable'

$sqliteHandle = [System.IO.File]::Open($sqlitePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
  $version = & $sqlitePath -batch ':memory:' 'select sqlite_version();'
  if ($LASTEXITCODE -ne 0 -or $version.Trim() -ne $toolLock.sqlite.version) {
    throw "Unexpected SQLite version: $version"
  }
} finally {
  $sqliteHandle.Dispose()
}

if (-not (Test-Path -LiteralPath $nodeArchivePath)) {
  Invoke-WebRequest -UseBasicParsing -Uri $nodeDownloadUri -OutFile $nodeArchivePath
}

$actualNodeSha256 = (Get-FileHash -LiteralPath $nodeArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualNodeSha256 -ne $expectedNodeSha256) {
  throw "Node.js archive digest mismatch. Expected $expectedNodeSha256, got $actualNodeSha256."
}

if (-not (Test-Path -LiteralPath $nodePath)) {
  Expand-Archive -LiteralPath $nodeArchivePath -DestinationPath $nodeRoot -Force
}

if (-not (Test-Path -LiteralPath $nodePath) -or -not (Test-Path -LiteralPath $npmPath)) {
  throw 'The local Node.js distribution was not found after extracting the verified archive.'
}
Assert-FileSha256 -Path $nodePath -Expected $expectedNodeExeSha256 -Label 'Node.js executable'

$nodeHandle = [System.IO.File]::Open($nodePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
  $nodeVersion = & $nodePath --version
  if ($LASTEXITCODE -ne 0 -or $nodeVersion.Trim() -ne "v$($toolLock.node.version)") {
    throw "Unexpected Node.js version: $nodeVersion"
  }
} finally {
  $nodeHandle.Dispose()
}

$requiredPackages = @{
  'ajv' = '8.20.0'
  'ajv-formats' = '3.0.1'
}
$packagesReady = (Test-Path -LiteralPath $installedValidatorLockPath)
if ($packagesReady) {
  $sourceLockHash = (Get-FileHash -LiteralPath $schemaValidatorLockPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $installedLockHash = (Get-FileHash -LiteralPath $installedValidatorLockPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $packagesReady = $sourceLockHash -eq $expectedValidatorLockSha256 -and $installedLockHash -eq $expectedValidatorLockSha256
}
foreach ($package in $requiredPackages.GetEnumerator()) {
  if (-not $packagesReady) { break }
  $packageManifest = Join-Path $schemaValidatorRoot "node_modules\$($package.Key)\package.json"
  if (-not (Test-Path -LiteralPath $packageManifest)) {
    $packagesReady = $false
    break
  }

  $installedVersion = (Get-Content -Raw -Encoding UTF8 -LiteralPath $packageManifest | ConvertFrom-Json).version
  if ($installedVersion -ne $package.Value) {
    $packagesReady = $false
    break
  }
}

if ($packagesReady) {
  $packagesReady = (Get-TreeSha256 -Root $schemaValidatorRoot) -eq $expectedValidatorTreeSha256
}

if (-not $packagesReady) {
  Assert-TreeSha256 -Root $nodeRoot -Expected $expectedNodeTreeSha256 -Label 'Node.js distribution'
  Copy-Item -LiteralPath $schemaValidatorManifestPath -Destination $installedValidatorManifestPath -Force
  Copy-Item -LiteralPath $schemaValidatorLockPath -Destination $installedValidatorLockPath -Force
  $npmOutput = & $npmPath ci --prefix $schemaValidatorRoot --ignore-scripts --no-audit --no-fund 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Could not install the local JSON Schema validator: $($npmOutput -join ' ')"
  }
}

Assert-TreeSha256 -Root $schemaValidatorRoot -Expected $expectedValidatorTreeSha256 -Label 'JSON Schema validator'

Write-Output $sqlitePath
