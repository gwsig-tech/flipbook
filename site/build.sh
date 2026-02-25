#!/usr/bin/env bash
#
# build.sh — Assemble the static flipbook site into site/public/
#
# Usage: bash site/build.sh
#
# Reads each site/flipbooks/<slug>/config.json and generates:
#   - /v/<slug>/index.html   (viewer page)
#   - /embed/<slug>/index.html (iframe embed page)
#   - /index.html            (listing page)
#
# All static assets (JS, CSS, images) are copied to public/.

set -euo pipefail

# Find Python
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null && "$cmd" -c "import json" 2>/dev/null; then
        PYTHON="$cmd"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "Error: Python not found. Install Python 3."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC="$SCRIPT_DIR/public"
FLIPBOOKS_DIR="$SCRIPT_DIR/flipbooks"

# Clean and create output
rm -rf "$PUBLIC"
mkdir -p "$PUBLIC/static/js" "$PUBLIC/static/css" "$PUBLIC/static/img"

# Copy static assets from the existing web/ directory
WEB_DIR="$SCRIPT_DIR/../web/static"
cp "$WEB_DIR/js/page-flip.browser.js" "$PUBLIC/static/js/"
cp "$WEB_DIR/js/viewer.js" "$PUBLIC/static/js/"
cp "$WEB_DIR/css/viewer.css" "$PUBLIC/static/css/"
cp "$WEB_DIR/img/favicon.svg" "$PUBLIC/static/img/"

# Collect flipbook entries for the index page
INDEX_ENTRIES=""
FLIPBOOK_COUNT=0

# Process each flipbook — Python generates the HTML files and outputs index metadata
for CONFIG in "$FLIPBOOKS_DIR"/*/config.json; do
    [ -f "$CONFIG" ] || continue

    SLUG=$(basename "$(dirname "$CONFIG")")
    echo "Building $SLUG..."

    # Python generates viewer + embed HTML, copies images, prints index vars
    eval "$($PYTHON "$SCRIPT_DIR/build_flipbook.py" "$CONFIG" "$PUBLIC")"

    # Build index entry (SLUG, TITLE_HTML, PAGE_COUNT, FIRST_THUMB set by Python)
    INDEX_ENTRIES+="<a href=\"/v/${SLUG}\" class=\"flipbook-card\">"
    INDEX_ENTRIES+="<img src=\"/flipbooks/${SLUG}/thumbs/${FIRST_THUMB}\" alt=\"${TITLE_HTML}\" loading=\"lazy\">"
    INDEX_ENTRIES+="<div class=\"card-info\"><h2>${TITLE_HTML}</h2><p>${PAGE_COUNT} pages</p></div>"
    INDEX_ENTRIES+="</a>"

    FLIPBOOK_COUNT=$((FLIPBOOK_COUNT + 1))
done

# Generate index page
cat > "$PUBLIC/index.html" <<'INDEX_TOP'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flipbooks</title>
    <link rel="icon" type="image/svg+xml" href="/static/img/favicon.svg">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #1a1a2e;
            color: #fff;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            min-height: 100vh;
        }
        header {
            text-align: center;
            padding: 40px 20px 30px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        header h1 { font-size: 28px; font-weight: 600; }
        header p { color: rgba(255,255,255,0.5); margin-top: 8px; font-size: 14px; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 24px;
            padding: 32px 24px;
            max-width: 1200px;
            margin: 0 auto;
        }
        .flipbook-card {
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 12px;
            overflow: hidden;
            text-decoration: none;
            color: #fff;
            transition: transform 0.2s, border-color 0.2s;
        }
        .flipbook-card:hover {
            transform: translateY(-4px);
            border-color: rgba(99,102,241,0.5);
        }
        .flipbook-card img {
            width: 100%;
            aspect-ratio: 16/9;
            object-fit: cover;
            background: #fff;
        }
        .card-info {
            padding: 16px;
        }
        .card-info h2 { font-size: 16px; font-weight: 500; }
        .card-info p { font-size: 13px; color: rgba(255,255,255,0.5); margin-top: 4px; }
    </style>
</head>
<body>
    <header>
        <h1>Flipbooks</h1>
INDEX_TOP

# Insert dynamic count and entries
PLURAL=""
[ "$FLIPBOOK_COUNT" -ne 1 ] && PLURAL="s"
echo "        <p>${FLIPBOOK_COUNT} presentation${PLURAL}</p>" >> "$PUBLIC/index.html"
echo "    </header>" >> "$PUBLIC/index.html"
echo "    <div class=\"grid\">" >> "$PUBLIC/index.html"
echo "        ${INDEX_ENTRIES}" >> "$PUBLIC/index.html"

cat >> "$PUBLIC/index.html" <<'INDEX_BOTTOM'
    </div>
</body>
</html>
INDEX_BOTTOM

echo ""
echo "Built $FLIPBOOK_COUNT flipbook(s) -> site/public/"
echo ""
echo "To preview locally:  npx serve site/public"
echo "To deploy:           vercel site/public --prod"
