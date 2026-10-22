function Get-PhpSrc {
    <#
    .SYNOPSIS
        Get the PHP source code.
    .PARAMETER PhpVersion
        PHP Version
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [string] $PhpVersion
    )
    begin {
    }
    process {
        Add-Type -Assembly "System.IO.Compression.Filesystem"

        $baseUrl = "https://github.com/php/php-src/archive"
        $zipFile = "php-$PhpVersion.zip"
        $directory = "php-$PhpVersion-src"

        # A local security backport is published one segment above the upstream
        # tag (8.1.34.1 over 8.1.34) so the registry ranks it higher; upstream
        # never tags the extra segment. Fetch the release the build is based on
        # and keep the extra segment for the directory name only.
        $tagVersion = $PhpVersion
        if ( $PhpVersion -match '^(\d+\.\d+\.\d+)\.\d+$' ) {
            $tagVersion = $Matches[1]
            Write-Host "Version $PhpVersion is a local backport of upstream $tagVersion"
        }

        if ( $tagVersion.Contains("."))
        {
            $ref = "php-$tagVersion"
            $url = "$baseUrl/refs/tags/php-$tagVersion.zip"
        }
        else
        {
            $ref = $tagVersion
            $url = "$baseUrl/$tagVersion.zip"
        }

        $currentDirectory = (Get-Location).Path
        $zipFilePath = Join-Path $currentDirectory $zipFile
        $directoryPath = Join-Path $currentDirectory $directory
        $srcZipFilePath = Join-Path $currentDirectory "php-$PhpVersion-src.zip"

        Get-File -Url $url -Outfile $zipFile
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $currentDirectory)
        Rename-Item -Path "php-src-$ref" -NewName $directory
        [System.IO.Compression.ZipFile]::CreateFromDirectory($directoryPath, $srcZipFilePath)
    }
    end {
    }
}