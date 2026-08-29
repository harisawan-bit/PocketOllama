#!/usr/bin/env python3
"""
PocketOllama - Hermes Agent Runner
Tests multi-step autonomous tool calling and scratchpad reasoning with an iPhone local server.
"""

import os
import sys
import json
import subprocess
import time
try:
    from openai import OpenAI
except ImportError:
    print("Error: openai package not installed. Run: pip install openai")
    sys.exit(1)

BASE_URL = os.getenv("OPENAI_BASE_URL", "http://iphone-ai.local:11434/v1")
API_KEY = os.getenv("OPENAI_API_KEY", "pocketollama")

print(f"[*] Connecting Hermes Agent to iPhone AI Server: {BASE_URL}")
client = OpenAI(base_url=BASE_URL, api_key=API_KEY)

tools = [
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": "Execute a bash / terminal command on the laptop and return stdout/stderr",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to execute, e.g., 'git status' or 'ls -la'"
                    }
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the contents of a local file on the laptop",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file to read"
                    }
                },
                "required": ["path"]
            }
        }
    }
]

def execute_local_tool(name: str, arguments_str: str) -> str:
    print(f"\n[🔧 Executing Laptop Tool: {name}] Args: {arguments_str}")
    try:
        args = json.loads(arguments_str) if isinstance(arguments_str, str) else arguments_str
    except json.JSONDecodeError:
        return json.dumps({"error": "Malformed JSON arguments"})

    if name == "run_shell_command":
        cmd = args.get("command", "")
        print(f"  > Running: {cmd}")
        try:
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            output = res.stdout if res.returncode == 0 else f"Error: {res.stderr}"
            return output[:2000]
        except Exception as e:
            return f"Command execution failed: {str(e)}"

    elif name == "read_file":
        path = args.get("path", "")
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()[:4000]
        except Exception as e:
            return f"Failed to read file: {str(e)}"

    return f"Unknown tool: {name}"

def run_agent_loop(goal: str, max_turns: int = 10):
    messages = [
        {
            "role": "system",
            "content": "You are Hermes, an autonomous AI engineer. Use available tools step-by-step to achieve the goal. Think carefully in your scratchpad before calling tools."
        },
        {"role": "user", "content": goal}
    ]

    print(f"\n🎯 Goal: {goal}\n" + "=" * 60)

    for turn in range(1, max_turns + 1):
        print(f"\n--- [Turn {turn}/{max_turns}] Waiting for iPhone Inference ---")
        start_t = time.time()

        try:
            response = client.chat.completions.create(
                model="hermes-3-llama-3.2-3b",
                messages=messages,
                tools=tools,
                stream=True
            )
        except Exception as e:
            print(f"❌ Connection error to iPhone: {e}")
            break

        accumulated_content = ""
        tool_calls = []

        for chunk in response:
            delta = chunk.choices[0].delta if chunk.choices else None
            if not delta:
                continue

            if hasattr(delta, "reasoning_content") and delta.reasoning_content:
                print(f"\033[90m{delta.reasoning_content}\033[0m", end="", flush=True)

            if delta.content:
                print(delta.content, end="", flush=True)
                accumulated_content += delta.content

            if delta.tool_calls:
                for tc in delta.tool_calls:
                    tool_calls.append(tc)

        elapsed = time.time() - start_t
        print(f"\n[⏱️ iPhone Response in {elapsed:.2f}s]")

        if tool_calls:
            for tc in tool_calls:
                fn_name = tc.function.name if hasattr(tc, 'function') else tc.get('name')
                fn_args = tc.function.arguments if hasattr(tc, 'function') else tc.get('arguments', '{}')
                tool_output = execute_local_tool(fn_name, fn_args)

                messages.append({
                    "role": "tool",
                    "tool_call_id": getattr(tc, 'id', 'call_1'),
                    "name": fn_name,
                    "content": tool_output
                })
        else:
            print("\n✅ Task completed by Hermes Agent!")
            break

if __name__ == "__main__":
    test_goal = sys.argv[1] if len(sys.argv) > 1 else "Check current directory contents and report system status."
    run_agent_loop(test_goal)
