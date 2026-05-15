#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="$(cd "$SCRIPT_DIR/../docs" && pwd)"
PORT=8000
SERVER_PID=""

# Start a server if port 8000 is not already in use
if ! lsof -ti:$PORT > /dev/null 2>&1; then
  echo "Starting HTTP server on port $PORT serving $DOCS_DIR..."
  python3 -m http.server $PORT --directory "$DOCS_DIR" &
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
