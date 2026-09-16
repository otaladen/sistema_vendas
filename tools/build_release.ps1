# Builds release binaries for PC servidor (Windows) and reference targets.
# Run from repo root: powershell -ExecutionPolicy Bypass -File tools\build_release.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> flutter analyze (fatal: warnings+)"
flutter analyze --no-fatal-infos

Write-Host "==> Windows release (servidor / terminal com UI desktop)"
flutter build windows --release

Write-Host ""
Write-Host "Artefato servidor:" (Resolve-Path "build\windows\x64\runner\Release").Path
