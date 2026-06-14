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

$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
    Write-Host "Claude Code found: $(claude --version)"
    Write-Host "  Both roles run on this binary: architect = your interactive Opus 4.8 session,"
    Write-Host "  builder = headless 'claude -p --model claude-sonnet-4-6'."
    Write-Host "  Builder/researcher hours draw on the Agent SDK credit pool on your Claude plan."
} else {
    Write-Host "Claude Code not found - install it from https://claude.com/claude-code"
}
