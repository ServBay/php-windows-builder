function Invoke-PhpBuild {
    <#
    .SYNOPSIS
        Build PHP.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER Ts
        PHP Build Type
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='PHP Version')]
        [string] $PhpVersion = '',
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP Build Type')]
        [ValidateNotNull()]
        [ValidateSet('nts', 'ts')]
        [string] $Ts,
        [Parameter(Mandatory = $false, Position=3, HelpMessage='SDK build branch for deps/CRT; set to master to build a pre-GA source against master deps')]
        [string] $BuildBranch = ''
    )
    begin {
    }
    process {
        Set-NetSecurityProtocolType
        $fetchSrc = $True
        if($null -eq $PhpVersion -or $PhpVersion -eq '') {
            $fetchSrc = $False
            $PhpVersion = Get-SourcePhpVersion
        }
        # CRT/deps come from the build branch when overridden (e.g. build a pre-GA
        # tag against master's SDK deps, since the tag's own branch has no published
        # deps yet); otherwise they come from the PHP version itself.
        $vsRef = if ($BuildBranch) { $BuildBranch } else { $PhpVersion }
        $VsConfig = (Get-VsVersion -PhpVersion $vsRef)
        if($null -eq $VsConfig.vs) {
            throw "PHP version $vsRef is not supported."
        }
        # libsdk otherwise guesses the SDK branch from the source's php_version.h;
        # pin it to the build branch so a pre-GA source resolves deps/CRT from an
        # available branch (libsdk honors master via this env in guessCurrentBranchName).
        if ($BuildBranch) {
            $env:PHP_RMTOOLS_PHP_BUILD_BRANCH = $BuildBranch
        }

        $currentDirectory = (Get-Location).Path

        $tempDirectory = [System.IO.Path]::GetTempPath()

        $buildDirectory = [System.IO.Path]::Combine($tempDirectory, ("php-" + [System.Guid]::NewGuid().ToString()))

        New-Item "$buildDirectory" -ItemType "directory" -Force > $null 2>&1

        Set-Location "$buildDirectory"

        Add-BuildRequirements -PhpVersion $PhpVersion -Arch $Arch -FetchSrc:$fetchSrc

        Copy-Item -Path $PSScriptRoot\..\config -Destination . -Recurse
        $buildPath = "$buildDirectory\config\$($VsConfig.vs)\$Arch\php-$PhpVersion"
        $sourcePath = "$buildDirectory\php-$PhpVersion-src"
        if(-not($fetchSrc)) {
            $sourcePath = $currentDirectory
        }
        Move-Item $sourcePath $buildPath
        Set-Location "$buildPath"

        # PHP 8.6 removed XtOffsetOf from Zend/zend_portability.h; restore it (guarded)
        # so the compiled devel pack ships it and PECL extensions that include this
        # header keep building. Versions that still define it are unaffected.
        $zpHeader = "Zend\zend_portability.h"
        if ((Test-Path $zpHeader) -and -not (Select-String -Path $zpHeader -SimpleMatch 'define XtOffsetOf' -Quiet)) {
            Add-Content -Path $zpHeader -Value "`n#ifndef XtOffsetOf`n# define XtOffsetOf(s_type, field) offsetof(s_type, field)`n#endif"
        }

        New-Item "..\obj" -ItemType "directory" > $null 2>&1
        Copy-Item "..\config.$Ts.bat"

        $task = "$PSScriptRoot\..\runner\task-$Ts.bat"

        & "$buildDirectory\php-sdk\phpsdk-starter.bat" -c $VsConfig.vs -a $Arch -s $VsConfig.toolset -t $task
        if (-not $?) {
            throw "build failed with errorlevel $LastExitCode"
        }

        $artifacts = if ($Ts -eq "ts") {"..\obj\Release_TS\php-*.zip"} else {"..\obj\Release\php-*.zip"}
        New-Item "$currentDirectory\artifacts" -ItemType "directory" -Force > $null 2>&1
        xcopy $artifacts "$currentDirectory\artifacts\*"
        Move-Item "$buildDirectory\php-$PhpVersion-src.zip" "$currentDirectory\artifacts\"

        Set-Location "$currentDirectory"
    }
    end {
    }
}