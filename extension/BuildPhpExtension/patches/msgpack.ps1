# Check if PHP version is 8.6 or higher
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

# Apply PHP 8.6+ compatibility patch
if (($major -eq 8 -and $minor -ge 6) -or $major -gt 8) {
    Write-Host "Applying PHP 8.6+ compatibility patch for msgpack..."

    # Replace zval_dtor with zval_ptr_dtor_nogc in all .c files
    Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $changed = $false
        if ($content -match 'zval_dtor\(') {
            $content = $content -replace 'zval_dtor\(', 'zval_ptr_dtor_nogc('
            $changed = $true
        }
        # PHP 8.6: PG(unserialize_callback_func) changed from char* to zend_string*
        # (main/php_globals.h). msgpack still indexes it as a C string, which fails
        # with C2088 on msvc. Upstream msgpack has not adapted as of v3.0.1/master.
        if ($content -match 'PG\(unserialize_callback_func\)\[') {
            $content = $content -replace 'PG\(unserialize_callback_func\)\[', 'ZSTR_VAL(PG(unserialize_callback_func))['
            $changed = $true
        }
        if ($content -match 'ZVAL_STRING\(\s*&\w+\s*,\s*PG\(unserialize_callback_func\)\s*\)') {
            $content = $content -replace 'ZVAL_STRING\(\s*(&\w+)\s*,\s*PG\(unserialize_callback_func\)\s*\)', 'ZVAL_STR_COPY($1, PG(unserialize_callback_func))'
            $changed = $true
        }
        if ($changed) {
            Set-Content $_.FullName -Value $content -NoNewline
            Write-Host "Patched $($_.Name) for PHP 8.6"
        }
    }
}
