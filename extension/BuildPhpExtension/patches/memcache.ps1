(Get-Content src\memcache_pool.h) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_pool.h
(Get-Content src\memcache_binary_protocol.c) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_binary_protocol.c

# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # PHP 8.5: Use manual replacement
    if ($major -eq 8 -and $minor -eq 5) {
        Write-Host "Applying PHP 8.5 compatibility patch for memcache..."

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

    # PHP 8.6: Use patch files
    if ($major -eq 8 -and $minor -eq 6) {
        Write-Host "Applying PHP 8.6 patches for memcache..."

        # First apply PHP 8.5 patch
        $patch85File = "$PSScriptRoot\php8.5\memcache.diff"
        if (Test-Path $patch85File) {
            Write-Host "Applying PHP 8.5 patch..."
            git apply --ignore-whitespace --reject $patch85File
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply PHP 8.5 patch for memcache"
            }
            Write-Host "✓ PHP 8.5 patch applied"
        }

        # Then apply PHP 8.6 patch
        $patch86File = "$PSScriptRoot\php8.6\memcache.patch"
        if (Test-Path $patch86File) {
            Write-Host "Applying PHP 8.6 patch..."
            git apply --ignore-whitespace --reject $patch86File
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply PHP 8.6 patch for memcache"
            }
            Write-Host "✓ PHP 8.6 patch applied"
        }
    }
}
