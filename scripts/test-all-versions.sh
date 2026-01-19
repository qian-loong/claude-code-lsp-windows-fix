#!/bin/bash

# Claude Code LSP Fix - 多版本测试脚本
# 测试所有已安装的版本（从独立目录）

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

# 测试配置
TEST_DIR="/test"
PACKAGES_DIR="$TEST_DIR/packages"
SCRIPTS_DIR="$TEST_DIR/scripts"
RESULTS_DIR="$TEST_DIR/results"
BACKUPS_DIR="$TEST_DIR/backups"

# 结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 创建结果文件
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="$RESULTS_DIR/test-results-${TIMESTAMP}.txt"
SUMMARY_FILE="$RESULTS_DIR/summary.txt"

echo -e "${BOLD}${BLUE}Claude Code LSP Fix - Multi-Version Test${RESET}\n"
echo "Test started at: $(date)" | tee "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# 检查是否有已安装的版本
if [ ! -d "$PACKAGES_DIR" ] || [ -z "$(ls -A $PACKAGES_DIR/v* 2>/dev/null)" ]; then
    echo -e "${RED}✗${RESET} No installed versions found in $PACKAGES_DIR"
    echo "Please run install-versions.sh first"
    exit 1
fi

# 获取所有已安装的版本（只匹配目录，排除文件）
INSTALLED_VERSIONS=$(find $PACKAGES_DIR -maxdepth 1 -type d -name "v*" 2>/dev/null | xargs -n1 basename | sed 's/^v//' | sort -V)
echo "Found installed versions: $INSTALLED_VERSIONS" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# 测试单个版本
test_version() {
    local version=$1
    local version_dir="$PACKAGES_DIR/v${version}"
    local cli_path="$version_dir/node_modules/@anthropic-ai/claude-code/cli.js"

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}Testing version: ${version}${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # 记录到结果文件
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$RESULT_FILE"
    echo "Version: $version" >> "$RESULT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$RESULT_FILE"

    # 1. 检查 CLI 文件是否存在
    echo -e "${DIM}[1/4] Checking CLI file...${RESET}"
    if [ ! -f "$cli_path" ]; then
        echo -e "${RED}✗${RESET} CLI file not found: $cli_path"
        echo "✗ CLI file: NOT FOUND" >> "$RESULT_FILE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    echo -e "${GREEN}✓${RESET} Found CLI at: ${DIM}$cli_path${RESET}"
    echo "✓ CLI file: $cli_path" >> "$RESULT_FILE"

    # 2. 检查是否包含 LSP 功能
    echo -e "${DIM}[2/4] Checking for LSP support...${RESET}"
    if grep -q "getServerForFile" "$cli_path"; then
        echo -e "${GREEN}✓${RESET} LSP support detected"
        echo "✓ LSP support: YES" >> "$RESULT_FILE"
    else
        echo -e "${YELLOW}⚠${RESET} No LSP support in this version (skipping)"
        echo "⚠ LSP support: NO (skipped)" >> "$RESULT_FILE"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi

    # 3. 备份原始文件（如果还没有备份）
    echo -e "${DIM}[3/4] Creating backup...${RESET}"
    local backup_file="$BACKUPS_DIR/cli-${version}-original.js"
    if [ ! -f "$backup_file" ]; then
        cp "$cli_path" "$backup_file"
        echo -e "${GREEN}✓${RESET} Backup created: ${DIM}$backup_file${RESET}"
        echo "✓ Backup: $backup_file" >> "$RESULT_FILE"
    else
        echo -e "${YELLOW}ℹ${RESET} Backup already exists: ${DIM}$backup_file${RESET}"
        echo "ℹ Backup: Already exists" >> "$RESULT_FILE"
    fi

    # 4. 运行 patch 脚本
    echo -e "${DIM}[4/4] Running patch script...${RESET}"

    # 创建临时的 patch 脚本（修改路径）
    local temp_script="$SCRIPTS_DIR/temp-patch-${version}.cjs"
    sed "s|const CLI_PATH = .*|const CLI_PATH = '$cli_path';|" \
        "$SCRIPTS_DIR/apply-lsp-fix-anchor-based.cjs" > "$temp_script"
    sed -i "s|const BACKUP_DIR = .*|const BACKUP_DIR = '$BACKUPS_DIR';|" "$temp_script"

    # 运行 patch
    local patch_output="$RESULTS_DIR/patch-output-${version}.txt"
    if node "$temp_script" > "$patch_output" 2>&1; then
        echo -e "${GREEN}✓${RESET} Patch script executed successfully"
        echo "✓ Patch execution: SUCCESS" >> "$RESULT_FILE"

        # 检查是否实际应用了补丁
        if grep -q "already patched\|already fixed" "$patch_output"; then
            echo -e "${YELLOW}ℹ${RESET} File was already patched"
            echo "ℹ Patch status: ALREADY PATCHED" >> "$RESULT_FILE"
        elif grep -q "patch(es) applied" "$patch_output"; then
            local patch_count=$(grep -o "[0-9]* patch(es) applied" "$patch_output" | grep -o "^[0-9]*")
            echo -e "${GREEN}✓${RESET} Applied ${patch_count} patch(es)"
            echo "✓ Patch status: APPLIED ($patch_count patches)" >> "$RESULT_FILE"
        else
            echo -e "${YELLOW}ℹ${RESET} No patches needed"
            echo "ℹ Patch status: NO PATCHES NEEDED" >> "$RESULT_FILE"
        fi

        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${RESET} Patch script failed"
        echo "✗ Patch execution: FAILED" >> "$RESULT_FILE"
        echo "" >> "$RESULT_FILE"
        echo "Error output:" >> "$RESULT_FILE"
        cat "$patch_output" >> "$RESULT_FILE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        rm -f "$temp_script"
        return 1
    fi

    # 显示 patch 输出摘要
    echo -e "\n${DIM}Patch output summary:${RESET}"
    grep -E "✓|✗|ℹ|⚠" "$patch_output" | head -10

    # 清理临时文件
    rm -f "$temp_script"

    echo "" >> "$RESULT_FILE"
}

# 主测试循环
for version in $INSTALLED_VERSIONS; do
    test_version "$version" || true
done

# 生成测试摘要
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Test Summary${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

echo "Total tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:        $PASSED_TESTS${RESET}"
echo -e "${RED}Failed:        $FAILED_TESTS${RESET}"
echo -e "${YELLOW}Skipped:       $SKIPPED_TESTS${RESET}"

# 计算成功率
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "\nSuccess rate:  ${SUCCESS_RATE}%"
fi

# 保存摘要
{
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test completed at: $(date)"
    echo ""
    echo "Total tests:   $TOTAL_TESTS"
    echo "Passed:        $PASSED_TESTS"
    echo "Failed:        $FAILED_TESTS"
    echo "Skipped:       $SKIPPED_TESTS"
    if [ $TOTAL_TESTS -gt 0 ]; then
        echo "Success rate:  $((PASSED_TESTS * 100 / TOTAL_TESTS))%"
    fi
    echo ""
    echo "Detailed results: $RESULT_FILE"
    echo ""
    echo "Backups location: $BACKUPS_DIR"
} | tee "$SUMMARY_FILE" >> "$RESULT_FILE"

# 退出码
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "\n${RED}Some tests failed!${RESET}"
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${RESET}"
    exit 0
fi
