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

    # Manual replacement for cross-platform compatibility
    if (Test-Path "imagick.c") {
        $content = Get-Content imagick.c -Raw

        # 1. Fix header includes (lines 24-30)
        $content = $content -replace '(?s)#if PHP_VERSION_ID >= 70000\s*\r?\n#include "ext/standard/php_smart_string\.h"', @'
#if PHP_VERSION_ID >= 80100
#include "zend_smart_str.h"
#elif PHP_VERSION_ID >= 70000
#include "ext/standard/php_smart_string.h"
'@

        # 2. Fix smart_string declaration (line 1128)
        $content = $content -replace '#if PHP_VERSION_ID >= 70000\s*\r?\n\s*smart_string formats = \{0\};', @'
#if PHP_VERSION_ID >= 70000 && PHP_VERSION_ID < 80100
	smart_string formats = {0};
'@

        # 3. Fix smart_string_appends usage (lines 1166-1171)
        $content = $content -replace '(?s)(for \(i = 0; i < num_formats; i\+\+\) \{\s*#if PHP_VERSION_ID >= 70000)\s*\r?\n(\s*if \(i != 0\) \{)', '$1 && PHP_VERSION_ID < 80100$2'

        # 4. Fix smart_string_0 and free (lines 1178-1180)
        $content = $content -replace '(?s)(IMAGICK_FREE_MAGICK_MEMORY\(supported_formats\[i\]\);\s*\}\s*\r?\n\s*#if PHP_VERSION_ID >= 70000)\s*\r?\n(\s*smart_string_0)', '$1 && PHP_VERSION_ID < 80100$2'

        # 5. Add PHP 8.1+ handling for formats output
        $content = $content -replace '(?s)(smart_str_0\(&formats\);\s*\r?\n)(\s*php_info_print_table_row)', @'
$1#if PHP_VERSION_ID >= 80100
		php_info_print_table_row(2, "ImageMagick supported formats", ZSTR_VAL(formats.s));
#else
		$2
'@
        $content = $content -replace '(php_info_print_table_row\(2, "ImageMagick supported formats", formats\.c\);\s*\r?\n)(\s*smart_str_free)', @'
$1#endif
		$2
'@

        # 6. Fix php_strtolower -> zend_str_tolower (PHP 8.4+)
        if ($minor -ge 4) {
            $content = $content -replace 'php_strtolower\(', 'zend_str_tolower('
            Write-Host "✓ Replaced php_strtolower with zend_str_tolower"
        }

        Set-Content imagick.c -Value $content -NoNewline
        Write-Host "✓ Patched imagick.c"
    }
}
