param(
    [Parameter(Position = 0)]
    [ValidateSet("package", "deploy", "bump", "help")]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [ValidateSet("patch", "minor", "major")]
    [string]$BumpType = "patch"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# Helpers

function Get-ModInfo {
    $infoPath = Join-Path $ScriptDir "info.json"
    return Get-Content $infoPath -Raw | ConvertFrom-Json
}

function Get-FactorioModsDir {
    $appdata = [Environment]::GetFolderPath("ApplicationData")
    $modsDir = Join-Path $appdata "Factorio\mods"
    if (-not (Test-Path $modsDir)) {
        Write-Error "Factorio mods directory not found at: $modsDir"
        exit 1
    }
    return $modsDir
}

# Files/folders to exclude from the release zip
$ExcludePatterns = @(
    "build.ps1",
    "comparison.png",
    ".git",
    ".gitignore",
    ".vscode",
    "*.zip",
    "README.md",
    "LICENSE",
    "CONTRIBUTING.md",
    ".github"
)

function Get-ModFiles {
    $allFiles = Get-ChildItem -Path $ScriptDir -File -Recurse
    return $allFiles | Where-Object {
        $relativePath = $_.FullName.Substring($ScriptDir.Length + 1)
        $excluded = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($relativePath -like $pattern -or $relativePath -like "$pattern\*") {
                $excluded = $true
                break
            }
        }
        -not $excluded
    }
}

# Actions

function Invoke-Package {
    $info = Get-ModInfo
    $modFolder = "$($info.name)_$($info.version)"
    $zipName = "$modFolder.zip"
    $zipPath = Join-Path $ScriptDir $zipName
    $tempDir = Join-Path $env:TEMP "minimalwire-build"
    $tempModDir = Join-Path $tempDir $modFolder

    # Clean up
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Create temp structure: modname_version/files
    New-Item -ItemType Directory -Path $tempModDir -Force | Out-Null

    $files = Get-ModFiles
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($ScriptDir.Length + 1)
        $destPath = Join-Path $tempModDir $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $file.FullName $destPath
    }

    # Create zip
    Compress-Archive -Path $tempModDir -DestinationPath $zipPath -Force
    Remove-Item $tempDir -Recurse -Force

    $size = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
    Write-Host "✅ Packaged: $zipName ($size KB)" -ForegroundColor Green
    Write-Host "   Upload this to the Factorio Mod Portal." -ForegroundColor DarkGray
}

function Invoke-Deploy {
    $info = Get-ModInfo
    $modsDir = Get-FactorioModsDir
    $modFolder = "$($info.name)_$($info.version)"
    $destDir = Join-Path $modsDir $modFolder

    # Remove any existing versions of this mod
    Get-ChildItem -Path $modsDir -Directory -Filter "$($info.name)_*" | ForEach-Object {
        Write-Host "   Removing old version: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item $_.FullName -Recurse -Force
    }

    # Copy mod files
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $files = Get-ModFiles
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($ScriptDir.Length + 1)
        $destPath = Join-Path $destDir $relativePath
        $fileDestDir = Split-Path $destPath -Parent
        if (-not (Test-Path $fileDestDir)) {
            New-Item -ItemType Directory -Path $fileDestDir -Force | Out-Null
        }
        Copy-Item $file.FullName $destPath
    }

    Write-Host "✅ Deployed: $modFolder -> $destDir" -ForegroundColor Green
    Write-Host "   Restart Factorio to load the updated mod." -ForegroundColor DarkGray
}

function Invoke-Bump {
    $infoPath = Join-Path $ScriptDir "info.json"
    $info = Get-ModInfo
    $parts = $info.version -split "\."
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    $oldVersion = $info.version

    switch ($BumpType) {
        "major" { $major++; $minor = 0; $patch = 0 }
        "minor" { $minor++; $patch = 0 }
        "patch" { $patch++ }
    }

    $newVersion = "$major.$minor.$patch"
    $info.version = $newVersion
    $info | ConvertTo-Json -Depth 10 | Set-Content $infoPath -Encoding UTF8

    # Add a changelog stub
    $changelogPath = Join-Path $ScriptDir "changelog.txt"
    if (Test-Path $changelogPath) {
        $today = Get-Date -Format "yyyy-MM-dd"
        $stub = @"
---------------------------------------------------------------------------------------------------
Version: $newVersion
Date: $today
  Changes:
    - 

"@
        $existing = Get-Content $changelogPath -Raw
        $stub + $existing | Set-Content $changelogPath -Encoding UTF8
    }

    Write-Host "✅ Bumped: $oldVersion -> $newVersion" -ForegroundColor Green
    Write-Host "   Don't forget to fill in changelog.txt!" -ForegroundColor DarkGray
}

function Invoke-Help {
    Write-Host ""
    Write-Host "MinimalWire Build Script" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build.ps1 <action> [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Yellow
    Write-Host "  package          Create a release .zip for the Factorio Mod Portal"
    Write-Host "  deploy           Copy mod to local Factorio mods folder for testing"
    Write-Host "  bump [type]      Bump version in info.json (patch|minor|major, default: patch)"
    Write-Host "  help             Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\build.ps1 package        # Build a .zip for upload"
    Write-Host "  .\build.ps1 deploy         # Deploy to Factorio mods folder"
    Write-Host "  .\build.ps1 bump           # 1.0.9 -> 1.0.10"
    Write-Host "  .\build.ps1 bump minor     # 1.0.9 -> 1.1.0"
    Write-Host "  .\build.ps1 bump major     # 1.0.9 -> 2.0.0"
    Write-Host ""
}

switch ($Action) {
    "package" { Invoke-Package }
    "deploy"  { Invoke-Deploy }
    "bump"    { Invoke-Bump }
    "help"    { Invoke-Help }
}
