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
    Write-Host "Applying PHP 8.5+ compatibility patch for xdebug..."

    # Fix version check in config.w32 to support PHP 8.5+
    if (Test-Path "config.w32") {
        (Get-Content config.w32) | ForEach-Object {
            if ($minor -eq 5) {
                # PHP 8.5: Change version check from >= 80500 to >= 80600
                $_ = $_ -replace '(XDEBUG_PHP_VERSION\s+>=\s+)80500', '${1}80600'
                $_ = $_ -replace '(<\s+)8\.5\.0', '${1}8.6.0'
            } elseif ($minor -ge 6) {
                # PHP 8.6+: Change version check to >= 80700
                # xdebug 3.5.0 uses 80600, older versions use 80500
                $_ = $_ -replace '(XDEBUG_PHP_VERSION\s+>=\s+)8050\d', '${1}80700'
                $_ = $_ -replace '(XDEBUG_PHP_VERSION\s+>=\s+)8060\d', '${1}80700'
                $_ = $_ -replace '(<\s+)8\.[56]\.0', '${1}8.7.0'
            }
            $_
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

    # PHP 8.6: Apply additional patches
    if ($minor -ge 6) {
        Write-Host "Applying PHP 8.6 additional patches for xdebug..."

        # Replace zval_dtor with zval_ptr_dtor_nogc in all .c files
        Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            if ($content -match 'zval_dtor\(') {
                $content = $content -replace 'zval_dtor\(', 'zval_ptr_dtor_nogc('
                Set-Content $_.FullName -Value $content -NoNewline
                Write-Host "✓ Replaced zval_dtor in $($_.Name)"
            }
        }

        # Replace WRONG_PARAM_COUNT with equivalent code
        if (Test-Path "src\develop\php_functions.c") {
            $content = Get-Content src\develop\php_functions.c -Raw
            $content = $content -replace 'WRONG_PARAM_COUNT;', '{ zend_wrong_param_count(); return; }'
            Set-Content src\develop\php_functions.c -Value $content -NoNewline
            Write-Host "✓ Replaced WRONG_PARAM_COUNT in php_functions.c"
        }

        # Fix ZSTR_INIT_LITERAL usage in profiler.c
        if (Test-Path "src\profiler\profiler.c") {
            $content = Get-Content src\profiler\profiler.c -Raw
            $content = $content -replace 'ZSTR_INIT_LITERAL\(tmp_name,\s*false\)', 'zend_string_init(tmp_name, strlen(tmp_name), false)'
            Set-Content src\profiler\profiler.c -Value $content -NoNewline
            Write-Host "✓ Fixed ZSTR_INIT_LITERAL in profiler.c"
        }
    }
}
