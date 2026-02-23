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

    $patchFile = "$PSScriptRoot\php8.5\phalcon.diff"
    if (Test-Path $patchFile) {
        Write-Host "Applying phalcon.diff..."
        git apply --ignore-whitespace --reject $patchFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: git apply failed, applying text replacements as fallback..."

            # Fallback: manual replacements
            $zepC = "build\phalcon\phalcon.zep.c"
            if (Test-Path $zepC) {
                $content = Get-Content $zepC -Raw
                # Fix php_smart_string.h -> zend_smart_string.h
                $content = $content -replace '#include\s+<ext/standard/php_smart_string\.h>', '#include <zend_smart_string.h>'
                # Fix zend_exception_get_default() -> zend_ce_exception
                $content = $content -replace 'zend_exception_get_default\(\)', 'zend_ce_exception'
                Set-Content $zepC -Value $content -NoNewline
                Write-Host "Patched $zepC via text replacement fallback"
            }
        } else {
            Write-Host "phalcon.diff applied successfully"
        }
    }
}
