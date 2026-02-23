Function Invoke-Build {
    <#
    .SYNOPSIS
        Build the extension
    .PARAMETER Config
        Extension Configuration
    #>
    [OutputType()]
    param(
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Extension Configuration')]
        [PSCustomObject] $Config
    )
    begin {
    }
    process {
        Add-StepLog "Building $($Config.name) extension"
        try {
            Set-GAGroup start

            $builder = "php-sdk\phpsdk-starter.bat"
            $task = [System.IO.Path]::Combine($PSScriptRoot, '..\config\task.bat')

            $options = $Config.options
            if ($Config.debug_symbols) {
                $options += " --enable-debug-pack"
            }
            Set-Content -Path task.bat -Value (Get-Content -Path $task -Raw).Replace("OPTIONS", $options)

            $ref = $Config.ref
            if($env:ARTIFACT_NAMING_SCHEME -eq 'pecl') {
                $ref = $Config.ref.ToLower()
            }
            $suffix = "php_" + (@(
                $Config.name,
                $ref,
                $Config.php_version,
                $Config.ts,
                $Config.vs_version,
                $Config.arch
            ) -join "-")
            & $builder -c $Config.vs_version -a $Config.Arch -s $Config.vs_toolset -t task.bat | Tee-Object -FilePath "build-$suffix.txt"
            Set-GAGroup end
            $dllPath = "$((Get-Location).Path)\$($Config.build_directory)\php_$($Config.name).dll"
            if(-not(Test-Path $dllPath)) {
                # Check for LNK1170: response file line exceeds 131071 characters
                $buildLog = Get-Content "build-$suffix.txt" -Raw -ErrorAction SilentlyContinue
                if ($buildLog -and $buildLog -match 'LNK1170') {
                    Write-Host "Detected LNK1170: response file line too long. Fixing response files..."
                    $fixed = $false
                    Get-ChildItem -Path . -Recurse -Filter "*.txt" -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -match '\\resp\\' } | ForEach-Object {
                        $content = [System.IO.File]::ReadAllText($_.FullName)
                        if ($content.Length -gt 100000) {
                            Write-Host "  Fixing $($_.Name) ($($content.Length) chars)"
                            [System.IO.File]::WriteAllText($_.FullName, ($content -replace '\.obj\s+', ".obj`n"))
                            $fixed = $true
                        }
                    }
                    if ($fixed) {
                        Write-Host "Response files fixed. Retrying link step..."
                        Set-Content -Path "task-retry.bat" -Value "nmake /nologo 2>&1`nexit %errorlevel%"
                        Set-GAGroup start
                        & $builder -c $Config.vs_version -a $Config.Arch -s $Config.vs_toolset -t task-retry.bat | Tee-Object -FilePath "build-$suffix-retry.txt"
                        Set-GAGroup end
                    }
                }
            }
            if(-not(Test-Path $dllPath)) {
                throw "Failed to build the extension"
            }
            Add-BuildLog tick $Config.name "Extension $($Config.name) built successfully"
        } catch {
            Add-BuildLog cross $Config.name "Failed to build the extension"
            throw
        }
    }
    end {
    }
}