(Get-Content config.w32) | ForEach-Object { $_ -replace '/sdl', '' } | Set-Content config.w32

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

if ($major -eq 8 -and $minor -ge 5 -or $major -gt 8) {
    Write-Host "Applying PHP 8.5+ compatibility patch for pdo_sqlsrv..."

    # Fix 1: query_stmt_zval → query_stmt_obj in php_pdo_sqlsrv_int.h
    # PHP 8.5 replaced `zval query_stmt_zval` with `zend_object *query_stmt_obj` in pdo_dbh_t
    if (Test-Path "php_pdo_sqlsrv_int.h") {
        $content = Get-Content php_pdo_sqlsrv_int.h -Raw
        $content = $content -replace 'zval_ptr_dtor\s*\(\s*&dbh->query_stmt_zval\s*\)', 'OBJ_RELEASE(dbh->query_stmt_obj)'
        Set-Content php_pdo_sqlsrv_int.h -Value $content -NoNewline
        Write-Host "✓ Fixed query_stmt_zval → query_stmt_obj in php_pdo_sqlsrv_int.h"
    }

    # Fix 2: pdo_error_mode cast in pdo_dbh.cpp
    # PHP 8.5 changed `enum pdo_error_mode error_mode` to `uint8_t error_mode` in pdo_dbh_t
    # MSVC C++ does not allow implicit conversion from uint8_t to enum
    if (Test-Path "pdo_dbh.cpp") {
        $content = Get-Content pdo_dbh.cpp -Raw
        $content = $content -replace 'pdo_error_mode\s+prev_err_mode\s*=\s*dbh->error_mode', 'pdo_error_mode prev_err_mode = static_cast<pdo_error_mode>(dbh->error_mode)'
        Set-Content pdo_dbh.cpp -Value $content -NoNewline
        Write-Host "✓ Fixed pdo_error_mode cast in pdo_dbh.cpp"
    }

    # Fix 3: php_stream_wrapper_log_error signature (PHP 8.6). shared/core_stream.cpp's
    # legacy 3-arg call fails with C2660. A same-name macro shim (not re-expanded within
    # its own expansion, so the inner call hits the real 7-arg function) fills the new
    # context/severity/terminating/code params. Guarded by PHP_VERSION_ID so <8.6 is unaffected.
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
