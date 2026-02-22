(Get-Content src\memcache_pool.h) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_pool.h
(Get-Content src\memcache_binary_protocol.c) | ForEach-Object { $_ -replace 'win32/php_stdint.h', 'stdint.h' } | Set-Content src\memcache_binary_protocol.c

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
    Write-Host "Applying PHP 8.5+ compatibility patch for memcache..."

    # Fix smart_string headers (manual replacement for cross-platform compatibility)
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

    # PHP 8.6: Apply additional patch file and text replacements
    if ($minor -eq 6) {
        Write-Host "Applying PHP 8.6 additional patches..."

        $patch86File = "$PSScriptRoot\php8.6\memcache.patch"
        if (Test-Path $patch86File) {
            Write-Host "Applying PHP 8.6 patch..."
            git apply --ignore-whitespace --reject $patch86File
            if ($LASTEXITCODE -ne 0) {
                Write-Host "WARNING: git apply failed, applying text replacements as fallback..."
            } else {
                Write-Host "✓ PHP 8.6 patch applied"
            }
        }

        # Add WRONG_PARAM_COUNT compatibility macro to php_memcache.h
        if (Test-Path "src\php_memcache.h") {
            $content = Get-Content src\php_memcache.h -Raw
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
                $content = $content -replace '(#ifndef\s+PHP_MEMCACHE_H\s*\r?\n#define\s+PHP_MEMCACHE_H)', "`$1`n$compatMacro"
                Set-Content src\php_memcache.h -Value $content -NoNewline
                Write-Host "✓ Added WRONG_PARAM_COUNT compatibility macro to php_memcache.h"
            }
        }

        # Expand PS_FUNCS macro in php_memcache.h (PHP 8.6 has a semicolon issue)
        if (Test-Path "src\php_memcache.h") {
            $content = Get-Content src\php_memcache.h -Raw
            $content = $content -replace 'PS_FUNCS\(memcache\);', 'PS_OPEN_FUNC(memcache); PS_CLOSE_FUNC(memcache); PS_READ_FUNC(memcache); PS_WRITE_FUNC(memcache); PS_DESTROY_FUNC(memcache); PS_GC_FUNC(memcache); PS_CREATE_SID_FUNC(memcache); PS_VALIDATE_SID_FUNC(memcache);'
            Set-Content src\php_memcache.h -Value $content -NoNewline
            Write-Host "✓ Expanded PS_FUNCS macro in php_memcache.h"
        }

        # Fix save_path type in memcache_session.c (const char* -> zend_string*)
        if (Test-Path "src\memcache_session.c") {
            $content = Get-Content src\memcache_session.c -Raw
            $content = $content -replace 'path = save_path;', 'path = ZSTR_VAL(save_path);'

            # PHP 8.6: PS_MOD now references ps_create_sid and ps_validate_sid
            # memcache uses PS_MOD (not PS_MOD_SID) but PHP 8.6 merged them
            # Add stub implementations if not present
            if ($content -notmatch 'PS_CREATE_SID_FUNC\(memcache\)') {
                $stubs = @"

/* PHP 8.6 compatibility: PS_MOD now requires create_sid and validate_sid */
#if PHP_VERSION_ID >= 80600
PS_CREATE_SID_FUNC(memcache)
{
	return php_session_create_id(NULL);
}

PS_VALIDATE_SID_FUNC(memcache)
{
	return SUCCESS;
}
#endif

"@
                # Add stubs before the ps_module definition (PS_MOD line)
                if ($content -match 'ps_module\s+ps_mod_memcache') {
                    $content = $content -replace '(ps_module\s+ps_mod_memcache)', "$stubs`$1"
                } else {
                    # Fallback: append at end of file
                    $content = $content + $stubs
                }
                Write-Host "✓ Added PS_CREATE_SID_FUNC/PS_VALIDATE_SID_FUNC stubs"
            }

            Set-Content src\memcache_session.c -Value $content -NoNewline
            Write-Host "✓ Fixed save_path type in memcache_session.c"
        }
    }
}
