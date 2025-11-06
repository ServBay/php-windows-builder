# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for mongodb..."

        # Fix IS_INTERNED macro
        if (Test-Path "src\contrib\php_array_api.h") {
            (Get-Content src\contrib\php_array_api.h) | ForEach-Object {
                $_ -replace '\*pfree\s*=\s*!\s*IS_INTERNED\(Z_STR\(c\)\);', '*pfree = ! ZSTR_IS_INTERNED(Z_STR(c));'
            } | Set-Content src\contrib\php_array_api.h
            Write-Host "✓ Patched src\contrib\php_array_api.h"
        }
    }
}
