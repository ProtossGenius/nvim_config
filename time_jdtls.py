#!/usr/bin/env python3
import os
import sys
import json
import time
import subprocess
import tempfile
import shutil

def send_rpc(proc, method, params, msg_id=None):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params
    }
    if msg_id is not None:
        payload["id"] = msg_id
    content = json.dumps(payload)
    message = f"Content-Length: {len(content)}\r\n\r\n{content}"
    proc.stdin.write(message.encode('utf-8'))
    proc.stdin.flush()

def read_rpc(proc):
    content_length = None
    while True:
        line = proc.stdout.readline()
        if not line:
            return None
        line = line.decode('utf-8').strip()
        if line.startswith("Content-Length:"):
            content_length = int(line.split(":")[1].strip())
        elif line == "":
            break
    if content_length is None:
        return None
    content = proc.stdout.read(content_length)
    return json.loads(content.decode('utf-8'))

def main():
    # 1. Resolve project directory
    cwd = os.getcwd()
    print(f"[*] Testing JDTLS startup in: {cwd}")
    
    # 2. Check if pom.xml or build.gradle exists
    if not any(os.path.exists(os.path.join(cwd, f)) for f in ["pom.xml", "build.gradle", "build.gradle.kts"]):
        print("[-] Warning: No pom.xml or build.gradle found in current directory. JDTLS may start in no-project mode.")
    
    # 3. Locate JDTLS executable
    home = os.getenv("HOME")
    jdtls_bin = os.path.join(home, ".local/share/nvim/mason/bin/jdtls")
    if not os.path.exists(jdtls_bin):
        print(f"[-] Error: JDTLS not found at {jdtls_bin}")
        sys.exit(1)
        
    # 4. Create temporary workspace directory to avoid caching
    temp_dir = tempfile.mkdtemp(prefix="jdtls_bench_")
    print(f"[*] Created temporary workspace: {temp_dir}")
    
    cmd = [jdtls_bin, "-data", temp_dir]
    
    # Try to locate lombok
    lombok_glob = os.path.join(home, ".m2/repository/org/projectlombok/lombok/*/lombok-*.jar")
    import glob
    lombok_files = glob.glob(lombok_glob)
    if lombok_files:
        lombok_jar = lombok_files[-1]
        cmd.append(f"--jvm-arg=-javaagent:{lombok_jar}")
        print(f"[*] Lombok jar found and appended: {lombok_jar}")
    else:
        # Fallback lombok
        fallback = os.path.join(home, ".local/share/nvim/lombok.jar")
        if os.path.exists(fallback):
            cmd.append(f"--jvm-arg=-javaagent:{fallback}")
            print(f"[*] Lombok jar found and appended: {fallback}")

    print(f"[*] Spawning JDTLS process...")
    start_time = time.time()
    
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL
    )
    
    # 5. Send initialize request
    root_uri = f"file://{cwd}"
    init_params = {
        "processId": os.getpid(),
        "rootPath": cwd,
        "rootUri": root_uri,
        "capabilities": {
            "workspace": {
                "workspaceFolders": True,
                "configuration": True
            },
            "textDocument": {
                "synchronization": {
                    "dynamicRegistration": True,
                    "willSave": True,
                    "willSaveWaitUntil": True,
                    "didSave": True
                }
            }
        },
        "initializationOptions": {
            "workspaceFolders": [root_uri]
        }
    }
    
    send_rpc(proc, "initialize", init_params, msg_id=1)
    
    handshake_time = None
    ready_time = None
    
    try:
        while True:
            msg = read_rpc(proc)
            if not msg:
                break
                
            elapsed = time.time() - start_time
            
            # Check for initialize response
            if msg.get("id") == 1:
                handshake_time = elapsed
                print(f"[+] LSP Handshake Complete (initialize response received): {handshake_time:.2f} seconds")
                # Send initialized notification
                send_rpc(proc, "initialized", {})
                
            # Check for language/status or progress
            method = msg.get("method")
            params = msg.get("params", {})
            
            if method == "language/status":
                status_msg = params.get("message", "")
                print(f"    [Status Update] {status_msg} (elapsed: {elapsed:.2f}s)")
                if "ServiceReady" in status_msg or "Ready" in status_msg or "ready" in status_msg.lower():
                    ready_time = elapsed
                    print(f"\n[+] JDTLS IS FULLY STARTED AND READY: {ready_time:.2f} seconds")
                    break
            elif method == "$/progress":
                value = params.get("value", {})
                kind = value.get("kind")
                title = value.get("title", "")
                message = value.get("message", "")
                progress_text = f"{title} - {message}".strip(" -")
                if progress_text:
                    print(f"    [Progress] {progress_text} (elapsed: {elapsed:.2f}s)")
                if kind == "end" and ("build" in title.lower() or "compile" in title.lower() or "indexing" in title.lower()):
                    # Sometimes progress end happens slightly after or before ServiceReady
                    pass

    except KeyboardInterrupt:
        print("\n[-] Aborted by user.")
    finally:
        print("[*] Terminating JDTLS...")
        proc.terminate()
        proc.wait()
        # Clean up temp workspace
        shutil.rmtree(temp_dir)
        print("[*] Temporary workspace cleaned up.")

if __name__ == "__main__":
    main()
