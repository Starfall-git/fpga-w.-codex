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
    $run = @(Invoke-GdbStep 'run-live' 60000)
    $run | Write-Output
    if (($run -join "`n") -notmatch '(?m)^CNN_LIVE 1196185137 [4-8] 0 [0-9]+\r?$') {
        throw 'Live initialization failed. Inspect stage/error and camera capture status.'
    }
    Write-Output 'PASS: live firmware initialized; CPU is running. Enable inference/overlay in the host TinyML panel.'
} finally { Pop-Location }
