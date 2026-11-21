param(
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Part = 'patch',
    [switch]$Push
)

# Quick version bump for machines without a Flutter/Dart SDK.
# Updates VERSION and pubspec.yaml, then optionally commits and pushes.
$root = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $root 'VERSION'
$pubspecFile = Join-Path $root 'pubspec.yaml'

$raw = (Get-Content $versionFile -Raw).Trim()
$body = ($raw -replace '^v', '' -split '[-+]')[0]
$parts = @($body.Split('.') | ForEach-Object { [int]$_ })
while ($parts.Count -lt 3) { $parts += 0 }

switch ($Part) {
    'major' { $parts[0]++; $parts[1] = 0; $parts[2] = 0 }
    'minor' { $parts[1]++; $parts[2] = 0 }
    default { $parts[2]++ }
}

# X.YY.ZZ：minor 与 hotfix 固定两位。
$next = '{0}.{1:D2}.{2:D2}' -f $parts[0], $parts[1], $parts[2]
[IO.File]::WriteAllText($versionFile, "$next`n", (New-Object System.Text.UTF8Encoding($false)))

$text = [IO.File]::ReadAllText($pubspecFile)
$build = 1
if ($text -match '(?m)^version:\s*\S+\+(\d+)\s*$') { $build = [int]$Matches[1] }
$text = [regex]::Replace($text, '(?m)^version:\s*\S+\s*$', "version: $next+$build")
[IO.File]::WriteAllText($pubspecFile, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "VERSION -> $next"

if ($Push) {
    git -C $root add VERSION pubspec.yaml
    git -C $root commit -m "chore(release): $next"
    git -C $root push
}
