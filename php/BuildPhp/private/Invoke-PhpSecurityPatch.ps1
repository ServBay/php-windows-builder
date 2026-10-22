function Invoke-PhpSecurityPatch {
    <#
    .SYNOPSIS
        Apply vendored PHP security backports to the extracted source tree.

    .DESCRIPTION
        Patches are matched on the upstream x.y.z version, so a backport published
        as x.y.z.N (see Get-PhpSrc) can only reach the release it was built
        against. No matching file means no work at all, which keeps mainstream
        releases byte-identical to upstream.

        Patch files live in BuildPhp\patches and are named <x.y.z>-<reason>.patch.
        They are generated against the upstream php-src source layout and applied
        with -p1 from the source root.

    .PARAMETER PhpVersion
        PHP version being built; may carry a local revision segment (x.y.z.N).

    .PARAMETER PatchRoot
        Directory holding the patch files. Defaults to BuildPhp\patches.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP version being built')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $false, Position=1, HelpMessage='Directory holding the patch files')]
        [string] $PatchRoot = ''
    )
    begin {
    }
    process {
        if (-not $PatchRoot) {
            $PatchRoot = [System.IO.Path]::Combine($PSScriptRoot, '..', 'patches')
        }
        if (-not (Test-Path $PatchRoot)) {
            return
        }

        # x.y.z.N is a local backport of upstream x.y.z; anything else is upstream
        # verbatim and therefore only matched by its own name.
        $baseVersion = $PhpVersion
        if ($PhpVersion -match '^(\d+\.\d+\.\d+)\.\d+$') {
            $baseVersion = $Matches[1]
        }

        $patches = @(Get-ChildItem -Path $PatchRoot -Filter "$baseVersion-*.patch" -File -ErrorAction SilentlyContinue)
        if ($patches.Count -eq 0) {
            return
        }

        foreach ($patch in $patches) {
            Write-Host "Applying PHP security patch: $($patch.Name)"
            git apply --ignore-whitespace -p1 "$($patch.FullName)"
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to apply PHP security patch $($patch.Name) to $PhpVersion"
            }
        }

        # Upstream ships zend_vm_def.h, zend_vm_execute.h and zend_vm_opcodes.h
        # with one shared timestamp. A patch rewrites the first two, so the
        # generated ones look stale and nmake re-runs zend_vm_gen.php mid-build.
        # Touch them together so the headers the tarball already ships are used.
        $now = Get-Date
        foreach ($generated in @('Zend\zend_vm_execute.h', 'Zend\zend_vm_opcodes.h')) {
            if (Test-Path $generated) {
                (Get-Item $generated).LastWriteTime = $now
            }
        }

        Write-Host "Applied $($patches.Count) PHP security patch(es) to $PhpVersion"
    }
    end {
    }
}
