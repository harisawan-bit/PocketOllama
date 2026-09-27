import Foundation

public enum WebDashboardHTML {
    public static func render(serverIP: String, port: String, modelName: String, apiKey: String = "") -> String {
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

                <div id="apikey-row" style="display: \(apiKey.isEmpty ? "none" : "flex"); margin-bottom: 8px;">
                    <input id="apikey-input" type="password" placeholder="API key (required)"
                           onkeydown="if(event.key==='Enter'){ localStorage.setItem('poApiKey', this.value.trim()); this.value=''; sendPrompt(); }" />
                    <button onclick="localStorage.setItem('poApiKey', document.getElementById('apikey-input').value.trim()); document.getElementById('apikey-input').value=''; sendPrompt();">SET</button>
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
                    assistantBubble.textContent = 'Thinking...';
                    msgs.appendChild(assistantBubble);
                    msgs.scrollTop = msgs.scrollHeight;

                    try {
                        const headers = { 'Content-Type': 'application/json' };
                        const poKey = localStorage.getItem('poApiKey') || '';
                        if (poKey) { headers['Authorization'] = 'Bearer ' + poKey; }
                        const res = await fetch(endpoint, {
                            method: 'POST',
                            headers: headers,
                            body: JSON.stringify({
                                model: '\(modelName)',
                                messages: [{ role: 'user', content: text }],
                                stream: true
                            })
                        });

                        if (!res.ok) {
                            let detail = '';
                            try { detail = (await res.text()).slice(0, 300); } catch (e) {}
                            const note = document.createElement('span');
                            note.style.color = '#ef4444';
                            note.textContent = 'HTTP ' + res.status + (detail ? ' - ' + detail : '');
                            assistantBubble.textContent = '';
                            assistantBubble.appendChild(note);
                            return;
                        }

                        const reader = res.body.getReader();
                        // {stream:true} so a multi-byte character split across two
                        // network reads is not corrupted into U+FFFD.
                        const decoder = new TextDecoder('utf-8');
                        assistantBubble.textContent = '';
                        const thoughtBox = document.createElement('div');
                        thoughtBox.className = 'thought-box';
                        const thoughtLabel = document.createElement('strong');
                        thoughtLabel.textContent = 'THOUGHT: ';
                        const thoughtText = document.createElement('span');
                        thoughtBox.appendChild(thoughtLabel);
                        thoughtBox.appendChild(thoughtText);
                        const answerText = document.createElement('span');
                        assistantBubble.appendChild(thoughtBox);
                        assistantBubble.appendChild(answerText);

                        let accumulatedContent = '';
                        let accumulatedReasoning = '';
                        // A network read can end anywhere, including halfway
                        // through a data: line. Without carrying the remainder
                        // over, JSON.parse failed on a fragment and the empty
                        // catch swallowed it, so tokens intermittently vanished.
                        let pending = '';
                        // Rendered on a timer instead of per token: assigning
                        // on every token forced a full re-layout per token.
                        let dirty = false;
                        const render = () => {
                            if (!dirty) return;
                            dirty = false;
                            thoughtBox.style.display = accumulatedReasoning ? '' : 'none';
                            // textContent, never innerHTML. The model output is
                            // untrusted: assigning it to innerHTML let a model
                            // return markup that ran in this origin and read the
                            // API key straight out of localStorage.
                            thoughtText.textContent = accumulatedReasoning;
                            answerText.textContent = accumulatedContent;
                            msgs.scrollTop = msgs.scrollHeight;
                        };
                        const renderTimer = setInterval(render, 60);

                        const applyLine = (line) => {
                            const trimmed = line.trim();
                            if (!trimmed.startsWith('data: ')) return;
                            const payload = trimmed.substring(6).trim();
                            if (!payload || payload === '[DONE]') return;
                            let json;
                            try { json = JSON.parse(payload); } catch (e) { return; }
                            const delta = json && json.choices && json.choices[0]
                                ? json.choices[0].delta : null;
                            if (!delta) return;
                            if (delta.reasoning_content) {
                                accumulatedReasoning += delta.reasoning_content;
                                dirty = true;
                            }
                            if (delta.content) {
                                accumulatedContent += delta.content;
                                dirty = true;
                            }
                        };

                        try {
                            while (true) {
                                const { value, done } = await reader.read();
                                if (done) break;
                                pending += decoder.decode(value, { stream: true });
                                let nl;
                                while ((nl = pending.indexOf('\n')) !== -1) {
                                    applyLine(pending.slice(0, nl));
                                    pending = pending.slice(nl + 1);
                                }
                            }
                            pending += decoder.decode();
                            if (pending.trim()) applyLine(pending);
                        } finally {
                            clearInterval(renderTimer);
                            render();
                        }
                    } catch (err) {
                        const note = document.createElement('span');
                        note.style.color = '#ef4444';
                        note.textContent = 'Error connecting to local server: ' + err.message;
                        assistantBubble.appendChild(note);
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
