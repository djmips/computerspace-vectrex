# build.ps1 - assemble Computer Space with VIDE's assembler (Asmj) from the vecx-run kit.
#
#   powershell -ExecutionPolicy Bypass -File build.ps1
#
# Output: build\computerspace.bin (the cartridge, single bank, at most 32K) and
# build\computerspace.cnt (VIDE symbols). Set VECX_KIT to the vecx-run kit's folder.
# Windows PowerShell 5.1 syntax only.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$kit = $env:VECX_KIT
if (-not $kit) { Write-Host "set VECX_KIT to the vecx-run kit's folder"; exit 1 }
$script = Join-Path $kit "scripts\build-banks.ps1"
if (-not (Test-Path $script)) { Write-Host "vecx-run kit not found: $script"; exit 1 }

& powershell -NoProfile -ExecutionPolicy Bypass -File $script -ProjectDir $here -Out build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bin = Join-Path $here "build\computerspace.bin"
$b = [IO.File]::ReadAllBytes($bin)
if ($b.Length -gt 32768) { Write-Host ("{0} is {1} bytes, over 32K" -f $bin, $b.Length); exit 1 }
$sig = [Text.Encoding]::ASCII.GetString($b, 0, 5)
if ($sig -ne "g GCE") { Write-Host "$bin does not start with the 'g GCE' header"; exit 1 }
Write-Host ("ok: {0} bytes, {1} free" -f $b.Length, (32768 - $b.Length))
exit 0
