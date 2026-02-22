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

    # PHP 8.6: Apply additional patch file and text replacements
    if ($minor -eq 6) {
        Write-Host "Applying PHP 8.6 additional patches..."

        $patch86File = "$PSScriptRoot\php8.6\phpredis.patch"
        if (Test-Path $patch86File) {
            Write-Host "Applying PHP 8.6 patch..."
            git apply --ignore-whitespace --reject $patch86File
            if ($LASTEXITCODE -ne 0) {
                Write-Host "WARNING: git apply failed, applying text replacements as fallback..."
            } else {
                Write-Host "✓ PHP 8.6 patch applied"
            }
        }

        # Replace zval_dtor with zval_ptr_dtor_nogc in all .c files
        Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
            $c = Get-Content $_.FullName -Raw
            $changed = $false
            if ($c -match 'zval_dtor\(') {
                $c = $c -replace 'zval_dtor\(', 'zval_ptr_dtor_nogc('
                $changed = $true
            }
            if ($c -match '(?<!\w)zval_is_true\(') {
                $c = $c -replace '(?<!\w)zval_is_true\(', 'zend_is_true('
                $changed = $true
            }
            if ($changed) {
                Set-Content $_.FullName -Value $c -NoNewline
                Write-Host "✓ Replaced zval_dtor/zval_is_true in $($_.Name)"
            }
        }

        # Add WRONG_PARAM_COUNT compatibility macro to common.h
        if (Test-Path "common.h") {
            $content = Get-Content common.h -Raw
            if ($content -notmatch 'WRONG_PARAM_COUNT') {
                $compatMacro = @"
/* PHP 8.6 compatibility: WRONG_PARAM_COUNT macros removed */
#if PHP_VERSION_ID >= 80600
#ifndef WRONG_PARAM_COUNT
#define WRONG_PARAM_COUNT { zend_wrong_param_count(); return; }
#define ZEND_WRONG_PARAM_COUNT() { zend_wrong_param_count(); return; }
#endif
#endif

"@
                $content = $content -replace '(#include\s+"php\.h"\s*\r?\n#include\s+"php_ini\.h"\s*\r?\n)', "`$1`n$compatMacro"
                Set-Content common.h -Value $content -NoNewline
                Write-Host "✓ Added WRONG_PARAM_COUNT compatibility macro to common.h"
            }
        }

        # Fix save_path type in redis_session.c (const char* -> zend_string*)
        if (Test-Path "redis_session.c") {
            $content = Get-Content redis_session.c -Raw
            if ($content -match 'PS_OPEN_FUNC\(redis\)' -and $content -notmatch '_save_path = ZSTR_VAL\(save_path\)') {
                # Add local variable after the opening brace of PS_OPEN_FUNC
                $content = $content -replace '(PS_OPEN_FUNC\(redis\)\s*\{[^\n]*\n(\s*(?:php_url|zval|int|redis_pool)[^\n]*\n)*)', "`$1    const char *_save_path = ZSTR_VAL(save_path);`n"
                # Replace all save_path references with _save_path (but not _save_path itself)
                $content = $content -replace '(?<![_\w])save_path(?!\s*\)|\s*;[^;]*ZSTR_VAL)', '_save_path'
                Set-Content redis_session.c -Value $content -NoNewline
                Write-Host "✓ Fixed save_path type in redis_session.c"
            }
        }

        # Fix save_path in redis_cluster.c
        if (Test-Path "redis_cluster.c") {
            $content = Get-Content redis_cluster.c -Raw
            $content = $content -replace 'estrdup\(save_path\)', 'estrdup(ZSTR_VAL(save_path))'
            Set-Content redis_cluster.c -Value $content -NoNewline
            Write-Host "✓ Fixed save_path in redis_cluster.c"
        }
    }
}
