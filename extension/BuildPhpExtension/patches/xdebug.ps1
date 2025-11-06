# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for xdebug..."

        # Fix version check in config.w32 to support PHP 8.5+
        if (Test-Path "config.w32") {
            (Get-Content config.w32) | ForEach-Object {
                $_ -replace '(PHP_VERSION_ID\s+<\s+)80500', '${1}80600'
            } | Set-Content config.w32
            Write-Host "✓ Patched config.w32 version check"
        }

        # Fix smart_string.h header path in var.c
        if (Test-Path "src\lib\var.c") {
            (Get-Content src\lib\var.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "Zend/zend_smart_string.h"'
            } | Set-Content src\lib\var.c
            Write-Host "✓ Patched src\lib\var.c"
        }

        # Fix smart_string.h header path in stack.c
        if (Test-Path "src\develop\stack.c") {
            (Get-Content src\develop\stack.c) | ForEach-Object {
                $_ -replace '#include\s+"ext/standard/php_smart_string\.h"', '#include "Zend/zend_smart_string.h"'
            } | Set-Content src\develop\stack.c
            Write-Host "✓ Patched src\develop\stack.c"
        }

        # Fix php_setcookie parameter in compat.c
        if (Test-Path "src\lib\compat.c") {
            $content = Get-Content src\lib\compat.c -Raw
            # Add false parameter before url_encode in php_setcookie call
            $content = $content -replace '(php_setcookie\([^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*)(url_encode)', '${1}false, $2'
            Set-Content src\lib\compat.c -Value $content -NoNewline
            Write-Host "✓ Patched src\lib\compat.c"
        }
    }
}
