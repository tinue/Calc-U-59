#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="$(cd "$SCRIPT_DIR/../docs" && pwd)"
PORT=8000
SERVER_PID=""

# Start a server if port 8000 is not already in use
if ! lsof -ti:$PORT > /dev/null 2>&1; then
  echo "Starting HTTP server on port $PORT serving $DOCS_DIR..."
  # http.server with a larger listen backlog: the default of 5 resets
  # connections when parallel test pages each fetch the calculator's ROM files.
  python3 - "$DOCS_DIR" "$PORT" <<'PY' &
import functools, http.server, sys
class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
Server(("", int(sys.argv[2])), handler).serve_forever()
PY
  SERVER_PID=$!
  trap 'echo "Stopping server..."; kill "$SERVER_PID" 2>/dev/null' EXIT
  sleep 1   # give the server a moment to start
else
  echo "Port $PORT already in use — using existing server."
fi

cd "$SCRIPT_DIR"

echo "Installing npm dependencies..."
npm install

echo "Installing Playwright browsers..."
npx playwright install chromium

echo "Running tests..."
npx playwright test "$@"
