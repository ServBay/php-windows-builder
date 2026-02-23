# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES

# Treat "master" as PHP 8.6
if ($phpVersion -eq "master") {
    $major = 8
    $minor = 6
} elseif ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
} else {
    # Cannot parse version, skip patching
    exit 0
}

# Apply PHP 8.5+ compatibility patch
if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
    Write-Host "Applying PHP 8.5+ compatibility patch for igbinary..."

    # Fix smart_string.h header path in php_igbinary.h
    if (Test-Path "src\php7\php_igbinary.h") {
        (Get-Content src\php7\php_igbinary.h) | ForEach-Object {
            $_ -replace '#include\s+[''"]ext/standard/php_smart_string\.h[''"]', '#include <zend_smart_string.h>'
        } | Set-Content src\php7\php_igbinary.h
        Write-Host "Patched src\php7\php_igbinary.h"
    }

    # PHP 8.6+: Replace zval_dtor with zval_ptr_dtor_nogc
    if ($minor -ge 6) {
        Write-Host "Applying PHP 8.6 additional patches for igbinary..."

        Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            if ($content -match 'zval_dtor\(') {
                $content = $content -replace 'zval_dtor\(', 'zval_ptr_dtor_nogc('
                Set-Content $_.FullName -Value $content -NoNewline
                Write-Host "Replaced zval_dtor in $($_.Name)"
            }
        }
    }
}
