#!/usr/bin/env node

/**
 * Claude Code LSP Fix - Anchor-Based Version
 *
 * 使用稳定的 LSP return 语句作为锚点定位函数，而不是依赖易变的变量名
 *
 * 核心思路：
 * 1. LSP 函数的 return 语句结构是稳定的（包含 initialize, shutdown, getServerForFile 等方法）
 * 2. 从 return 语句向前搜索找到函数开始位置
 * 3. 在函数内部定位需要修改的代码模式
 * 4. 动态提取实际使用的变量名进行替换
 */

const fs = require('fs');
const path = require('path');

// ANSI 颜色代码
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    dim: '\x1b[2m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
    bold: '\x1b[1m'
};

// 从命令行参数获取 CLI 文件路径
const CLI_PATH = process.argv[2];

// 备份目录（CLI 文件同目录下的 backups 文件夹）
const BACKUP_DIR = CLI_PATH ? path.join(path.dirname(CLI_PATH), 'backups') : null;

/**
 * 显示差异对比
 */
function showDiff(title, content, startIndex, endIndex, newText) {
    const contextLength = 80;
    const contextStart = Math.max(0, startIndex - contextLength);
    const contextEndOld = Math.min(content.length, endIndex + contextLength);

    const beforeText = content.slice(contextStart, startIndex);
    const oldText = content.slice(startIndex, endIndex);
    const afterText = content.slice(endIndex, contextEndOld);

    // NEW 版本的 after 文本应该从 endIndex 开始（旧代码结束的位置）
    const afterTextNew = afterText;

    console.log(`\n${colors.dim}━━━ ${title} ━━━${colors.reset}`);
    console.log(`${colors.red}[-] OLD:${colors.reset} ${beforeText}${colors.red}${oldText}${colors.reset}${afterText}`);
    console.log(`${colors.green}[+] NEW:${colors.reset} ${beforeText}${colors.green}${newText}${colors.reset}${afterTextNew}`);
    console.log(`${colors.dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${colors.reset}\n`);
}

/**
 * 创建备份
 */
function createBackup(filePath) {
    if (!fs.existsSync(BACKUP_DIR)) {
        fs.mkdirSync(BACKUP_DIR, { recursive: true });
    }

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupPath = path.join(BACKUP_DIR, `cli-${timestamp}.js`);

    fs.copyFileSync(filePath, backupPath);
    console.log(`${colors.green}✓${colors.reset} Backup created: ${backupPath}`);

    return backupPath;
}

/**
 * 使用括号配对找到函数开始位置
 * 从函数结束的 } 向前匹配，找到对应的 {
 */
function findFunctionStart(content, returnPos, returnEndPos) {
    // 找到 return 语句后的函数结束 }
    // return{...} 后面应该紧跟一个 }
    let functionEndBrace = returnEndPos;

    // 跳过 return 对象的 }，找到函数体的 }
    while (functionEndBrace < content.length && content[functionEndBrace] !== '}') {
        functionEndBrace++;
    }

    if (content[functionEndBrace] !== '}') {
        throw new Error('Could not find function closing brace after return statement');
    }

    console.log(`${colors.dim}  Function ends at position ${functionEndBrace}${colors.reset}`);

    // 从函数结束的 } 向前匹配括号
    let braceCount = 1; // 需要找到匹配的 {
    let pos = functionEndBrace - 1;

    // 向前扫描，匹配括号
    while (pos >= 0 && braceCount > 0) {
        const char = content[pos];
        if (char === '}') {
            braceCount++;
        } else if (char === '{') {
            braceCount--;
        }
        pos--;
    }

    if (braceCount !== 0) {
        throw new Error('Bracket mismatch: could not find function start');
    }

    // pos 现在指向匹配的 { 的前一个字符
    const functionStartBrace = pos + 1;

    // 从 { 向前查找 function 关键字
    // 格式：function XXX(){
    // 函数名可以是：A52, $52, _foo, foo 等
    const beforeBrace = content.substring(Math.max(0, functionStartBrace - 100), functionStartBrace);
    const functionMatch = beforeBrace.match(/function ([$\w]+)\(\)$/);

    if (!functionMatch) {
        throw new Error('Could not find function declaration before opening brace');
    }

    const functionName = functionMatch[1];
    const functionStart = functionStartBrace - functionMatch[0].length;

    return {
        name: functionName,
        start: functionStart,
        end: functionEndBrace + 1, // +1 包含结束的 }
        bracePos: functionStartBrace
    };
}

/**
 * 查找 LSP 函数
 * 使用稳定的 return 语句作为锚点，然后用括号配对找到函数边界
 */
function findLSPFunction(content) {
    console.log(`${colors.cyan}[2/5]${colors.reset} Locating LSP function using return statement anchor...`);

    // 查找 LSP 函数的 return 语句（这是稳定的特征）
    // 变量名可以是：G, $foo, _bar, foo123 等
    const returnPattern = /return *\{ *initialize: *[$\w]+ *, *shutdown: *[$\w]+ *, *getServerForFile: *[$\w]+ *, *ensureServerStarted: *[$\w]+ *, *sendRequest: *[$\w]+ *, *getAllServers: *[$\w]+ *, *openFile: *[$\w]+ *, *changeFile: *[$\w]+ *, *saveFile: *[$\w]+ *, *closeFile: *[$\w]+ *, *isFileOpen: *[$\w]+ *\}/;

    const returnMatch = content.match(returnPattern);
    if (!returnMatch) {
        throw new Error('Could not find LSP function return statement');
    }

    const returnPos = content.indexOf(returnMatch[0]);
    const returnEndPos = returnPos + returnMatch[0].length;
    console.log(`${colors.green}✓${colors.reset} Found return statement at position ${returnPos}`);

    // 使用括号配对找到函数边界
    console.log(`${colors.dim}  Using bracket matching to find function boundaries...${colors.reset}`);

    const functionInfo = findFunctionStart(content, returnPos, returnEndPos);
    const functionStart = functionInfo.start;
    const functionEnd = functionInfo.end;
    const functionName = functionInfo.name;

    console.log(`${colors.green}✓${colors.reset} Found LSP function: ${colors.bold}${functionName}${colors.reset}`);
    console.log(`${colors.dim}  Range: ${functionStart} - ${functionEnd} (${functionEnd - functionStart} chars)${colors.reset}`);

    return {
        name: functionName,
        start: functionStart,
        end: functionEnd,
        code: content.substring(functionStart, functionEnd)
    };
}

/**
 * 提取函数内使用的变量名
 */
function extractVariables(content, lspFunction) {
    console.log(`${colors.cyan}[3/5]${colors.reset} Extracting variable names from LSP function...`);

    const variables = {};

    // 1. 提取 pathToFileURL 的别名（从文件开头的 import 语句）
    // 别名可以是：C35, $35, _F35, foo 等
    const pathToFileURLMatch = content.match(/import\{pathToFileURL as ([$\w]+)\}from["']url["']/);
    if (pathToFileURLMatch) {
        variables.pathToFileURL = pathToFileURLMatch[1];
        console.log(`${colors.green}✓${colors.reset} pathToFileURL alias: ${colors.bold}${variables.pathToFileURL}${colors.reset}`);
    }

    // 2. 提取 path 模块别名（从 LSP 函数内部实际使用的）
    // 查找模式：`file://${XXX.resolve(...)}` 或 XXX.resolve(...)
    // 别名可以是：ag, $path, _p, PATH 等
    const pathUsageMatch = lspFunction.code.match(/([$\w]+)\.resolve\(/);
    if (pathUsageMatch) {
        variables.path = pathUsageMatch[1];
        console.log(`${colors.green}✓${colors.reset} path module alias: ${colors.bold}${variables.path}${colors.reset}`);
    }

    // 3. 检查当前的 URI 构造方式
    const oldUriPattern = /`file:\/\/\$\{[$\w]+\.resolve\([^)]+\)\}`/;
    const newUriPattern = /[$\w]+\([$\w]+\.resolve\([^)]+\)\)\.href/;

    if (oldUriPattern.test(lspFunction.code)) {
        console.log(`${colors.yellow}ℹ${colors.reset} Found old URI construction pattern (needs patching)`);
        variables.needsPatching = true;
    } else if (newUriPattern.test(lspFunction.code)) {
        console.log(`${colors.yellow}ℹ${colors.reset} Found new URI construction pattern (already patched)`);
        variables.needsPatching = false;
    } else {
        console.log(`${colors.yellow}⚠${colors.reset} Unknown URI construction pattern`);
        variables.needsPatching = false;
    }

    return variables;
}

/**
 * 应用补丁
 */
function applyPatches(content, lspFunction, variables) {
    console.log(`${colors.cyan}[4/5]${colors.reset} Applying patches...`);

    let modified = content;
    let patchCount = 0;

    if (!variables.needsPatching) {
        console.log(`${colors.green}✓${colors.reset} No patching needed (already fixed or unknown pattern)`);
        return modified;
    }

    if (!variables.path || !variables.pathToFileURL) {
        console.log(`${colors.red}✗${colors.reset} Cannot apply patches: Missing required variables`);
        console.log(`  path: ${variables.path || 'NOT FOUND'}`);
        console.log(`  pathToFileURL: ${variables.pathToFileURL || 'NOT FOUND'}`);
        return modified;
    }

    // 补丁：替换所有旧的 URI 构造方式
    // 旧：`file://${path.resolve(file)}`
    // 新：pathToFileURL(path.resolve(file)).href

    console.log(`\n${colors.cyan}Patching URI construction...${colors.reset}`);

    // 在 LSP 函数范围内查找所有旧的 URI 构造
    // 文件变量可以是：H, $h, _file, foo 等
    const oldPattern = new RegExp(
        `\`file:\\/\\/\\$\\{${variables.path}\\.resolve\\(([$\\w]+)\\)\\}\``,
        'g'
    );

    // 在完整文件中查找并替换（限制在 LSP 函数范围内）
    const functionStart = lspFunction.start;
    const functionEnd = lspFunction.end;
    const beforeFunction = modified.substring(0, functionStart);
    const functionCode = modified.substring(functionStart, functionEnd);
    const afterFunction = modified.substring(functionEnd);

    const matches = [...functionCode.matchAll(oldPattern)];

    if (matches.length > 0) {
        console.log(`${colors.dim}Found ${matches.length} old URI construction(s)${colors.reset}`);

        let modifiedFunction = functionCode;
        let offset = 0; // 跟踪累积的长度变化

        for (const match of matches) {
            const fileVar = match[1];
            const oldCode = match[0];
            const newCode = `${variables.pathToFileURL}(${variables.path}.resolve(${fileVar})).href`;

            // 在当前的 modifiedFunction 中查找（考虑之前的偏移）
            const startIndex = modifiedFunction.indexOf(oldCode);
            if (startIndex !== -1) {
                const endIndex = startIndex + oldCode.length;

                // 显示差异（使用原始内容和原始位置）
                const originalStart = functionStart + match.index;
                showDiff(
                    `Fix URI construction (file variable: ${fileVar})`,
                    content, // 使用原始内容
                    originalStart,
                    originalStart + oldCode.length,
                    newCode
                );

                // 替换
                modifiedFunction = modifiedFunction.substring(0, startIndex) + newCode + modifiedFunction.substring(endIndex);
                patchCount++;
            }
        }

        // 重新组合文件
        modified = beforeFunction + modifiedFunction + afterFunction;

        console.log(`${colors.green}✓${colors.reset} Patched ${matches.length} URI construction(s)`);
    } else {
        console.log(`${colors.yellow}⚠${colors.reset} No old URI constructions found`);
    }

    console.log(`\n${colors.bright}Summary: ${patchCount} patch(es) applied${colors.reset}`);

    return modified;
}

/**
 * 主函数
 */
function main() {
    console.log(`${colors.bright}${colors.blue}Claude Code LSP Fix - Anchor-Based Version${colors.reset}\n`);

    let backupPath = null;

    try {
        // 检查参数
        if (!CLI_PATH) {
            console.error(`${colors.red}Error: CLI file path is required${colors.reset}`);
            console.log(`\nUsage: node apply-lsp-fix-anchor-based.cjs <path-to-cli.js>`);
            console.log(`Example: node apply-lsp-fix-anchor-based.cjs /path/to/node_modules/@anthropic-ai/claude-code/cli.js\n`);
            process.exit(1);
        }

        // 检查文件是否存在
        if (!fs.existsSync(CLI_PATH)) {
            throw new Error(`CLI file not found: ${CLI_PATH}`);
        }

        console.log(`${colors.dim}Target: ${CLI_PATH}${colors.reset}\n`);

        // 创建备份（在任何修改之前）
        console.log(`${colors.cyan}[1/5]${colors.reset} Creating backup...`);
        backupPath = createBackup(CLI_PATH);
        console.log();

        // 读取文件
        const content = fs.readFileSync(CLI_PATH, 'utf8');
        console.log(`${colors.green}✓${colors.reset} File loaded (${content.length} bytes)\n`);

        // 查找 LSP 函数
        const lspFunction = findLSPFunction(content);

        // 提取变量名
        const variables = extractVariables(content, lspFunction);

        // 应用补丁
        const modified = applyPatches(content, lspFunction, variables);

        // 保存修改
        console.log(`${colors.cyan}[5/5]${colors.reset} Saving changes...`);
        fs.writeFileSync(CLI_PATH, modified, 'utf8');
        console.log(`${colors.green}✓${colors.reset} Changes saved to ${CLI_PATH}`);

        console.log(`\n${colors.bright}${colors.green}✓ LSP fix applied successfully!${colors.reset}`);
        console.log(`${colors.dim}You may need to restart Claude Code CLI for changes to take effect.${colors.reset}\n`);

    } catch (error) {
        console.error(`\n${colors.red}✗ Error: ${error.message}${colors.reset}`);

        // 自动回滚
        if (backupPath && fs.existsSync(backupPath)) {
            console.log(`${colors.yellow}⟳${colors.reset} Rolling back changes...`);
            try {
                fs.copyFileSync(backupPath, CLI_PATH);
                console.log(`${colors.green}✓${colors.reset} Rollback successful\n`);
            } catch (rollbackError) {
                console.error(`${colors.red}✗${colors.reset} Rollback failed: ${rollbackError.message}`);
                console.log(`${colors.yellow}ℹ${colors.reset} Manual restore needed from: ${backupPath}\n`);
            }
        } else {
            console.log();
        }

        process.exit(1);
    }
}

// 运行
main();
