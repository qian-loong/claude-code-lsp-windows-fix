# Claude Code LSP Fix for Windows

修复 Claude Code CLI 在 Windows 上的 LSP（Language Server Protocol）文件路径问题。

[![测试状态](https://img.shields.io/badge/测试-100%25通过-brightgreen)]()
[![支持版本](https://img.shields.io/badge/版本-2.0.74--2.1.11-blue)]()

## 🎯 问题描述

Claude Code CLI 的 LSP 功能在 Windows 上使用了错误的文件 URI 格式：

```javascript
// 错误格式（2.0.74 - 2.1.9）
`file://${path.resolve(file)}`  // 生成: file://C:\path\to\file

// 正确格式（2.1.10+）
pathToFileURL(path.resolve(file)).href  // 生成: file:///C:/path/to/file
```

这导致 LSP 服务器无法正确识别 Windows 文件路径，影响代码补全、跳转定义等功能。

## 📊 支持的版本

| 版本范围 | LSP 支持 | 需要修复 | 状态 | 测试结果 |
|---------|---------|---------|------|---------|
| < 2.0.74 | ❌ 无 | - | 不支持 LSP(以官方ChangeLog add为准) | - |
| 2.0.74 - 2.1.12 | ✅ 有 | ✅ 是 | 需要 patch | ✅ 100% 通过 |

**测试覆盖**: 17 个版本（2.0.74 - 2.1.12），成功率 **100%**

详细测试报告: [TEST_REPORT.md](TEST_REPORT.md)

## ⚡ 快速开始

### 方法 1: 手动修复单个文件（推荐）

```bash
# 1. 克隆或下载本项目
git clone https://github.com/qian-loong/claude-code-lsp-windows-fix.git
cd claude-code-lsp-windows-fix

# 2. 运行修复（指定 CLI 文件路径）
node scripts/apply-lsp-fix-anchor-based.cjs /path/to/cli.js

# 示例：
node scripts/apply-lsp-fix-anchor-based.cjs C:/Users/username/node_modules/@anthropic-ai/claude-code/cli.js

# 3. 重启 Claude Code CLI
exit
claude
```

## 🔧 核心脚本说明

### apply-lsp-fix-anchor-based.cjs

**特点**:
- ✅ 基于稳定的 LSP return 语句作为锚点
- ✅ 动态提取变量名，支持所有混淆模式
- ✅ 使用括号配对算法精确定位函数边界
- ✅ 自动创建备份
- ✅ 支持 `$`, `_` 开头的变量名
- ✅ 可重复运行，自动检测状态

**工作原理**:
1. 查找 LSP 函数的 return 语句（稳定特征）
2. 使用括号配对向前找到函数开始位置
3. 动态提取实际使用的变量名
4. 替换所有旧的 URI 构造方式

**修复内容**（每个版本 5 处）:
- `didOpen` - 打开文件通知
- `didChange` - 文件变更通知
- `didSave` - 文件保存通知
- `didClose` - 文件关闭通知
- `isFileOpen` - 文件打开状态检查

## 📊 技术细节

### 变量名混淆模式

不同版本使用不同的变量名混淆，脚本完全兼容：

| 版本 | LSP 函数 | pathToFileURL | path 模块 |
|------|----------|---------------|-----------|
| 2.0.74-2.1.6 | `$52`, `z52`, `h52`, `b52` | `U35`, `C35`, `jA7`, `PA7` | `ag`, `Rm` |
| 2.1.7-2.1.8 | `_82`, `Uy2` | `J65`, `We8` | `vd`, `Mc` |
| 2.1.9 | `D52` | `e65` | `ud` |
| 2.1.10-2.1.12 | `$52`, `z52`, `A52` | `U35`, `C35`, `F35` | `ag`, `ig` |

脚本使用正则 `[$\w]+` 匹配所有 JavaScript 变量名。

### 锚点定位策略

**为什么使用 `return `语句作为锚点？**

1. **稳定性**: LSP 函数的 `return `语句结构固定
   
   ```javascript
   return {
     initialize: xxx,
     shutdown: xxx,
     getServerForFile: xxx,
     // ... 其他方法
   }
   ```
   
2. **唯一性**: 这个特定的方法组合在代码中是唯一的

3. **可靠性**: 即使变量名混淆，`return `语句结构不变

## ❓ 常见问题

### Q: 我应该使用哪个版本？

**A**: 测试发现所有 LSP 版本（2.0.74 - 2.1.12）在 Windows 上都存在 URI 问题，建议使用本脚本修复。

### Q: 修复后需要重启吗？

**A**: 是的，修复后需要**完全退出并重启** Claude Code CLI 才能生效。

### Q: 如何恢复原始文件？

**A**: 脚本会自动在 CLI 文件同目录下创建 `backups/` 文件夹并保存备份：
- 备份位置: `<cli-directory>/backups/cli-TIMESTAMP.js`

恢复方法：
```bash
cp <cli-directory>/backups/cli-2026-01-19T06-03-58-076Z.js /path/to/cli.js
```

### Q: 脚本可以重复运行吗？

**A**: 可以！脚本有状态检测机制：
- ✅ 如果已经修复，会自动跳过
- ✅ 不会重复打补丁
- ✅ 每次运行都会创建新备份

## 📈 测试结果

**测试摘要**:
- ✅ 测试版本: 17 个（2.0.74 - 2.1.12）
- ✅ 成功率: **100%**
- ✅ 每版本补丁数: 5

详细测试报告: [TEST_REPORT.md](TEST_REPORT.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可

MIT License

## 🔗 相关链接

- [Claude Code GitHub](https://github.com/anthropics/claude-code)
- [Claude Code Changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [LSP 功能介绍 (2.0.74)](https://www.petegypps.uk/blog/claude-code-2-0-74-lsp-chrome-integration-december-2025)
- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
- [[BUG\] clangd-lsp: Malformed file:// URI Generation on Windows (v2.1.1) · Issue #16729 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/16729)
- [[BUG\] LSP clangd fails on Windows: "unresolvable URI" in textDocument/didOpen · Issue #17094 · anthropics/claude-code](https://github.com/anthropics/claude-code/issues/17094)

---

**最后更新**: 2026-01-19
**测试版本**: 2.0.74 - 2.1.12
**成功率**: 100%
