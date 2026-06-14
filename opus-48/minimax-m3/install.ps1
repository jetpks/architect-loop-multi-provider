param([switch]$Project)

$srcRoot = Join-Path $PSScriptRoot "skills"
if ($Project) {
    $destRoot = Join-Path (Get-Location) ".claude\skills"
} else {
    $destRoot = Join-Path $env:USERPROFILE ".claude\skills"
}

New-Item -ItemType Directory -Force $destRoot | Out-Null
foreach ($skill in Get-ChildItem -Directory $srcRoot) {
    $dest = Join-Path $destRoot $skill.Name
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Recurse $skill.FullName $dest
    Write-Host "Installed /$($skill.Name) to $dest"
}

$pi = Get-Command pi -ErrorAction SilentlyContinue
if ($pi) {
    Write-Host "pi CLI found: $(pi --version)"
    if (-not $env:OPENROUTER_API_KEY) {
        Write-Host "  WARNING: OPENROUTER_API_KEY is not set - the builder needs it for minimax/minimax-m3"
    }
    Write-Host "  Builder model: pi --list-models minimax/minimax-m3"
    Write-Host "  Web access:    pi install npm:pi-web-access  (zero-config via Exa)"
} else {
    Write-Host "pi CLI not found - install the builder from https://pi.dev"
}
