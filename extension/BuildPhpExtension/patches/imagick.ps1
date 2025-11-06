# Check if PHP version is 8.1 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.1+ compatibility patch (for PHP 8.5+)
    if (($major -eq 8 -and $minor -ge 1) -or $major -gt 8) {
        Write-Host "Applying PHP 8.1+ compatibility patch for imagick..."

        # Fix smart_string.h header includes
        if (Test-Path "imagick.c") {
            $content = Get-Content imagick.c -Raw

            # Replace the smart string includes section
            $oldPattern = '#if PHP_VERSION_ID >= 70000\s*\r?\n#include "ext/standard/php_smart_string\.h"\s*\r?\n#define smart_str smart_string'
            $newPattern = @'
#if PHP_VERSION_ID >= 80100
#include "zend_smart_str.h"
#define smart_str_0(x) smart_str_0_ex((x))
#define smart_str_appendl(dest, src, len) smart_str_appendl_ex((dest), (src), (len), 0)
#elif PHP_VERSION_ID >= 70000
#include "ext/standard/php_smart_string.h"
#define smart_str smart_string
'@

            if ($content -match $oldPattern) {
                $content = $content -replace $oldPattern, $newPattern
                Set-Content imagick.c -Value $content -NoNewline
                Write-Host "✓ Patched imagick.c"
            } else {
                Write-Host "⚠ Pattern not found in imagick.c, may already be patched"
            }
        }
    }
}
