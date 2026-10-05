param(
    [string]$ReleaseDir = (Join-Path $PSScriptRoot '../deliverables/v0.5-ti60-debug-r1'),
    [string]$Sdk = 'C:\Users\SteLl1a\Desktop\Work\FPGA_Contest\env\RISCV-IDE',
    [ValidateSet(100, 400, 800)][int]$SpeedKHz = 100,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$release = (Resolve-Path -LiteralPath $ReleaseDir).Path
$exe = Join-Path $Sdk 'openocd/bin/openocd.exe'
$debugDir = Join-Path $release 'debug'
$source = Join-Path $debugDir 'debug_ti.cfg'
$adapter = Join-Path $debugDir 'cnn_ft232h_ti.cfg'
$bit = Join-Path $release 'hardware/Ti60_AR0135.bit'
foreach ($file in @($exe, $source, $adapter, $bit)) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing file: $file" }
}
$config = [IO.File]::ReadAllText($source)
# The official target file runs init itself. A later -c "adapter speed ..."
# would be too late. Change only its two modern/legacy speed declarations.
$modern = '(?m)^([ \t]*adapter speed )800(?=[ \t]*\r?$)'
$legacy = '(?m)^([ \t]*adapter_khz )800(?=[ \t]*\r?$)'
if ([regex]::Matches($config, $modern).Count -ne 1 -or
    [regex]::Matches($config, $legacy).Count -ne 1) {
    throw 'Unexpected BSP speed declarations; inspect debug_ti.cfg before adapting it.'
}
foreach ($pattern in @($modern, $legacy)) {
    $config = [regex]::Replace($config, $pattern, { param($m) $m.Groups[1].Value + $SpeedKHz })
}
$repo = Split-Path $PSScriptRoot -Parent
$run = Join-Path $repo ('artifacts/jtag-diagnostics/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $SpeedKHz + 'kHz')
[IO.Directory]::CreateDirectory($run) | Out-Null
$target = Join-Path $run 'debug_ti.cfg'
$log = Join-Path $run 'openocd.log'
[IO.File]::WriteAllText($target, $config, [Text.UTF8Encoding]::new($false))
$metadata = [ordered]@{
    release = $release; speed_khz = $SpeedKHz; openocd = $exe
    source_config_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    effective_config_sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    adapter_sha256 = (Get-FileHash -LiteralPath $adapter -Algorithm SHA256).Hash
    bit_file_sha256 = (Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash
    note = 'File hashes do not prove which image is currently on the board. No ELF load or Flash programming. Official init/halt may halt the CPU.'
    prepared_only = [bool]$PrepareOnly
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'metadata.json') -Encoding UTF8
Write-Host "Diagnostic folder: $run"
if ($PrepareOnly) { Write-Host 'Prepared only; no board connection attempted.'; exit 0 }
Write-Host 'Use after JTAG .bit download. Close other JTAG debug sessions first.'
Write-Host 'This runs official init/halt, without loading ELF or writing Flash.'
Write-Host 'Detailed output is in openocd.log. Stop with Ctrl+C after about 30 seconds if it keeps timing out.'
Write-Host "View it in another terminal: Get-Content -LiteralPath '$log' -Tail 50 -Wait"
Write-Host 'If CPU halt succeeds, leave this running and use the release start-gdb.ps1 in another terminal.'
# Keep the official relative cpu0.yaml lookup anchored at the release debug dir.
Push-Location $debugDir
try {
    & $exe -d3 -l $log -f $adapter -f $target
    if ($LASTEXITCODE -ne 0) { throw "OpenOCD exited with $LASTEXITCODE. Log: $log" }
} finally { Pop-Location }
