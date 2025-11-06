# Check if PHP version is 8.5 or higher
$phpVersion = $env:PHP_VERSION_FOR_PATCHES
if ($phpVersion -match '^(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]

    # Apply PHP 8.5+ compatibility patch
    if (($major -eq 8 -and $minor -ge 5) -or $major -gt 8) {
        Write-Host "Applying PHP 8.5+ compatibility patch for redis..."

        # Fix smart_string.h header path
        if (Test-Path "redis_array_impl.c") {
            (Get-Content redis_array_impl.c) | ForEach-Object {
                $_ -replace '#include\s+<ext/standard/php_smart_string\.h>', '#include <zend_smart_string.h>'
            } | Set-Content redis_array_impl.c
            Write-Host "✓ Patched redis_array_impl.c"
        }
    }
}
