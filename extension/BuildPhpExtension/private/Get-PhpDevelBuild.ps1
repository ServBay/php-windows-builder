function Get-PhpDevelBuild {
    <#
    .SYNOPSIS
        Get the PHP build.
    .PARAMETER Config
        Extension Configuration
    .PARAMETER BuildDetails
        PHP Build Details
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Configuration for the extension')]
        [PSCustomObject] $Config,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Php Build Details')]
        [PSCustomObject] $BuildDetails,
        [Parameter(Mandatory = $false, Position=2, HelpMessage='Local PHP build path')]
        [string] $PhpBuildPath = ''
    )
    begin {
    }
    process {
        try {
            Add-StepLog "Adding developer build for PHP $($Config.php_version)"
            Add-Type -Assembly "System.IO.Compression.Filesystem"
            $phpSemver, $baseUrl, $fallbackBaseUrl = $BuildDetails.phpSemver, $BuildDetails.baseUrl, $BuildDetails.fallbackBaseUrl

            # If phpSemver is empty and we have local build path, use php_version directly
            if (($null -eq $phpSemver -or $phpSemver -eq '') -and $PhpBuildPath -ne '') {
                Write-Host "phpSemver is empty, using php_version: $($Config.php_version)"
                $phpSemver = $Config.php_version
            }

            $tsPart = if ($Config.ts -eq "nts") {"nts-Win32"} else {"Win32"}
            $binZipFile = "php-devel-pack-$phpSemver-$tsPart-$($Config.vs_version)-$($Config.arch).zip"
            $binUrl = "$baseUrl/$binZipFile"
            $fallBackUrl = "$fallbackBaseUrl/$binZipFile"

            if($Config.php_version -lt '7.4') {
                $fallBackUrl = $fallBackUrl.replace("vc", "VC")
            }

            # Check if local PHP build path is provided and file exists
            Write-Host "==> Checking for local PHP devel build"
            Write-Host "PhpBuildPath parameter: '$PhpBuildPath'"
            Write-Host "phpSemver from BuildDetails: '$($BuildDetails.phpSemver)'"
            Write-Host "phpSemver used: '$phpSemver'"
            Write-Host "Expected file name: $binZipFile"

            if ($PhpBuildPath -ne '' -and (Test-Path $PhpBuildPath)) {
                Write-Host "Local PHP build path exists: $PhpBuildPath"
                Write-Host "Files in directory:"
                Get-ChildItem -Path $PhpBuildPath | ForEach-Object { Write-Host "  - $($_.Name)" }

                $localZipFile = Join-Path $PhpBuildPath $binZipFile
                if (Test-Path $localZipFile) {
                    Write-Host "✓ Using local PHP devel build from: $localZipFile"
                    Copy-Item -Path $localZipFile -Destination $binZipFile -Force
                } else {
                    Write-Host "✗ Local PHP devel build not found at: $localZipFile"
                    Write-Host "Falling back to download"
                    try {
                        Get-File -Url $binUrl -OutFile $binZipFile
                    } catch {
                        try {
                            Get-File -Url $fallBackUrl -OutFile $binZipFile
                        } catch {
                            throw "Failed to download the build for PHP version $($Config.php_version)."
                        }
                    }
                }
            } else {
                if ($PhpBuildPath -eq '') {
                    Write-Host "✗ PhpBuildPath is empty, downloading from web"
                } else {
                    Write-Host "✗ PhpBuildPath does not exist: $PhpBuildPath"
                    Write-Host "Downloading from web"
                }
                try {
                    Get-File -Url $binUrl -OutFile $binZipFile
                } catch {
                    try {
                        Get-File -Url $fallBackUrl -OutFile $binZipFile
                    } catch {
                        throw "Failed to download the build for PHP version $($Config.php_version)."
                    }
                }
            }

            $currentDirectory = (Get-Location).Path
            $binZipFilePath = Join-Path $currentDirectory $binZipFile
            $binDirectoryPath = Join-Path $currentDirectory php-dev

            [System.IO.Compression.ZipFile]::ExtractToDirectory($binZipFilePath, $binDirectoryPath)
            Move-Item $binDirectoryPath/php-*/* $binDirectoryPath/
            Add-Path -PathItem $binDirectoryPath
            Add-BuildLog tick PHP "PHP developer build added successfully"
            return $binDirectoryPath
        } catch {
            Add-BuildLog cross PHP "Failed to download the PHP developer build"
            throw
        }
    }
    end {
    }
}