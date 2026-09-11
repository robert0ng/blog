#!/bin/sh
# Generate a professionally-typeset PDF of the CV into artifacts/cv.pdf,
# straight from _data/cv.json -- no Jekyll build, no browser involved.
# Run this any time you want an up-to-date CV PDF, e.g. before an
# interview. Re-run freely -- it overwrites artifacts/cv.pdf each time.
#
# Requires RenderCV (https://rendercv.com), a Python/Typst-based CV
# typesetter -- much more professional output than printing the site's
# own cv.html page (the previous approach). One-time setup:
#   pipx install "rendercv[full]"
#   pipx inject rendercv pyyaml   # needed by cv_to_rendercv.py
set -e
cd "$(dirname "$0")/.."

OUT="artifacts/cv.pdf"
CONVERTER="artifacts/cv_to_rendercv.py"
GENERATED_YAML="artifacts/.cv-rendercv.yaml"
RENDER_OUTPUT_DIR="artifacts/.rendercv_output"

if ! command -v rendercv >/dev/null 2>&1; then
  echo "error: rendercv not found on PATH." >&2
  echo "       install it with: pipx install \"rendercv[full]\"" >&2
  exit 1
fi

# cv_to_rendercv.py needs PyYAML. RenderCV itself is installed in its own
# pipx-managed virtualenv; reuse that same interpreter (found via the
# rendercv shim script's shebang line) rather than requiring a second,
# separate Python environment just for one dependency.
RENDERCV_PYTHON="$(head -1 "$(command -v rendercv)" | sed 's/^#!//' | awk '{print $1}')"
if [ ! -x "$RENDERCV_PYTHON" ]; then
  echo "error: could not resolve rendercv's own Python interpreter from its shim script." >&2
  echo "       expected a shebang line like '#!/path/to/venv/bin/python' in: $(command -v rendercv)" >&2
  exit 1
fi
if ! "$RENDERCV_PYTHON" -c 'import yaml' >/dev/null 2>&1; then
  echo "error: PyYAML not installed in rendercv's virtualenv." >&2
  echo "       install it with: pipx inject rendercv pyyaml" >&2
  exit 1
fi

echo "==> converting _data/cv.json to RenderCV's YAML schema"
mkdir -p artifacts
"$RENDERCV_PYTHON" "$CONVERTER" _data/cv.json "$GENERATED_YAML"

echo "==> rendering with RenderCV"
rm -rf "$RENDER_OUTPUT_DIR"
# --output-folder is resolved relative to the YAML file's own directory
# (artifacts/), not the cwd -- pass just the basename to land at
# artifacts/.rendercv_output, not artifacts/artifacts/.rendercv_output.
rendercv render "$GENERATED_YAML" --output-folder "$(basename "$RENDER_OUTPUT_DIR")" >/dev/null

generated_pdf="$(find "$RENDER_OUTPUT_DIR" -maxdepth 1 -name '*.pdf' | head -1)"
if [ -z "$generated_pdf" ]; then
  echo "error: RenderCV did not produce a PDF in $RENDER_OUTPUT_DIR" >&2
  exit 1
fi
mv "$generated_pdf" "$OUT"
rm -rf "$RENDER_OUTPUT_DIR" "$GENERATED_YAML"

if command -v pdfinfo >/dev/null 2>&1; then
  pages="$(pdfinfo "$OUT" 2>/dev/null | awk '/^Pages:/ {print $2}')"
  echo "==> $OUT: $pages page(s)"
else
  echo "==> $OUT generated (install poppler's pdfinfo to see page count here)"
fi

echo "==> OK"
