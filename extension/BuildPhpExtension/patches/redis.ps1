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

if ($major -eq 8 -and ($minor -eq 5 -or $minor -eq 6)) {
    Write-Host "Applying PHP 8.5+ compatibility patch for redis..."

    # Fix smart_string.h header path in common.h (manual replacement for cross-platform compatibility)
    if (Test-Path "common.h") {
        (Get-Content common.h) | ForEach-Object {
            $_ -replace '#include\s+<ext/standard/php_smart_string\.h>', '#include <zend_smart_string.h>'
        } | Set-Content common.h
        Write-Host "✓ Patched common.h"
    }

    # PHP 8.6: Apply additional patch file
    if ($minor -eq 6) {
        Write-Host "Applying PHP 8.6 additional patches..."

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
