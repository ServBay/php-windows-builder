(Get-Content config.w32) | ForEach-Object { $_ -replace '/sdl', '' } | Set-Content config.w32

$phpVersion = $env:PHP_VERSION_FOR_PATCHES

if ($phpVersion -eq "master") {
    $major = 8
    $minor = 6
} elseif ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
} else {
    exit 0
}

# PHP 8.6 removed INI_STR / INI_INT / INI_FLT / INI_BOOL / EMPTY_SWITCH_DEFAULT_CASE
# Inject backward-compatible #ifndef stubs into init.cpp (sqlsrv main entry, uses INI_BOOL/INI_INT).
if ($major -eq 8 -and $minor -eq 6) {
    Write-Host "Applying PHP 8.6 compatibility stubs for sqlsrv..."

    if (Test-Path "init.cpp") {
        $content = Get-Content init.cpp -Raw
        if ($content -notmatch '#ifndef\s+INI_STR') {
            $stub = @"
#ifndef INI_STR
# define INI_STR(name) zend_ini_string((name), (size_t)strlen(name), 0)
#endif
#ifndef INI_INT
# define INI_INT(name) zend_ini_long((name), (size_t)strlen(name), 0)
#endif
#ifndef INI_FLT
# define INI_FLT(name) zend_ini_double((name), (size_t)strlen(name), 0)
#endif
#ifndef INI_BOOL
# define INI_BOOL(name) zend_ini_parse_bool(zend_ini_str((name), (size_t)strlen(name), 0))
#endif
#ifndef EMPTY_SWITCH_DEFAULT_CASE
# define EMPTY_SWITCH_DEFAULT_CASE() default: ZEND_UNREACHABLE();
#endif
"@
            # Inject after the first include of php.h or zend.h (sqlsrv pulls those in via core_sqlsrv.h)
            if ($content -match '#include\s+"php\.h"') {
                $content = $content -replace '(#include\s+"php\.h"\s*\r?\n)', "`$1$stub`r`n"
            } elseif ($content -match '#include\s+"core_sqlsrv\.h"') {
                $content = $content -replace '(#include\s+"core_sqlsrv\.h"\s*\r?\n)', "`$1$stub`r`n"
            } else {
                # Fallback: prepend
                $content = "$stub`r`n" + $content
            }
            Set-Content init.cpp -Value $content -NoNewline
            Write-Host "✓ Injected INI_STR/INI_INT/INI_BOOL stubs into init.cpp"
        }
    }

    # PHP 8.6 changed php_stream_wrapper_log_error's signature (context inserted before
    # options; severity/terminating/code added after). sqlsrv's lone legacy 3-arg call
    # in shared/core_stream.cpp then fails with C2660. Inject a same-name macro shim
    # (a macro is not re-expanded within its own expansion, so the inner call hits the
    # real 7-arg function) filling the new params with warning/None defaults.
    $csFile = Get-ChildItem -Recurse -Filter "core_stream.cpp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csFile) {
        $cs = Get-Content $csFile.FullName -Raw
        if ($cs -notmatch 'log_error compat shim') {
            $shim = @"
/* php_stream_wrapper_log_error compat shim: PHP 8.6 changed the signature */
#if defined(PHP_VERSION_ID) && PHP_VERSION_ID >= 80600
#define php_stream_wrapper_log_error(wrapper, options, ...) \
    php_stream_wrapper_log_error((wrapper), NULL, (options), E_WARNING, true, ZEND_ENUM_StreamErrorCode_None, __VA_ARGS__)
#endif
"@
            $cs = $cs -replace '(#include\s+"core_sqlsrv\.h"\s*\r?\n)', "`$1$shim`r`n"
            Set-Content $csFile.FullName -Value $cs -NoNewline
            Write-Host "✓ Injected php_stream_wrapper_log_error shim into $($csFile.Name)"
        }
    }
}
