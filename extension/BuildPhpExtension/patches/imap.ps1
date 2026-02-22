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

    # PHP 8.6 changed TSendMail signature - removed mailCc, mailBcc, mailRPath parameters
    # Old: TSendMail(host, &err, &errmsg, headers, subject, to, message, cc, bcc, rpath)
    # New: TSendMail(host, &err, &errmsg, headers, subject, to, message)
    # The Cc, Bcc, and return-path are now handled via the headers parameter
    if (Test-Path "php_imap.c") {
        $content = Get-Content php_imap.c -Raw

        # Check if TSendMail is called with 10 arguments (old style)
        if ($content -match 'TSendMail\([^)]+bufferCc') {
            Write-Host "Fixing TSendMail call for PHP 8.6 (10 args -> 7 args)..."

            # The imap extension builds Cc/Bcc/RPath into separate buffers and passes them.
            # In PHP 8.6, TSendMail handles these from the headers string directly.
            # We need to:
            # 1. Merge Cc and Bcc into the headers buffer before calling TSendMail
            # 2. Remove the extra arguments from the TSendMail call

            # Add a preprocessor block that adapts the call based on PHP version
            # Find the TSendMail call and wrap it
            $content = $content -replace `
                '(if\s*\(TSendMail\(INI_STR\("SMTP"\),\s*&tsm_err,\s*&tsm_errmsg,\s*bufferHeader,\s*ZSTR_VAL\(subject\),\s*\r?\n\s*bufferTo,\s*ZSTR_VAL\(message\),\s*bufferCc,\s*bufferBcc,\s*rpath\s*\?\s*ZSTR_VAL\(rpath\)\s*:\s*NULL\)\s*!=\s*SUCCESS\))', `
                @'
/* PHP 8.6+: Merge Cc/Bcc/RPath into headers, TSendMail has 7 params */
#if PHP_VERSION_ID >= 80600
            /* Append Cc header if present */
            if (bufferCc && *bufferCc) {
                size_t oldLen = strlen(bufferHeader);
                size_t ccLen = strlen(bufferCc);
                bufferHeader = erealloc(bufferHeader, oldLen + ccLen + 8);
                snprintf(bufferHeader + oldLen, ccLen + 8, "\r\nCc: %s", bufferCc);
            }
            /* Append Bcc header if present */
            if (bufferBcc && *bufferBcc) {
                size_t oldLen = strlen(bufferHeader);
                size_t bccLen = strlen(bufferBcc);
                bufferHeader = erealloc(bufferHeader, oldLen + bccLen + 9);
                snprintf(bufferHeader + oldLen, bccLen + 9, "\r\nBcc: %s", bufferBcc);
            }
            if (TSendMail(INI_STR("SMTP"), &tsm_err, &tsm_errmsg, bufferHeader, ZSTR_VAL(subject),
                bufferTo, ZSTR_VAL(message)) != SUCCESS)
#else
            $1
#endif
'@

            Set-Content php_imap.c -Value $content -NoNewline
            Write-Host "✓ Fixed TSendMail call in php_imap.c"
        } else {
            Write-Host "TSendMail call pattern not found or already patched"
        }
    } else {
        Write-Host "php_imap.c not found, skipping"
    }
}
