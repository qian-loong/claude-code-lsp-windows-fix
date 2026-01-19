#!/bin/bash

# Claude Code LSP Fix - 安装多个版本到独立目录
# 每个版本安装到独立目录，避免可执行文件冲突

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# 配置
PACKAGES_DIR="/test/packages"
VERSIONS_TO_INSTALL=${VERSIONS:-"2.1.11 2.1.10 2.1.9 2.1.8 2.1.7 2.1.6 2.1.5"}

echo -e "${BOLD}${BLUE}Installing Claude Code CLI Versions${RESET}\n"
echo "Target directory: $PACKAGES_DIR"
echo "Versions to install: $VERSIONS_TO_INSTALL"
echo ""

# 统计
TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0

# 安装单个版本
install_version() {
    local version=$1
    local version_dir="$PACKAGES_DIR/v${version}"

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}Installing version: ${version}${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

    TOTAL=$((TOTAL + 1))

    # 检查是否已安装
    if [ -d "$version_dir" ] && [ -f "$version_dir/node_modules/@anthropic-ai/claude-code/cli.js" ]; then
        echo -e "${YELLOW}ℹ${RESET} Version ${version} already installed at: ${DIM}$version_dir${RESET}"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    # 创建版本目录
    mkdir -p "$version_dir"
    cd "$version_dir"

    # 初始化 package.json
    echo -e "${DIM}[1/3] Initializing package.json...${RESET}"
    cat > package.json <<EOF
{
  "name": "claude-code-v${version}",
  "version": "1.0.0",
  "private": true,
  "description": "Claude Code CLI v${version} for testing"
}
EOF
    echo -e "${GREEN}✓${RESET} Created package.json"

    # 安装指定版本
    echo -e "${DIM}[2/3] Installing @anthropic-ai/claude-code@${version}...${RESET}"
    if npm install "@anthropic-ai/claude-code@${version}" --no-save 2>&1 | tee install.log | grep -v "npm WARN"; then
        echo -e "${GREEN}✓${RESET} Installed @anthropic-ai/claude-code@${version}"
    else
        echo -e "${RED}✗${RESET} Failed to install version ${version}"
        cat install.log
        FAILED=$((FAILED + 1))
        return 1
    fi

    # 验证安装
    echo -e "${DIM}[3/3] Verifying installation...${RESET}"
    local cli_path="$version_dir/node_modules/@anthropic-ai/claude-code/cli.js"

    if [ -f "$cli_path" ]; then
        echo -e "${GREEN}✓${RESET} CLI file found: ${DIM}$cli_path${RESET}"

        # 检查 LSP 支持
        if grep -q "getServerForFile" "$cli_path"; then
            echo -e "${GREEN}✓${RESET} LSP support: ${GREEN}YES${RESET}"
        else
            echo -e "${YELLOW}⚠${RESET} LSP support: ${YELLOW}NO${RESET}"
        fi

        # 获取文件大小
        local size=$(stat -c%s "$cli_path" 2>/dev/null || echo "unknown")
        echo -e "${DIM}  File size: $size bytes${RESET}"

        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${RED}✗${RESET} CLI file not found at expected location"
        FAILED=$((FAILED + 1))
        return 1
    fi

    # 清理日志
    rm -f install.log
}

# 安装所有版本
for version in $VERSIONS_TO_INSTALL; do
    install_version "$version" || true
done

# 生成版本清单
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Installation Summary${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

echo "Total versions:    $TOTAL"
echo -e "${GREEN}Installed:         $SUCCESS${RESET}"
echo -e "${YELLOW}Skipped:           $SKIPPED${RESET}"
echo -e "${RED}Failed:            $FAILED${RESET}"

# 创建版本清单文件
MANIFEST_FILE="$PACKAGES_DIR/versions.txt"
echo "Installed Claude Code CLI Versions" > "$MANIFEST_FILE"
echo "Generated at: $(date)" >> "$MANIFEST_FILE"
echo "" >> "$MANIFEST_FILE"

for version in $VERSIONS_TO_INSTALL; do
    version_dir="$PACKAGES_DIR/v${version}"
    cli_path="$version_dir/node_modules/@anthropic-ai/claude-code/cli.js"

    if [ -f "$cli_path" ]; then
        has_lsp=$(grep -q "getServerForFile" "$cli_path" && echo "YES" || echo "NO")
        echo "v${version}: $cli_path (LSP: $has_lsp)" >> "$MANIFEST_FILE"
    fi
done

echo ""
echo -e "${GREEN}✓${RESET} Version manifest saved to: ${DIM}$MANIFEST_FILE${RESET}"
cat "$MANIFEST_FILE"

# 退出码
if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}Some installations failed!${RESET}"
    exit 1
else
    echo -e "\n${GREEN}All installations completed successfully!${RESET}"
    exit 0
fi
