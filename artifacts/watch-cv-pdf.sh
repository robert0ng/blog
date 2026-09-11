#!/bin/sh
# Watch _data/cv.json and regenerate artifacts/robert-wang-cv.pdf every
# time it changes (on save). Ctrl-C to stop.
#
# Uses a simple mtime-polling loop rather than fswatch/inotify -- no
# extra dependency to install, works the same everywhere. Polls every
# second, which is plenty responsive for "regenerate after I save a
# file in my editor."
set -e
cd "$(dirname "$0")/.."

CV_JSON="_data/cv.json"
GENERATE="artifacts/generate-cv-pdf.sh"

last_mtime=""
echo "==> watching $CV_JSON for changes (Ctrl-C to stop)"

while true; do
  mtime="$(stat -f %m "$CV_JSON" 2>/dev/null || stat -c %Y "$CV_JSON" 2>/dev/null)"
  if [ "$mtime" != "$last_mtime" ]; then
    if [ -n "$last_mtime" ]; then
      echo "==> $CV_JSON changed, regenerating..."
      if sh "$GENERATE"; then
        echo "==> done, watching again"
      else
        echo "==> generate-cv-pdf.sh failed -- fix the error above, still watching" >&2
      fi
    fi
    last_mtime="$mtime"
  fi
  sleep 1
done
