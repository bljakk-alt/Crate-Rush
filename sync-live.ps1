$ErrorActionPreference = "Stop"

$source = "C:\Users\azurn\Documents\Crate Rush\CrateRush"
$target = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\CrateRush"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source addon folder not found: $source"
}

if (-not (Test-Path -LiteralPath $target)) {
    New-Item -ItemType Directory -Force -Path $target | Out-Null
}

Get-ChildItem -LiteralPath $source -Force | Copy-Item -Recurse -Force -Destination $target

Write-Host "Synced CrateRush workspace source to live WoW addon folder."
