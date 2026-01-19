#!/bin/sh
VERSION=$1
CLI_PATH="/test/packages/v${VERSION}/node_modules/@anthropic-ai/claude-code/cli.js"

if [ ! -f "$CLI_PATH" ]; then
  echo "CLI file not found: $CLI_PATH"
  exit 1
fi

echo "Testing version $VERSION..."

# Create temp script with correct paths
sed "s|const CLI_PATH = .*|const CLI_PATH = '$CLI_PATH';|" apply-lsp-fix-anchor-based.cjs > /tmp/patch.cjs
sed -i "s|const BACKUP_DIR = .*|const BACKUP_DIR = '/test/backups';|" /tmp/patch.cjs

node /tmp/patch.cjs
