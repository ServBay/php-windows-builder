(Get-Content src\memcache_pool.h) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_pool.h
(Get-Content src\memcache_binary_protocol.c) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_binary_protocol.c

# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for memcache..."

        # Fix smart_string headers
        if (Test-Path "src\memcache_pool.h") {
            (Get-Content src\memcache_pool.h) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string_public\.h"', '#include "zend_smart_str.h"'
            } | Set-Content src\memcache_pool.h
            Write-Host "✓ Patched src\memcache_pool.h"
        }

        if (Test-Path "src\memcache_pool.c") {
            (Get-Content src\memcache_pool.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "zend_smart_string.h"'
            } | Set-Content src\memcache_pool.c
            Write-Host "✓ Patched src\memcache_pool.c"
        }

        if (Test-Path "src\memcache_ascii_protocol.c") {
            (Get-Content src\memcache_ascii_protocol.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "zend_smart_string.h"'
            } | Set-Content src\memcache_ascii_protocol.c
            Write-Host "✓ Patched src\memcache_ascii_protocol.c"
        }

        if (Test-Path "src\memcache_session.c") {
            (Get-Content src\memcache_session.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "zend_smart_string.h"'
            } | Set-Content src\memcache_session.c
            Write-Host "✓ Patched src\memcache_session.c"
        }

        if (Test-Path "src\memcache_binary_protocol.c") {
            (Get-Content src\memcache_binary_protocol.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "zend_smart_string.h"'
            } | Set-Content src\memcache_binary_protocol.c
            Write-Host "✓ Patched src\memcache_binary_protocol.c (smart_string)"
        }
    }
}
