# Neovim 配置说明

当前 `leader` 键是 `Space`。

## 中文文档

- [Java / Lombok / LSP / Leader 键说明](docs/java-lsp-and-keymaps.zh-CN.md)

## 快速入口

| 按键 | 说明 |
| :--- | :--- |
| `gd` / `<C-]>` | 跳到定义；在 Java 中可进入 JDK / JAR 类源码或反编译内容 |
| `SPC l ...` | LSP 操作组：定义、引用、重命名、诊断、格式化 |
| `SPC j ...` | Java 操作组：organize imports、运行、测试、重构 |
| `SPC f ...` | 查找操作组：文件、grep、buffer、recent、tags |
| `SPC w ...` | 窗口操作组 |
| `SPC x ...` | 诊断操作组 |
| `SPC m ...` | make / build 操作组 |
| `SPC ?` | 查看当前 buffer 可用快捷键 |

按下 `Space` 或其它前缀键的一半时，会通过 `which-key.nvim` 在底部显示可继续输入的操作。
