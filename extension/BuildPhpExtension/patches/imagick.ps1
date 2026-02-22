# Check if PHP version is 8.1 or higher
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

if ($major -eq 8 -and $minor -in @(1,2,3,4,5,6)) {
    Write-Host "Applying PHP 8.1+ compatibility patch for imagick..."

    if (Test-Path "imagick.c") {
        $content = Get-Content imagick.c -Raw

        # Ensure zend_smart_str.h is included (provides smart_str functions)
        # imagick 3.8.1 has: #if PHP_VERSION_ID >= 70200 / #include "Zend/zend_smart_string.h"
        # We need to also include zend_smart_str.h for the smart_str type
        if ($content -match '#include "Zend/zend_smart_string\.h"' -and $content -notmatch '#include "zend_smart_str\.h"') {
            $content = $content -replace '#include "Zend/zend_smart_string\.h"', "#include `"Zend/zend_smart_string.h`"`n#include `"zend_smart_str.h`""
            Write-Host "✓ Added zend_smart_str.h include"
        }
        # Fallback: if the old pattern exists (imagick < 3.8.1)
        if ($content -notmatch '#include "zend_smart_str\.h"') {
            if ($content -match '#include "ext/standard/php_smart_string\.h"') {
                $content = $content -replace '#include "ext/standard/php_smart_string\.h"', "#include `"ext/standard/php_smart_string.h`"`n#include `"zend_smart_str.h`""
                Write-Host "✓ Added zend_smart_str.h include (fallback path)"
            }
        }

        # Fix php_strtolower -> zend_str_tolower (PHP 8.4+)
        if ($minor -ge 4) {
            $content = $content -replace 'php_strtolower\(', 'zend_str_tolower('
            Write-Host "✓ Replaced php_strtolower with zend_str_tolower"
        }

        Set-Content imagick.c -Value $content -NoNewline
        Write-Host "✓ Patched imagick.c"
    }
}
