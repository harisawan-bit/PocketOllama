import Foundation

public enum WebDashboardHTML {
    public static func render(serverIP: String, port: String, modelName: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PocketOllama // Developer Web Console</title>
            <style>
                :root {
                    --bg-deep: #000000;
                    --bg-surface: #0c0d10;
                    --bg-hover: #14161c;
                    --border-subtle: #222630;
                    --terminal-green: #22c55e;
                    --dev-cyan: #38bdf8;
                    --dev-indigo: #818cf8;
                    --text-primary: #f4f4f5;
                    --text-secondary: #a1a7b3;
                    --text-muted: #666e7a;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, monospace; }
                body { background: var(--bg-deep); color: var(--text-primary); display: flex; height: 100vh; overflow: hidden; }
                #sidebar { width: 320px; background: var(--bg-surface); border-right: 1px solid var(--border-subtle); display: flex; flex-direction: column; padding: 20px; }
                #main { flex: 1; display: flex; flex-direction: column; background: var(--bg-deep); }
                .brand { font-size: 14px; font-weight: 800; letter-spacing: 1px; color: var(--dev-cyan); display: flex; align-items: center; gap: 8px; margin-bottom: 20px; }
                .status-badge { display: inline-flex; align-items: center; gap: 6px; font-size: 11px; font-weight: 700; color: var(--terminal-green); background: rgba(34, 197, 94, 0.12); padding: 4px 8px; border-radius: 4px; border: 1px solid rgba(34, 197, 94, 0.25); }
                .status-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--terminal-green); }
                .meta-section { margin-top: 24px; }
                .meta-label { font-size: 10px; font-weight: 800; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
                .meta-val { font-size: 13px; font-family: "SF Mono", monospace; color: var(--text-primary); word-break: break-all; }
                .code-box { background: var(--bg-deep); border: 1px solid var(--border-subtle); padding: 8px 10px; border-radius: 6px; font-family: monospace; font-size: 11px; color: var(--dev-cyan); margin-top: 6px; }
                #chat-messages { flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column; gap: 16px; }
                .msg { max-width: 800px; padding: 14px 18px; border-radius: 8px; font-size: 14px; line-height: 1.6; }
                .msg.user { align-self: flex-end; background: var(--bg-hover); border: 1px solid var(--dev-cyan); color: var(--text-primary); }
                .msg.assistant { align-self: flex-start; background: var(--bg-surface); border: 1px solid var(--border-subtle); }
                .thought-box { background: rgba(129, 140, 248, 0.08); border-left: 3px solid var(--dev-indigo); padding: 8px 12px; margin-bottom: 10px; font-family: monospace; font-size: 12px; color: var(--text-secondary); border-radius: 0 4px 4px 0; }
                #chat-input-row { padding: 16px 24px; background: var(--bg-surface); border-top: 1px solid var(--border-subtle); display: flex; gap: 12px; }
                #prompt-input { flex: 1; background: var(--bg-deep); border: 1px solid var(--border-subtle); color: var(--text-primary); padding: 12px 16px; border-radius: 6px; font-size: 14px; outline: none; }
                #prompt-input:focus { border-color: var(--dev-cyan); }
                button { background: var(--dev-cyan); color: #000; font-weight: 700; border: none; padding: 0 20px; border-radius: 6px; cursor: pointer; font-size: 13px; }
                button:hover { opacity: 0.9; }
            </style>
        </head>
        <body>
            <div id="sidebar">
                <div class="brand">⚡ POCKETOLLAMA // HUD</div>
                <div class="status-badge"><div class="status-dot"></div> METAL SERVER ONLINE</div>

                <div class="meta-section">
                    <div class="meta-label">Active Model</div>
                    <div class="meta-val">\(modelName)</div>
                </div>

                <div class="meta-section">
                    <div class="meta-label">OpenAI Endpoint</div>
                    <div class="code-box">http://\(serverIP):\(port)/v1</div>
                </div>

                <div class="meta-section">
                    <div class="meta-label">Ollama Host</div>
                    <div class="code-box">http://\(serverIP):\(port)</div>
                </div>

                <div class="meta-section">
                    <div class="meta-label">Quick Test (cURL)</div>
                    <div class="code-box">curl http://\(serverIP):\(port)/v1/models</div>
                </div>
            </div>

            <div id="main">
                <div id="chat-messages">
                    <div class="msg assistant">
                        <strong>PocketOllama Metal Engine:</strong> Ready for real-time inference. Connected directly to Apple Silicon GPU over your local Wi-Fi.
                    </div>
                </div>

                <div id="chat-input-row">
                    <input id="prompt-input" type="text" placeholder="Type prompt and press Enter..." autofocus onkeydown="if(event.key==='Enter') sendPrompt()" />
                    <button onclick="sendPrompt()">SEND</button>
                </div>
            </div>

            <script>
                const endpoint = '/v1/chat/completions';
                async function sendPrompt() {
                    const input = document.getElementById('prompt-input');
                    const text = input.value.trim();
                    if (!text) return;

                    input.value = '';
                    const msgs = document.getElementById('chat-messages');

                    const userBubble = document.createElement('div');
                    userBubble.className = 'msg user';
                    userBubble.textContent = text;
                    msgs.appendChild(userBubble);

                    const assistantBubble = document.createElement('div');
                    assistantBubble.className = 'msg assistant';
                    assistantBubble.innerHTML = '<em>Thinking...</em>';
                    msgs.appendChild(assistantBubble);
                    msgs.scrollTop = msgs.scrollHeight;

                    try {
                        const res = await fetch(endpoint, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                model: '\(modelName)',
                                messages: [{ role: 'user', content: text }],
                                stream: true
                            })
                        });

                        const reader = res.body.getReader();
                        const decoder = new TextDecoder();
                        assistantBubble.innerHTML = '';
                        let accumulatedContent = '';
                        let accumulatedReasoning = '';

                        while (true) {
                            const { value, done } = await reader.read();
                            if (done) break;
                            const chunk = decoder.decode(value);
                            const lines = chunk.split('\\n');

                            for (const line of lines) {
                                if (line.startsWith('data: ') && !line.includes('[DONE]')) {
                                    try {
                                        const json = JSON.parse(line.substring(6));
                                        const delta = json.choices[0].delta;
                                        if (delta.reasoning_content) {
                                            accumulatedReasoning += delta.reasoning_content;
                                        }
                                        if (delta.content) {
                                            accumulatedContent += delta.content;
                                        }

                                        let fullHTML = '';
                                        if (accumulatedReasoning) {
                                            fullHTML += '<div class="thought-box"><strong>THOUGHT:</strong> ' + accumulatedReasoning + '</div>';
                                        }
                                        fullHTML += accumulatedContent.replace(/\\n/g, '<br/>');
                                        assistantBubble.innerHTML = fullHTML;
                                        msgs.scrollTop = msgs.scrollHeight;
                                    } catch (e) {}
                                }
                            }
                        }
                    } catch (err) {
                        assistantBubble.innerHTML = '<span style="color: #ef4444;">Error connecting to local server: ' + err.message + '</span>';
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
