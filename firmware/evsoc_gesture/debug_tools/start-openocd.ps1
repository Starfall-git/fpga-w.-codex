param([string]$Sdk = 'C:\Users\SteLl1a\Desktop\Work\FPGA_Contest\env\RISCV-IDE')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Sdk 'openocd/bin/openocd.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "OpenOCD not found: $exe" }
# Run interactively only when the user invokes this script after loading .bit.
Push-Location (Join-Path $PSScriptRoot 'debug')
try {
    & $exe -f cnn_ft232h_ti.cfg -f debug_ti.cfg
    if ($LASTEXITCODE -ne 0) { throw "OpenOCD exited with $LASTEXITCODE" }
} finally { Pop-Location }
