param([string]$Sdk = 'C:\Users\SteLl1a\Desktop\Work\FPGA_Contest\env\RISCV-IDE')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Sdk 'toolchain/bin/riscv-none-elf-gdb.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "GDB not found: $exe" }
function Invoke-GdbStep([string]$Name, [int]$TimeoutMs) {
    $out = Join-Path $PSScriptRoot "$Name.log"
    $err = Join-Path $PSScriptRoot "$Name.stderr.log"
    $proc = Start-Process -FilePath $exe -ArgumentList @('-batch', '-x', "debug/$Name.gdb") -WorkingDirectory $PSScriptRoot -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
    $null = $proc.Handle
    if (!$proc.WaitForExit($TimeoutMs)) {
        Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue
        throw "GDB $Name timed out; inspect OpenOCD and $Name logs."
    }
    if ($proc.ExitCode -ne 0) {
        Get-Content -LiteralPath $err | Write-Host
        throw "GDB $Name exited with $($proc.ExitCode)"
    }
    Get-Content -LiteralPath $out
}
Push-Location $PSScriptRoot
try {
    $verify = @(Invoke-GdbStep 'load-verify' 180000)
    $verify | Write-Output
    $sections = @($verify | Where-Object { $_ -match '^Section ' })
    if ($sections.Count -ne 5 -or @($sections | Where-Object { $_ -notmatch ': matched\.$' }).Count -ne 0) {
        throw 'ELF readback failed; execution was not started.'
    }
    $run = @(Invoke-GdbStep 'run-static' 60000)
    $run | Write-Output
    $text = $run -join "`n"
    if ($text -notmatch '(?m)^CNN_RESULT 1195655729 9 0 3 3\r?$') {
        if ($text -notmatch '(?m)^CNN_RESULT 1195655729 (9|255) [0-9]+ 3 [0-3]\r?$') {
            throw 'No completed three-vector result was received.'
        }
        Write-Warning 'Three vectors completed but strict comparison failed. Inspect CNN_RESULT.'
        exit 2
    }
    Write-Output 'PASS: all three INT8 vectors exactly match the documented reference backend.'
} finally { Pop-Location }
