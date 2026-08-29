#!/usr/bin/env bash
# PocketOllama 1-Line Setup for macOS & Linux

echo "======================================================="
echo "   PocketOllama Laptop Client Setup (macOS / Linux)    "
echo "======================================================="

export OPENAI_BASE_URL="http://iphone-ai.local:11434/v1"
export OPENAI_API_KEY="pocketollama"
export OLLAMA_HOST="http://iphone-ai.local:11434"

SHELL_RC="$HOME/.zshrc"
if [ ! -f "$SHELL_RC" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if ! grep -q "OPENAI_BASE_URL.*iphone-ai.local" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# PocketOllama iPhone Server Auto-Routing" >> "$SHELL_RC"
    echo "export OPENAI_BASE_URL=\"http://iphone-ai.local:11434/v1\"" >> "$SHELL_RC"
    echo "export OPENAI_API_KEY=\"pocketollama\"" >> "$SHELL_RC"
    echo "export OLLAMA_HOST=\"http://iphone-ai.local:11434\"" >> "$SHELL_RC"
    echo "alias ollama-iphone='curl http://iphone-ai.local:11434/v1/models'" >> "$SHELL_RC"
    echo "✅ Exported environment variables to $SHELL_RC"
else
    echo "ℹ️ Environment variables already present in $SHELL_RC"
fi

echo ""
echo "🚀 Testing connection to iPhone..."
curl -s http://iphone-ai.local:11434/v1/models || echo "⚠️ Could not reach iphone-ai.local yet. Ensure PocketOllama is running on your iPhone and both devices are on the same Wi-Fi!"

echo ""
echo "🎉 Setup complete! You can now use Cursor, Continue.dev, Aider, or Python directly with your iPhone!"
