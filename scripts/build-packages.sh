#!/usr/bin/env bash
set -euo pipefail

echo "Building packages..."
pnpm --filter @the-a2ui/renderer run prepare

echo "All packages built successfully."
