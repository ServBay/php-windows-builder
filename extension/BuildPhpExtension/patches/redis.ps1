# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # PHP 8.5: Use manual replacement
    if ($major -eq 8 -and $minor -eq 5) {
        Write-Host "Applying PHP 8.5 compatibility patch for redis..."

        # Fix smart_string.h header path in common.h
        if (Test-Path "common.h") {
            (Get-Content common.h) | ForEach-Object {
                $_ -replace '#include\s+<ext/standard/php_smart_string\.h>', '#include <zend_smart_string.h>'
            } | Set-Content common.h
            Write-Host "✓ Patched common.h"
        }
    }

    # PHP 8.6: Use patch files
    if ($major -eq 8 -and $minor -eq 6) {
        Write-Host "Applying PHP 8.6 patches for redis..."

        # First apply PHP 8.5 patch
        $patch85File = "$PSScriptRoot\php8.5\phpredis-6.2.0-php8.5.patch"
        if (Test-Path $patch85File) {
            Write-Host "Applying PHP 8.5 patch..."
            git apply --ignore-whitespace --reject $patch85File
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply PHP 8.5 patch for redis"
            }
            Write-Host "✓ PHP 8.5 patch applied"
        }

        # Then apply PHP 8.6 patch
        $patch86File = "$PSScriptRoot\php8.6\phpredis.patch"
        if (Test-Path $patch86File) {
            Write-Host "Applying PHP 8.6 patch..."
            git apply --ignore-whitespace --reject $patch86File
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply PHP 8.6 patch for redis"
            }
            Write-Host "✓ PHP 8.6 patch applied"
        }
    }
}
