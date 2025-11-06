(Get-Content php_memcached_private.h) | ForEach-Object { $_ -replace '"php_stdint.h"', '<stdint.h>' } | Set-Content php_memcached_private.h

# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for memcached..."

        # Fix smart_string header
        if (Test-Path "php_memcached_private.h") {
            (Get-Content php_memcached_private.h) | ForEach-Object {
                $_ -replace '#include\s+<ext/standard/php_smart_string\.h>', '#include <zend_smart_string.h>'
            } | Set-Content php_memcached_private.h
            Write-Host "✓ Patched php_memcached_private.h"
        }

        # Fix zend_exception_get_default()
        if (Test-Path "php_memcached.c") {
            (Get-Content php_memcached.c) | ForEach-Object {
                $_ -replace 'return\s+zend_exception_get_default\(\);', 'return zend_ce_exception;'
            } | Set-Content php_memcached.c
            Write-Host "✓ Patched php_memcached.c"
        }
    }
}
