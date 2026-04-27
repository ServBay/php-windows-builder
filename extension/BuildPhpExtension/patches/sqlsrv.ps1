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
}
