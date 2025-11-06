# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for xdebug..."

        # Fix smart_string.h header path in usefulstuff.c
        if (Test-Path "src\lib\usefulstuff.c") {
            (Get-Content src\lib\usefulstuff.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "Zend/zend_smart_string.h"'
            } | Set-Content src\lib\usefulstuff.c
            Write-Host "✓ Patched src\lib\usefulstuff.c"
        }

        # Fix php_setcookie parameter in set.c
        if (Test-Path "src\lib\set.c") {
            $content = Get-Content src\lib\set.c -Raw
            # Add false parameter before url_encode in php_setcookie call
            $content = $content -replace '(\s+cookie_samesite,\s*\r?\n\s+)(url_encode)', '$1false, $2'
            Set-Content src\lib\set.c -Value $content -NoNewline
            Write-Host "✓ Patched src\lib\set.c"
        }
    }
}
