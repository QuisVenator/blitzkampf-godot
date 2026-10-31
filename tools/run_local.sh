#!/usr/bin/env bash
# Start a host plus N clients (default 1) on this machine, in small windows side by
# side, to try multiplayer by hand. Only the focused window receives input.
#   tools/run_local.sh        host + 1 client
#   tools/run_local.sh 2      host + 2 clients
# Ctrl+C stops everything. Pass the host's LAN address to another machine with:
#   godot --path . -- --join=<address>
set -euo pipefail
cd "$(dirname "$0")/.."

clients="${1:-1}"
port="${PORT:-7777}"
godot="${GODOT:-godot}"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT INT TERM

"$godot" --path . --resolution 640x360 --position 0,0 -- --host --port="$port" &
pids+=($!)
sleep 2
for ((i = 0; i < clients; i++)); do
	"$godot" --path . --resolution 640x360 --position $(((i + 1) * 660)),0 -- --join=127.0.0.1 --port="$port" &
	pids+=($!)
	sleep 0.5
done
wait
