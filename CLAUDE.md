# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flipbook is a self-hosted Go application that converts PowerPoint (.pptx/.ppt) and PDF files into interactive 3D page-curl flipbooks. It features SEO-optimized viewers, embeddable iframes, a REST API, and an MCP server for AI agent integration.

It also supports a **static site mode** where PDFs are converted locally and the viewer is deployed to Vercel (or any static host) with no server, database, or backend required.

## Build & Run Commands

**Server mode (full app):**
```bash
make build          # Compile Go binary to bin/flipbook
make run            # Build and run the server
make setup          # Download vendored StPageFlip JS library
make check-deps     # Verify LibreOffice and Poppler are installed
make set-password   # Set admin password interactively
make deploy         # Deploy to Fly.io
make clean          # Remove bin/ directory
```

**CLI subcommands:**
```bash
bin/flipbook                    # Start web server
bin/flipbook set-password       # Set admin password
bin/flipbook backfill-gridfs    # Backup originals to MongoDB GridFS
bin/flipbook mcp                # Start MCP JSON-RPC server (stdio)
```

**Static site mode (Vercel/Netlify):**
```bash
bash site/convert.sh <pdf> <slug> [dpi]   # Convert PDF → PNGs locally
bash site/build.sh                         # Build static site → site/public/
npx serve site/public                      # Preview locally
vercel --prod                              # Deploy to Vercel
```

**System dependencies:**
- Server mode: Go 1.21+, LibreOffice (headless, for PPTX→PDF), Poppler (pdftoppm/pdftotext), MongoDB
- Static site mode: Poppler (pdftoppm/pdftotext), Python 3

## Architecture

**Entry point:** `main.go` — CLI dispatch, config loading, MongoDB connection, HTTP route registration, and graceful shutdown.

**Key internal packages:**

| Package | Purpose |
|---------|---------|
| `internal/config` | YAML config with env var overrides (priority: env > config.dev.yaml > config.yaml) |
| `internal/auth` | bcrypt password verification, HMAC-SHA256 session cookies (7-day TTL) |
| `internal/converter` | Three-step pipeline: LibreOffice (PPTX→PDF) → pdftoppm (PDF→PNG at 300/72 DPI) → pdftotext (text extraction) |
| `internal/database` | MongoDB CRUD, GridFS file backup, session management, view tracking |
| `internal/handlers/admin` | Server-rendered admin dashboard (Go templates) |
| `internal/handlers/api` | JSON REST API with bearer token auth |
| `internal/handlers/viewer` | Public viewer with SEO (Open Graph, Twitter Cards, JSON-LD, hidden page text) |
| `internal/handlers/embed` | iframe-embeddable viewer with permissive CORS/CSP |
| `internal/models` | Flipbook struct (statuses: pending → converting → ready/error) |
| `internal/storage` | Filesystem layout: `data/flipbooks/{id}/{original,converted.pdf,pages/,thumbs/,text.json}` |
| `internal/worker` | Background goroutine job queue for async file conversion |
| `internal/mcp` | JSON-RPC 2.0 stdio server implementing MCP protocol |

**Static site pipeline (`site/`):**

| File | Purpose |
|------|---------|
| `site/convert.sh` | Converts a PDF to page PNGs + thumbnails using pdftoppm, extracts text with pdftotext, writes `config.json` |
| `site/build.sh` | Reads each `site/flipbooks/<slug>/config.json`, generates static HTML viewers, copies assets → `site/public/` |
| `site/flipbooks/<slug>/` | Converted flipbook data: `pages/`, `thumbs/`, `config.json` (committed to git) |
| `site/public/` | Build output (gitignored), served by Vercel/Netlify |
| `vercel.json` | Vercel config: build command, output dir, iframe/cache headers |

The build script uses Python to read config.json and generate shell variables (piped via stdin to avoid Windows path issues). Each flipbook produces `/v/<slug>/index.html` (SEO viewer) and `/embed/<slug>/index.html` (iframe embed).

**Frontend:** Vanilla JS/CSS with Go html/templates (server mode) or generated static HTML (static mode) — no build tools. The flipbook viewer uses a vendored StPageFlip library (`web/static/js/page-flip.browser.js`) for 3D page-curl effects with DPR-aware canvas rendering.

**Route structure (both modes):**
- `/v/{slug}` — Public SEO viewer
- `/embed/{slug}` — Embeddable iframe viewer

**Server mode only:**
- `/admin/*` — Session-authenticated dashboard
- `/api/*` — Bearer token-authenticated REST API
- `/data/flipbooks/{id}/*` — Static file serving (images)

## Configuration

Environment variables override YAML config. All prefixed with `FLIPBOOK_`. Key settings:
- `FLIPBOOK_MONGO_URI` — MongoDB connection string (required)
- `FLIPBOOK_BASE_URL` — Public URL (default: http://localhost:8080)
- `FLIPBOOK_API_KEY` — Bearer token for API/MCP (auto-generated if empty)
- `FLIPBOOK_CONVERSION_DPI` / `FLIPBOOK_THUMBNAIL_DPI` — Image quality (300/72 default)

See `config.example.yaml` for full reference.

## Conversion Pipeline

### Server mode (worker queue)

File uploads are processed asynchronously via the worker queue:
1. Original file saved to `data/flipbooks/{id}/original.{ext}` + backed up to GridFS
2. If PPTX/PPT: LibreOffice converts to PDF (uses persistent profile dir)
3. pdftoppm renders each PDF page to PNG at two DPI levels (pages/ and thumbs/)
4. pdftotext extracts per-page text, saved as `text.json`
5. Page dimensions detected from first PNG; status updated to "ready"

The converter auto-detects pdftoppm output naming format (page-1.png vs page-01.png).

### Static site mode (local conversion)

`site/convert.sh <pdf> <slug> [dpi]` runs the same Poppler tools locally:
1. pdftoppm renders pages at specified DPI (default 200) and thumbnails at 72 DPI
2. Page dimensions read from PNG IHDR header (or ImageMagick if available)
3. pdftotext extracts per-page text (optional, enables search)
4. Writes `site/flipbooks/<slug>/config.json` with all metadata

`site/build.sh` then generates static HTML from the config, copying page images and shared assets (JS/CSS) into `site/public/`.

## Testing

No automated tests exist. Testing is manual via the admin UI, REST API, or Docker.
