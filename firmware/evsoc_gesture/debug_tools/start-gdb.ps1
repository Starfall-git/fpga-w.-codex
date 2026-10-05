param([string]$Sdk = 'C:\Users\SteLl1a\Desktop\Work\FPGA_Contest\env\RISCV-IDE')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Sdk 'toolchain/bin/riscv-none-elf-gdb.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "GDB not found: $exe" }
Push-Location $PSScriptRoot
try {
    & $exe -q -x debug/load.gdb
    if ($LASTEXITCODE -ne 0) { throw "GDB exited with $LASTEXITCODE" }
} finally { Pop-Location }
