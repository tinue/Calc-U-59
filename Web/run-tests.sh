#!/usr/bin/env bash
# Run the web client's Playwright tests against Web/dist/ (build it first:
# Web/build.sh). Two HTTP servers: one serves dist/ at its root, the other
# only under /anything/calc/ (everything else is a 404) — the sub-path that
# proves the client is location-independent.
set -euo pipefail

WEB="$(cd "$(dirname "$0")" && pwd)"
DIST="$WEB/dist"
export CALCU_WEB_PORT="${CALCU_WEB_PORT:-8059}"
SUBPATH_PORT=$((CALCU_WEB_PORT + 1))

if [ ! -f "$DIST/MANIFEST.json" ]; then
  echo "error: $DIST is not built. Run Web/build.sh first." >&2
  exit 1
fi
for port in "$CALCU_WEB_PORT" "$SUBPATH_PORT"; do
  if lsof -ti:"$port" > /dev/null 2>&1; then
    echo "error: port $port is in use (set CALCU_WEB_PORT)." >&2
    exit 1
  fi
done

# http.server with a larger listen backlog: the default of 5 resets
# connections when parallel test pages each fetch the calculator's ROM files.
serve() {  # serve <port> <prefix>
  python3 - "$DIST" "$1" "$2" <<'PY' &
import functools, http.server, sys
PREFIX = sys.argv[3]
class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        if PREFIX:
            if not path.startswith(PREFIX + "/"):
                return "/nonexistent"
            path = path[len(PREFIX):]
        return super().translate_path(path)
    def log_message(self, *args):
        pass
class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128
Server(("", int(sys.argv[2])), functools.partial(Handler, directory=sys.argv[1])).serve_forever()
PY
  PIDS+=($!)
}
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT
serve "$CALCU_WEB_PORT" ""
serve "$SUBPATH_PORT" "/anything/calc"
sleep 1

cd "$WEB"
npm install --no-audit --no-fund
npx playwright install chromium
npx playwright test "$@"
