#!/bin/sh
# Generate a PDF of the CV page (cv.html) into artifacts/cv.pdf.
# Run this any time you want an up-to-date CV PDF, e.g. before an
# interview. Re-run freely -- it overwrites artifacts/cv.pdf each time.
#
# Requires Ruby matching .ruby-version (see script/verify.sh for why),
# Google Chrome installed at the standard macOS path, and python3/curl
# on PATH (both ship with macOS).
set -e
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="artifacts/cv.pdf"
PORT=4173

want_ruby="$(cat .ruby-version)"
have_ruby="$(ruby -e 'print RUBY_VERSION')"
if [ "$have_ruby" != "$want_ruby" ]; then
  echo "warning: active Ruby is $have_ruby, .ruby-version wants $want_ruby" >&2
  echo "         the build may fail on a Ruby this project isn't pinned to." >&2
fi

if [ ! -x "$CHROME" ]; then
  echo "error: Google Chrome not found at: $CHROME" >&2
  echo "       install it, or edit CHROME= in this script to match your setup." >&2
  exit 1
fi

echo "==> bundle install"
bundle check >/dev/null 2>&1 || bundle install

echo "==> jekyll build"
bundle exec jekyll build --strict_front_matter

server_pid=""
chrome_profile=""
cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" >/dev/null 2>&1
  if [ -n "$chrome_profile" ]; then
    # Chrome forks helper/renderer processes that inherit --user-data-dir
    # in their own argv but aren't children of the PID we captured, so
    # killing that one PID alone can leave them running (and racing our
    # rm -rf). Match on the unique profile path instead.
    pkill -f "$chrome_profile" >/dev/null 2>&1 || true
    sleep 0.3
    rm -rf "$chrome_profile"
  fi
}
trap cleanup EXIT INT TERM

echo "==> serving ./_site on 127.0.0.1:$PORT"
(cd _site && exec python3 -m http.server "$PORT" >/dev/null 2>&1) &
server_pid=$!

tries=0
until curl -sf "http://127.0.0.1:$PORT/cv.html" >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then
    echo "error: local server never came up on port $PORT" >&2
    exit 1
  fi
  sleep 0.2
done

echo "==> rendering cv.html to $OUT"
mkdir -p artifacts
rm -f "$OUT"
chrome_profile="$(mktemp -d)"
"$CHROME" \
  --headless --disable-gpu --no-sandbox \
  --user-data-dir="$chrome_profile" \
  --no-pdf-header-footer \
  --print-to-pdf="$OUT" \
  "http://127.0.0.1:$PORT/cv.html" >/dev/null 2>&1 &

tries=0
until [ -s "$OUT" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 50 ]; then
    echo "error: $OUT was never produced (Chrome timed out or failed)" >&2
    exit 1
  fi
  sleep 0.2
done
# Chrome may keep running briefly after the PDF is fully written; the
# EXIT trap (cleanup) tears it down along with its profile dir below.

if command -v pdfinfo >/dev/null 2>&1; then
  pages="$(pdfinfo "$OUT" 2>/dev/null | awk '/^Pages:/ {print $2}')"
  echo "==> $OUT: $pages page(s)"
else
  echo "==> $OUT generated (install poppler's pdfinfo to see page count here)"
fi

echo "==> OK"
