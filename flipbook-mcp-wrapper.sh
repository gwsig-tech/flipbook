#!/bin/bash
# Flipbook MCP Wrapper
# Sets working directory so the MCP server can find config files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec "$SCRIPT_DIR/bin/flipbook" mcp
