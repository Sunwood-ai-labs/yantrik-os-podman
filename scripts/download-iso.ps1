<#
.SYNOPSIS
    Downloads the latest Yantrik OS Nightly ISO and verifies its SHA256 checksum.
.DESCRIPTION
    Queries https://iso.yantrikos.com/nightly/latest.json for the latest ISO filename
    and SHA256 digest, downloads the image to ./yantrik.iso using curl.exe with
    resume support, and validates the file hash before completing.
#>
param(
    [string]$MetadataUrl = 'https://iso.yantrikos.com/nightly/latest.json',
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'yantrik.iso'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-SharedFileSha256([string]$Path) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToUpperInvariant()
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha256.Dispose()
    }
}

Write-Host "==> Fetching Yantrik OS nightly metadata from $MetadataUrl ..." -ForegroundColor Cyan
$meta = Invoke-RestMethod -Uri $MetadataUrl -UseBasicParsing
if (-not $meta.file -or -not $meta.sha256) {
    throw "Invalid metadata response from $MetadataUrl"
}

$baseUrl = $MetadataUrl.Substring(0, $MetadataUrl.LastIndexOf('/') + 1)
$downloadUrl = if ($meta.url) { $meta.url } else { $baseUrl + $meta.file }
$expectedHash = $meta.sha256.Trim().ToUpperInvariant()

Write-Host "    Version : $($meta.version) ($($meta.date))"
Write-Host "    File    : $($meta.file) ($($meta.bytes) bytes)"
Write-Host "    URL     : $downloadUrl"
Write-Host "    SHA256  : $expectedHash"

if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    Write-Host "==> Existing ISO found at $OutputPath. Verifying SHA256..." -ForegroundColor Yellow
    $actualHash = Get-SharedFileSha256 -Path $OutputPath
    if ($actualHash -eq $expectedHash) {
        Write-Host "==> Checksum verified ($actualHash). Skipping download." -ForegroundColor Green
        exit 0
    }
    Write-Warning "Existing file hash ($actualHash) does not match expected ($expectedHash). Re-downloading..."
}

Write-Host "==> Downloading ISO to $OutputPath ..." -ForegroundColor Cyan
& curl.exe -fL --retry 3 --continue-at - -o $OutputPath $downloadUrl
if ($LASTEXITCODE -ne 0) {
    throw "curl.exe failed with exit code $LASTEXITCODE"
}

Write-Host "==> Verifying SHA256 checksum ..." -ForegroundColor Cyan
$finalHash = Get-SharedFileSha256 -Path $OutputPath
if ($finalHash -ne $expectedHash) {
    throw "SHA256 mismatch! Expected $expectedHash, got $finalHash"
}

Write-Host "==> Successfully downloaded and verified $OutputPath ($finalHash)" -ForegroundColor Green
