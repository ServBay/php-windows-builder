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
# Inject backward-compatible #ifndef stubs into apc_persist.c
if ($major -eq 8 -and $minor -eq 6) {
    Write-Host "Applying PHP 8.6 compatibility patch for apcu..."

    $patch86File = "$PSScriptRoot\php8.6\apcu.patch"
    if (Test-Path $patch86File) {
        Write-Host "Applying PHP 8.6 patch..."
        git apply --ignore-whitespace --reject $patch86File
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: git apply failed, falling back to direct injection..."
        } else {
            Write-Host "✓ PHP 8.6 patch applied"
            exit 0
        }
    }

    # Fallback: inject the stubs directly if patch did not apply
    if (Test-Path "apc_persist.c") {
        $content = Get-Content apc_persist.c -Raw
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
            $content = $content -replace '(#include\s+"apc\.h"\s*\r?\n)', "`$1$stub`r`n"
            Set-Content apc_persist.c -Value $content -NoNewline
            Write-Host "✓ Injected INI_STR/EMPTY_SWITCH_DEFAULT_CASE stubs into apc_persist.c"
        }
    }
}
