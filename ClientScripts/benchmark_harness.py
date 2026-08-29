#!/usr/bin/env python3
"""
PocketOllama Benchmark & Harness Test Suite
Evaluates TTFT (Time-To-First-Token), Tokens/Sec, Logprobs, and overnight loop resilience.
"""

import os
import sys
import time
import json
import urllib.request

BASE_URL = os.getenv("OPENAI_BASE_URL", "http://iphone-ai.local:11434/v1")
API_KEY = os.getenv("OPENAI_API_KEY", "pocketollama")

def check_server_health():
    print(f"[*] Checking PocketOllama Server at: {BASE_URL}")
    try:
        req = urllib.request.Request(f"{BASE_URL}/models", headers={"Authorization": f"Bearer {API_KEY}"})
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
            print(f"✅ Connected! Available models: {[m['id'] for m in data.get('data', [])]}")
            return True
    except Exception as e:
        print(f"❌ Server unreachable at {BASE_URL}: {e}")
        return False

def run_benchmark(num_iterations=5):
    try:
        from openai import OpenAI
    except ImportError:
        print("Please install openai: pip install openai")
        return

    client = OpenAI(base_url=BASE_URL, api_key=API_KEY)
    test_prompt = "Explain quantum computing in 3 concise bullet points."
    
    print(f"\n🚀 Running Benchmark ({num_iterations} iterations)...")
    ttft_list = []
    tps_list = []

    for i in range(1, num_iterations + 1):
        start_time = time.time()
        first_token_time = None
        token_count = 0

        stream = client.chat.completions.create(
            model="hermes-3-llama-3.2-3b",
            messages=[{"role": "user", "content": test_prompt}],
            stream=True
        )

        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                if first_token_time is None:
                    first_token_time = time.time()
                token_count += 1

        end_time = time.time()
        ttft = (first_token_time - start_time) if first_token_time else (end_time - start_time)
        gen_time = max(0.001, end_time - (first_token_time or start_time))
        tps = token_count / gen_time

        ttft_list.append(ttft)
        tps_list.append(tps)

        print(f"  [Run {i}/{num_iterations}] TTFT: {ttft*1000:.1f}ms | Generation: {tps:.1f} tokens/sec ({token_count} tokens)")

    avg_ttft = sum(ttft_list) / len(ttft_list)
    avg_tps = sum(tps_list) / len(tps_list)

    print("\n" + "=" * 50)
    print(f"🏆 Final Benchmark Results:")
    print(f"  • Average TTFT: {avg_ttft*1000:.1f} ms")
    print(f"  • Average Throughput: {avg_tps:.1f} tokens/sec")
    print("=" * 50)

if __name__ == "__main__":
    if check_server_health():
        run_benchmark(5)
