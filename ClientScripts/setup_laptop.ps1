# PocketOllama 1-Line Setup for Windows PowerShell

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   PocketOllama Laptop Client Setup (Windows PowerShell) " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$env:OPENAI_BASE_URL = "http://iphone-ai.local:11434/v1"
$env:OPENAI_API_KEY = "pocketollama"
$env:OLLAMA_HOST = "http://iphone-ai.local:11434"

[System.Environment]::SetEnvironmentVariable('OPENAI_BASE_URL', 'http://iphone-ai.local:11434/v1', [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('OPENAI_API_KEY', 'pocketollama', [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', 'http://iphone-ai.local:11434', [System.EnvironmentVariableTarget]::User)

Write-Host "✅ Configured User Environment Variables:" -ForegroundColor Green
Write-Host "  • OPENAI_BASE_URL = http://iphone-ai.local:11434/v1"
Write-Host "  • OPENAI_API_KEY  = pocketollama"
Write-Host "  • OLLAMA_HOST     = http://iphone-ai.local:11434"

Write-Host "`n🚀 Testing connection to iPhone AI Server..." -ForegroundColor Yellow
try {
    $res = Invoke-RestMethod -Uri "http://iphone-ai.local:11434/v1/models" -TimeoutSec 3 -ErrorAction Stop
    Write-Host "✅ Connected successfully to iPhone! Available models:" -ForegroundColor Green
    $res.data | ForEach-Object { Write-Host "  • $($_.id)" -ForegroundColor Cyan }
} catch {
    Write-Host "⚠️ Notice: Could not connect to http://iphone-ai.local:11434 yet." -ForegroundColor DarkYellow
    Write-Host "Make sure PocketOllama is running on your iPhone and connected to the same Wi-Fi network!" -ForegroundColor DarkYellow
}

Write-Host "`n🎉 Setup complete! You can now use Cursor, Continue.dev, Aider, or Python harnesses directly." -ForegroundColor Green
