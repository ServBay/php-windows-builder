
set LDFLAGS=brotlidec.lib brotlicommon.lib libzstd.lib 2>&1
call phpize 2>&1
call configure --with-php-build="..\deps" OPTIONS --with-mp="disable" 2>&1
nmake /nologo 2>&1
exit %errorlevel%
