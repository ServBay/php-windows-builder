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
    Write-Host "Applying PHP 8.5+ compatibility patch for phalcon..."

    # phalcon is downloaded from PECL as a tarball (no git repo),
    # and Get-Extension.ps1 flattens subdirectories so phalcon.zep.c is at root level.
    # Use direct text replacement instead of git apply.
    Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $modified = $false

        # Fix php_smart_string.h -> zend_smart_string.h
        if ($content -match '#include\s+[<"]ext/standard/php_smart_string\.h[>"]') {
            $content = $content -replace '#include\s+[<"]ext/standard/php_smart_string\.h[>"]', '#include <zend_smart_string.h>'
            $modified = $true
            Write-Host "  Replaced php_smart_string.h in $($_.Name)"
        }

        # Fix zend_exception_get_default() -> zend_ce_exception
        if ($content -match 'zend_exception_get_default\(\)') {
            $content = $content -replace 'zend_exception_get_default\(\)', 'zend_ce_exception'
            $modified = $true
            Write-Host "  Replaced zend_exception_get_default() in $($_.Name)"
        }

        if ($modified) {
            Set-Content $_.FullName -Value $content -NoNewline
        }
    }

    # Also check .h files for the smart_string include
    Get-ChildItem -Path . -Filter "*.h" -Recurse | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match '#include\s+[<"]ext/standard/php_smart_string\.h[>"]') {
            $content = $content -replace '#include\s+[<"]ext/standard/php_smart_string\.h[>"]', '#include <zend_smart_string.h>'
            Set-Content $_.FullName -Value $content -NoNewline
            Write-Host "  Replaced php_smart_string.h in $($_.Name)"
        }
    }

    Write-Host "PHP 8.5+ patches applied for phalcon"
}

# Apply PHP 8.6+ zval_dtor fix
if (($major -eq 8 -and $minor -ge 6) -or $major -gt 8) {
    Write-Host "Applying PHP 8.6+ zval_dtor patch for phalcon..."

    Get-ChildItem -Path . -Filter "*.c" -Recurse | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match 'zval_dtor\(') {
            $content = $content -replace 'zval_dtor\(', 'zval_ptr_dtor_nogc('
            Set-Content $_.FullName -Value $content -NoNewline
            Write-Host "  Replaced zval_dtor in $($_.Name)"
        }
    }

    Write-Host "PHP 8.6+ zval_dtor patches applied for phalcon"
}
