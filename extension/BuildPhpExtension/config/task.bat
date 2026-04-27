
if exist "..\deps\lib\brotlidec.lib" set LDFLAGS=brotlidec.lib brotlicommon.lib libzstd.lib
call phpize 2>&1
call configure --with-php-build="..\deps" OPTIONS --with-mp="disable" 2>&1
nmake /nologo 2>&1
exit %errorlevel%
