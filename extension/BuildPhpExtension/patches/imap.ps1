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

if ($major -eq 8 -and $minor -ge 6) {
    Write-Host "Applying PHP 8.6 compatibility patch for imap..."

    # PHP 8.6 removed INI_STR / INI_INT / INI_FLT / INI_BOOL / EMPTY_SWITCH_DEFAULT_CASE macros.
    # Inject backward-compatible #ifndef stubs into php_imap.c.
    $patch86File = "$PSScriptRoot\php8.6\imap.patch"
    $stubsApplied = $false
    if (Test-Path $patch86File) {
        Write-Host "Applying PHP 8.6 INI_STR/EMPTY_SWITCH_DEFAULT_CASE stubs patch..."
        git apply --ignore-whitespace --reject $patch86File
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ PHP 8.6 stubs patch applied"
            $stubsApplied = $true
        } else {
            Write-Host "WARNING: git apply failed for INI_STR stubs, falling back to direct injection..."
        }
    }
    if (-not $stubsApplied -and (Test-Path "php_imap.c")) {
        $imapContent = Get-Content php_imap.c -Raw
        if ($imapContent -notmatch '#ifndef\s+INI_STR') {
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
            $imapContent = $imapContent -replace '(#include\s+"php\.h"\s*\r?\n)', "`$1$stub`r`n"
            Set-Content php_imap.c -Value $imapContent -NoNewline
            Write-Host "✓ Injected INI_STR/EMPTY_SWITCH_DEFAULT_CASE stubs into php_imap.c"
        }
    }

    # PHP 8.6 changed TSendMail signature - removed mailCc, mailBcc, mailRPath parameters
    # Old: TSendMail(host, &err, &errmsg, headers, subject, to, message, cc, bcc, rpath)
    # New: TSendMail(host, &err, &errmsg, headers, subject, to, message)
    # The Cc, Bcc, and return-path are now handled via the headers parameter
    if (Test-Path "php_imap.c") {
        $content = Get-Content php_imap.c -Raw

        # Check if TSendMail is called with bufferCc (old 10-arg style)
        if ($content -match 'TSendMail[\s\S]*?bufferCc') {
            Write-Host "Fixing TSendMail call for PHP 8.6 (10 args -> 7 args)..."

            # Replace the TSendMail call line by line:
            # Find: ZSTR_VAL(message), bufferCc, bufferBcc, rpath ? ZSTR_VAL(rpath) : NULL)
            # Replace with: ZSTR_VAL(message))
            # Then wrap the if block with preprocessor conditionals

            # Step 1: Replace the 10-arg call with 7-arg call wrapped in #if
            # Match the entire if(TSendMail(...)) block using (?s) for dotall mode
            $pattern = '(?s)([ \t]*)(if\s*\(TSendMail\(INI_STR\("SMTP"\).*?ZSTR_VAL\(message\)),\s*bufferCc,\s*bufferBcc,\s*rpath\s*\?\s*ZSTR_VAL\(rpath\)\s*:\s*NULL\)(\s*!=\s*SUCCESS\)\s*\{)'
            $replacement = @'
$1/* PHP 8.6+: Merge Cc/Bcc into headers, TSendMail signature changed */
$1#if PHP_VERSION_ID >= 80600
$1if (bufferCc && *bufferCc) {
$1	size_t oldLen = strlen(bufferHeader);
$1	size_t ccLen = strlen(bufferCc);
$1	bufferHeader = erealloc(bufferHeader, oldLen + ccLen + 8);
$1	snprintf(bufferHeader + oldLen, ccLen + 8, "\r\nCc: %s", bufferCc);
$1}
$1if (bufferBcc && *bufferBcc) {
$1	size_t oldLen = strlen(bufferHeader);
$1	size_t bccLen = strlen(bufferBcc);
$1	bufferHeader = erealloc(bufferHeader, oldLen + bccLen + 9);
$1	snprintf(bufferHeader + oldLen, bccLen + 9, "\r\nBcc: %s", bufferBcc);
$1}
$1$2)$3
$1#else
$1$2, bufferCc, bufferBcc, rpath ? ZSTR_VAL(rpath) : NULL)$3
$1#endif
'@
            $newContent = [regex]::Replace($content, $pattern, $replacement)
            if ($newContent -ne $content) {
                Set-Content php_imap.c -Value $newContent -NoNewline
                Write-Host "✓ Fixed TSendMail call in php_imap.c"
            } else {
                Write-Host "WARNING: TSendMail regex replacement did not match, trying simple approach..."
                # Fallback: simple text replacement of the extra args
                $content = $content -replace '(ZSTR_VAL\(message\)),\s*bufferCc,\s*bufferBcc,\s*rpath\s*\?\s*ZSTR_VAL\(rpath\)\s*:\s*NULL\)', '$1)'
                Set-Content php_imap.c -Value $content -NoNewline
                Write-Host "✓ Fixed TSendMail call (simple mode - removed extra args)"
            }
        } else {
            Write-Host "TSendMail call pattern not found or already patched"
        }
    } else {
        Write-Host "php_imap.c not found, skipping"
    }
}
