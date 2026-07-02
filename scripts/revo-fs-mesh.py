#!/usr/bin/env python3
"""
revo-fs-mesh.py — Package Mesh DHT Peer Discovery v1.4.0

Maintains a distributed hash table of package peers for the revo-fs
package streaming network. Each Revo OS node that caches a package
announces itself as a peer, enabling BitTorrent-style P2P distribution.

Architecture:
  - DHT (Kademlia-style): SHA-256(package_name:version) → peer list
  - Bootstrap nodes: hardcoded registry URLs for initial join
  - Peer scoring: track latency + reliability, prefer faster peers
  - NAT traversal: UDP hole punching via STUN (future)

This script runs as a lightweight background service on each node.
In v1.4.0, the DHT is simulated via HTTP registry (no UDP stack needed
in the minimal initramfs). Full UDP DHT planned for v1.5.

Usage:
  python3 revo-fs-mesh.py announce <name> <version> <port>
  python3 revo-fs-mesh.py discover <name>
  python3 revo-fs-mesh.py peers
  python3 revo-fs-mesh.py daemon
"""

import sys
import os
import json
import time
import hashlib
import urllib.request
import urllib.parse
from pathlib import Path

VERSION = "1.4.0"
MESH_DIR = Path(os.environ.get("MESH_STATE", "/revo/pkgs/mesh"))
REGISTRY = os.environ.get("MESH_BOOTSTRAP", "https://revo-pkgs.nousresearch.com")
MESH_PORT = int(os.environ.get("MESH_PORT", "6881"))

# ─── DHT Utilities ───

def infohash(name: str, version: str = "latest") -> str:
    """SHA-256 hash of package identity (Kademlia-style)."""
    data = f"revo-pkg:{name}:{version}".encode()
    return hashlib.sha256(data).hexdigest()[:40]

def api_get(path: str, params: dict = None) -> dict:
    """GET request to the mesh registry."""
    url = f"{REGISTRY}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def api_post(path: str, data: dict) -> dict:
    """POST request to the mesh registry."""
    url = f"{REGISTRY}{path}"
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

# ─── Commands ───

def cmd_announce(name: str, version: str, port: int = MESH_PORT) -> None:
    """Announce this node as a peer for a package."""
    ih = infohash(name, version)
    result = api_post("/api/v1/announce", {
        "infohash": ih,
        "name": name,
        "version": version,
        "port": port,
    })
    
    if "error" in result:
        print(f"Announce failed: {result['error']}")
    else:
        print(f"Announced: {name}-{version} (infohash: {ih[:12]}...)")
        print(f"Peers online: {result.get('peer_count', '?')}")

def cmd_discover(name: str) -> None:
    """Discover peers for a package."""
    result = api_get("/api/v1/peers", {"name": name})
    
    if "error" in result:
        print(f"Discovery failed: {result['error']}")
        return
    
    peers = result.get("peers", [])
    if not peers:
        print(f"No peers found for '{name}'")
        return
    
    # Save peers to local state
    peers_file = MESH_DIR / f"{name}.peers"
    peers_file.parent.mkdir(parents=True, exist_ok=True)
    with open(peers_file, "w") as f:
        for peer in peers:
            f.write(f"{peer}\n")
    
    print(f"Found {len(peers)} peers for '{name}':")
    for peer in peers[:10]:  # Show first 10
        print(f"  {peer}")
    if len(peers) > 10:
        print(f"  ... and {len(peers) - 10} more")

def cmd_peers() -> None:
    """List all known peers in the local mesh state."""
    peers_files = list(MESH_DIR.glob("*.peers"))
    
    if not peers_files:
        print("No peers cached locally.")
        print("Run 'discover <package>' to find peers.")
        return
    
    for pf in peers_files:
        name = pf.stem
        with open(pf) as f:
            lines = [l.strip() for l in f if l.strip()]
        print(f"{name}: {len(lines)} peers")
        for line in lines[:3]:
            print(f"  {line}")
        if len(lines) > 3:
            print(f"  ... and {len(lines) - 3} more")

def cmd_search(query: str) -> None:
    """Search the package registry."""
    result = api_get("/api/v1/search", {"q": query})
    
    if "error" in result:
        print(f"Search failed: {result['error']}")
        return
    
    packages = result.get("packages", [])
    if not packages:
        print(f"No packages found for '{query}'")
        return
    
    print(f"Packages matching '{query}':")
    for pkg in packages:
        name = pkg.get("name", "?")
        version = pkg.get("version", "?")
        desc = pkg.get("description", "")
        size = pkg.get("size_mb", "?")
        print(f"  {name} v{version}  ({size} MB)")
        if desc:
            print(f"    {desc}")

def cmd_daemon() -> None:
    """Run as a background daemon — periodically refresh peer lists."""
    print(f"revo-fs-mesh v{VERSION} daemon starting...")
    print(f"Registry: {REGISTRY}")
    print(f"Port:     {MESH_PORT}")
    
    # Discover peers for all known packages on startup
    for meta_file in MESH_DIR.parent.glob("db/*/meta"):
        pkg_name = meta_file.parent.name
        print(f"Discovering peers for: {pkg_name}")
        cmd_discover(pkg_name)
    
    # Periodic refresh loop
    refresh_interval = 300  # 5 minutes
    while True:
        time.sleep(refresh_interval)
        for meta_file in MESH_DIR.parent.glob("db/*/meta"):
            pkg_name = meta_file.parent.name
            cmd_discover(pkg_name)

# ─── Main ───

def main():
    if len(sys.argv) < 2:
        print(f"revo-fs-mesh v{VERSION} — Package Mesh DHT Peer Discovery")
        print(f"")
        print(f"Usage:")
        print(f"  {sys.argv[0]} announce <name> <version> [port]")
        print(f"  {sys.argv[0]} discover <name>")
        print(f"  {sys.argv[0]} search <query>")
        print(f"  {sys.argv[0]} peers")
        print(f"  {sys.argv[0]} daemon")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "announce":
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        version = sys.argv[3] if len(sys.argv) > 3 else "latest"
        port = int(sys.argv[4]) if len(sys.argv) > 4 else MESH_PORT
        cmd_announce(name, version, port)
    elif cmd == "discover":
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        cmd_discover(name)
    elif cmd == "search":
        query = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        cmd_search(query)
    elif cmd == "peers":
        cmd_peers()
    elif cmd == "daemon":
        cmd_daemon()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()
