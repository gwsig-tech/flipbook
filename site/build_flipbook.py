"""Generate static HTML viewer and embed pages for a flipbook.

Usage: python build_flipbook.py <config.json> <public_dir> <template_dir>

Reads config.json and writes:
  - <public_dir>/v/<slug>/index.html
  - <public_dir>/embed/<slug>/index.html
  - Copies pages/ and thumbs/ to <public_dir>/flipbooks/<slug>/

Prints a single line of shell variables for the index page:
  SLUG, TITLE_HTML, PAGE_COUNT, FIRST_THUMB
"""
import json, sys, os, html, shutil

config_path = sys.argv[1]
public_dir = sys.argv[2]

with open(config_path) as f:
    c = json.load(f)

slug = c['slug']
title = c['title']
title_html = html.escape(title)
page_count = c['pageCount']
page_width = c['pageWidth']
page_height = c['pageHeight']
pages = c['pages']
thumbs = c['thumbs']
texts = c.get('pageTexts', [])

pages_urls = ['/flipbooks/' + slug + '/' + p for p in pages]
thumbs_urls = ['/flipbooks/' + slug + '/' + t for t in thumbs]
first_page = pages[0] if pages else ''
og_image = '/flipbooks/%s/%s' % (slug, first_page)

desc = ' '.join(texts[:3]).strip()[:200] if texts else title_html
desc = desc.replace('"', '&quot;').replace('\n', ' ')

first_thumb = thumbs[0].split('/')[-1] if thumbs else ''

# The FLIPBOOK_DATA JSON block (safe — no bash expansion)
data_block = """    <script>
        window.FLIPBOOK_DATA = {
            id: %s,
            title: %s,
            slug: %s,
            baseURL: "",
            pageCount: %d,
            pageWidth: %d,
            pageHeight: %d,
            pages: %s,
            thumbs: %s,
            pageTexts: %s
        };
    </script>""" % (
    json.dumps(slug),
    json.dumps(title),
    json.dumps(slug),
    page_count, page_width, page_height,
    json.dumps(pages_urls),
    json.dumps(thumbs_urls),
    json.dumps(texts),
)

# Shared HTML body (controls, modals, overlays)
BODY_HTML = """    <div id="viewer-wrapper">
        <div id="landscape-hint">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="10" rx="2"/><line x1="12" y1="17" x2="12" y2="21"/><line x1="8" y1="21" x2="16" y2="21"/></svg>
            Rotate for best viewing experience
        </div>
        <div id="flipbook-container">
            <button class="nav-overlay" id="nav-prev" aria-label="Previous page">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            </button>
            <div id="flipbook"></div>
            <button class="nav-overlay" id="nav-next" aria-label="Next page">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
            </button>
        </div>
        <div id="controls">
            <button id="btn-prev" title="Previous page (Left Arrow)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            </button>
            <span id="page-indicator">
                <span id="current-page">1</span> / <span id="total-pages">%d</span>
            </span>
            <button id="btn-next" title="Next page (Right Arrow)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
            </button>
            <div id="page-slider-container">
                <input type="range" id="page-slider" min="1" max="%d" value="1">
            </div>
            <div class="controls-spacer"></div>
            <button id="btn-search" title="Search (Ctrl+F)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
            </button>
            <button id="btn-grid" title="Grid view (G)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
            </button>
            <button id="btn-fullscreen" title="Fullscreen (F)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>
            </button>
            <button id="btn-share" title="Share / Embed">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
            </button>
        </div>
        <div id="attribution">
            Created with <a href="https://metavert.io/flipbook" target="_blank">Flipbook</a>
        </div>
        <div id="share-modal" class="modal hidden">
            <div class="modal-overlay" onclick="closeShareModal()"></div>
            <div class="modal-content">
                <h3>Share this flipbook</h3>
                <div class="form-group share-page-option">
                    <label class="checkbox-label">
                        <input type="checkbox" id="share-from-page"> Share from current page (<span id="share-page-num">1</span>)
                    </label>
                </div>
                <div class="form-group">
                    <label>Link</label>
                    <div class="copy-field">
                        <input type="text" readonly id="share-link">
                        <button onclick="copyField('share-link')">Copy</button>
                    </div>
                </div>
                <div class="form-group">
                    <label>Embed code</label>
                    <div class="copy-field">
                        <textarea readonly id="embed-code" rows="3"></textarea>
                        <button onclick="copyField('embed-code')">Copy</button>
                    </div>
                </div>
                <button class="btn-close" onclick="closeShareModal()">Close</button>
            </div>
        </div>
        <div id="search-bar" class="hidden">
            <div id="search-bar-inner">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="search-icon"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <input type="text" id="search-input" placeholder="Search in slides..." autocomplete="off">
                <span id="search-status"></span>
                <button id="search-prev" title="Previous match" disabled>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
                </button>
                <button id="search-next" title="Next match" disabled>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
                </button>
                <button id="search-close" title="Close search">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
            </div>
        </div>
        <div id="grid-overlay" class="hidden">
            <div id="grid-header">
                <h3>All Pages</h3>
                <button id="btn-grid-close" title="Close grid">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
            </div>
            <div id="grid-container"></div>
        </div>
    </div>""" % (page_count, page_count)

SCRIPTS = """    <script src="/static/js/page-flip.browser.js"></script>
    <script src="/static/js/viewer.js"></script>"""

# --- Viewer page (with SEO) ---
viewer_html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <link rel="icon" type="image/svg+xml" href="/static/img/favicon.svg">
    <meta name="description" content="%s">
    <link rel="canonical" href="/v/%s">
    <meta property="og:title" content="%s">
    <meta property="og:description" content="%s">
    <meta property="og:type" content="article">
    <meta property="og:url" content="/v/%s">
    <meta property="og:image" content="%s">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="%s">
    <meta name="twitter:description" content="%s">
    <meta name="twitter:image" content="%s">
    <link rel="stylesheet" href="/static/css/viewer.css">
</head>
<body>
%s
%s
%s
</body>
</html>""" % (
    title_html, desc, slug,
    title_html, desc, slug, og_image,
    title_html, desc, og_image,
    BODY_HTML, data_block, SCRIPTS,
)

# --- Embed page (no SEO, iframe-friendly) ---
embed_html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <link rel="icon" type="image/svg+xml" href="/static/img/favicon.svg">
    <link rel="stylesheet" href="/static/css/viewer.css">
    <style>
        body { margin: 0; overflow: hidden; }
        #viewer-wrapper { height: 100vh; }
        #controls { border-radius: 0; }
    </style>
</head>
<body>
%s
%s
%s
</body>
</html>""" % (title_html, BODY_HTML, data_block, SCRIPTS)

# Write viewer
viewer_dir = os.path.join(public_dir, 'v', slug)
os.makedirs(viewer_dir, exist_ok=True)
with open(os.path.join(viewer_dir, 'index.html'), 'w', encoding='utf-8') as f:
    f.write(viewer_html)

# Write embed
embed_dir = os.path.join(public_dir, 'embed', slug)
os.makedirs(embed_dir, exist_ok=True)
with open(os.path.join(embed_dir, 'index.html'), 'w', encoding='utf-8') as f:
    f.write(embed_html)

# Copy images
flipbook_dir = os.path.join(public_dir, 'flipbooks', slug)
os.makedirs(flipbook_dir, exist_ok=True)
src_dir = os.path.dirname(config_path)
for sub in ('pages', 'thumbs'):
    dst = os.path.join(flipbook_dir, sub)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(os.path.join(src_dir, sub), dst)

# Output shell vars for index page (safe values only — no user text)
print('SLUG="%s" TITLE_HTML="%s" PAGE_COUNT=%d FIRST_THUMB="%s"' % (
    slug, title_html.replace('"', '\\"'), page_count, first_thumb))
