#!/usr/bin/env bash
#
# convert.sh — Convert a PDF to flipbook page images
#
# Usage: ./site/convert.sh <pdf-file> <slug> [dpi]
#
# Example: ./site/convert.sh slides/my-talk.pdf my-talk 200
#
# Requires: pdftoppm (from Poppler) and pdftotext (optional, for search)
#   macOS:   brew install poppler
#   Ubuntu:  sudo apt install poppler-utils
#   Windows: install poppler and add to PATH (or use WSL)
#
# Output goes to site/flipbooks/<slug>/

set -euo pipefail

# Find Python ($PYTHON on macOS/Linux, python on Windows)
PYTHON=""
for cmd in $PYTHON python; do
    if command -v "$cmd" &>/dev/null && "$cmd" -c "import json" 2>/dev/null; then
        PYTHON="$cmd"
        break
    fi
done

PDF="$1"
SLUG="$2"
DPI="${3:-200}"
THUMB_DPI=72

if [ -z "$PDF" ] || [ -z "$SLUG" ]; then
    echo "Usage: $0 <pdf-file> <slug> [dpi]"
    echo "  pdf-file  Path to the PDF file"
    echo "  slug      URL-friendly name (e.g. my-talk)"
    echo "  dpi       Render quality (default: 200)"
    exit 1
fi

if ! command -v pdftoppm &>/dev/null; then
    echo "Error: pdftoppm not found. Install Poppler:"
    echo "  macOS:   brew install poppler"
    echo "  Ubuntu:  sudo apt install poppler-utils"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/flipbooks/$SLUG"
PAGES_DIR="$OUT_DIR/pages"
THUMBS_DIR="$OUT_DIR/thumbs"

mkdir -p "$PAGES_DIR" "$THUMBS_DIR"

echo "Converting $PDF → $SLUG (${DPI} DPI)..."

# Render full-size pages
pdftoppm -png -r "$DPI" "$PDF" "$PAGES_DIR/page"

# Render thumbnails
pdftoppm -png -r "$THUMB_DPI" "$PDF" "$THUMBS_DIR/page"

# Count pages
PAGE_COUNT=$(ls "$PAGES_DIR"/page-*.png 2>/dev/null | wc -l | tr -d ' ')

if [ "$PAGE_COUNT" -eq 0 ]; then
    echo "Error: No pages rendered. Is the PDF valid?"
    exit 1
fi

# Detect page dimensions from first PNG header (bytes 16-23 contain width/height)
FIRST_PAGE=$(ls "$PAGES_DIR"/page-*.png | head -1)
if command -v identify &>/dev/null; then
    DIMS=$(identify -format "%w %h" "$FIRST_PAGE")
    PAGE_WIDTH=$(echo "$DIMS" | awk '{print $1}')
    PAGE_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
else
    # Read PNG IHDR chunk directly — width at offset 16, height at offset 20 (4 bytes each, big-endian)
    PAGE_WIDTH=$(od -A n -t u4 -j 16 -N 4 --endian=big "$FIRST_PAGE" 2>/dev/null | tr -d ' ')
    PAGE_HEIGHT=$(od -A n -t u4 -j 20 -N 4 --endian=big "$FIRST_PAGE" 2>/dev/null | tr -d ' ')
    if [ -z "$PAGE_WIDTH" ] || [ -z "$PAGE_HEIGHT" ]; then
        echo "Warning: Cannot detect page dimensions. Using defaults (1920x1080)."
        echo "Edit site/flipbooks/$SLUG/config.json to correct."
        PAGE_WIDTH=1920
        PAGE_HEIGHT=1080
    fi
fi

# Detect naming format (page-1.png vs page-01.png vs page-001.png)
FIRST_NAME=$(basename "$FIRST_PAGE")
if [[ "$FIRST_NAME" =~ page-0*1\.png ]]; then
    # Count zero-padding length
    NUM_PART="${FIRST_NAME#page-}"
    NUM_PART="${NUM_PART%.png}"
    PAD_LEN=${#NUM_PART}
else
    PAD_LEN=1
fi

# Extract text for search (optional)
PAGE_TEXTS="[]"
if command -v pdftotext &>/dev/null && [ -n "$PYTHON" ]; then
    echo "Extracting text for search..."
    FULL_TEXT=$(pdftotext -layout "$PDF" - 2>/dev/null || true)
    if [ -n "$FULL_TEXT" ]; then
        PAGE_TEXTS=$($PYTHON -c "
import json, sys
text = sys.stdin.read()
pages = text.split('\f')
pages = pages[:$PAGE_COUNT]
while len(pages) < $PAGE_COUNT:
    pages.append('')
pages = [p.strip() for p in pages]
print(json.dumps(pages))
" <<< "$FULL_TEXT" 2>/dev/null || echo "[]")
    fi
fi

# Build page URL lists
PAGES_JSON="["
THUMBS_JSON="["
for i in $(seq 1 "$PAGE_COUNT"); do
    PADDED=$(printf "%0${PAD_LEN}d" "$i")
    [ "$i" -gt 1 ] && PAGES_JSON+=","
    [ "$i" -gt 1 ] && THUMBS_JSON+=","
    PAGES_JSON+="\"pages/page-${PADDED}.png\""
    THUMBS_JSON+="\"thumbs/page-${PADDED}.png\""
done
PAGES_JSON+="]"
THUMBS_JSON+="]"

# Write config
cat > "$OUT_DIR/config.json" <<CONF
{
    "title": "$SLUG",
    "slug": "$SLUG",
    "pageCount": $PAGE_COUNT,
    "pageWidth": $PAGE_WIDTH,
    "pageHeight": $PAGE_HEIGHT,
    "pages": $PAGES_JSON,
    "thumbs": $THUMBS_JSON,
    "pageTexts": $PAGE_TEXTS
}
CONF

echo ""
echo "Done! $PAGE_COUNT pages rendered to site/flipbooks/$SLUG/"
echo ""
echo "Next steps:"
echo "  1. Edit site/flipbooks/$SLUG/config.json to set the title"
echo "  2. Run: bash site/build.sh"
echo "  3. Deploy: vercel --prod (or push to GitHub)"
