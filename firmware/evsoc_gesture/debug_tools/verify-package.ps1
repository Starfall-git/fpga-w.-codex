$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
foreach ($entry in $manifest.files.PSObject.Properties) {
    $file = Join-Path $PSScriptRoot $entry.Name
    if (!(Test-Path -LiteralPath $file)) { throw "Missing file: $($entry.Name)" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value.sha256) {
        throw "SHA256 mismatch: $($entry.Name)"
    }
}
Write-Output "PASS: all $($manifest.files.PSObject.Properties.Name.Count) payload hashes match. No board operation performed."
