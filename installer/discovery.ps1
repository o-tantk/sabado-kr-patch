# Steam paths use Windows case-insensitive semantics; registry paths often use
# lowercase forward slashes while libraryfolders.vdf uses backslashes.
function Get-UniqueSteamPaths([string[]]$Paths) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try { $normalized = [IO.Path]::GetFullPath($path).TrimEnd('\', '/') }
        catch { continue }
        if ($seen.Add($normalized)) { $normalized }
    }
}

function Get-SteamRoots {
    Get-UniqueSteamPaths @(
        (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath,
        (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath,
        (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath,
        (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    )
}

function Read-SteamText([string]$Path) {
    try { [IO.File]::ReadAllText($Path) }
    catch { '' } # A stale/inaccessible library must not prevent checking the others.
}

function Find-Sabado([string[]]$SteamRoots = (Get-SteamRoots)) {
    $roots = @(Get-UniqueSteamPaths $SteamRoots)
    $libraries = @($roots)
    foreach ($root in $roots) {
        $text = Read-SteamText (Join-Path $root 'steamapps\libraryfolders.vdf')
        foreach ($match in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    foreach ($library in (Get-UniqueSteamPaths $libraries)) {
        $apps = Join-Path $library 'steamapps'
        $text = Read-SteamText (Join-Path $apps 'appmanifest_4986750.acf')
        $match = [regex]::Match($text, '"installdir"\s*"([^"]+)"')
        $name = if ($match.Success) { $match.Groups[1].Value } else { 'Sabado' }
        if ($name -in @('.', '..') -or $name -match '[/\\:]') { continue }
        $candidate = Join-Path (Join-Path $apps 'common') $name
        if ([IO.File]::Exists((Join-Path $candidate 'Sabado Day One.exe'))) {
            # Offer the first installed game. The confirmation still lets the user
            # choose another folder; multiple paths are not a discovery failure.
            return $candidate
        }
    }
    return $null
}
