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

视觉模式下的 leader 提示也已经显式注册，像选中文本后使用 `SPC o t` 时，会直接显示 `Translate selection with Ollama`，不再退化成 `1+ mappings`。

## 打包

运行仓库根目录下的 `./package_nvim.sh` 会生成一个自解压安装脚本 `target/install.sh`。

这个安装脚本会内嵌当前 Neovim 配置，以及本机 `~/.local/share/nvim` 里和配置直接相关的内容，包括：

- `lazy` 插件下载目录；
- `mason` 下载的 LSP / 工具 / 注册表；
- `nvim-java` 下载的运行时数据；
- 若存在，则一并带上 `site` 目录下的本地运行时内容。

在另一台机器上直接运行这个 `install.sh`，就会把内容安装到当前用户的 XDG 路径：

- `${XDG_CONFIG_HOME:-~/.config}/nvim`
- `${XDG_DATA_HOME:-~/.local/share}/nvim`

`./package_nvim.sh -h` 和生成后的 `target/install.sh -h` 都可查看帮助；传入不支持的参数时会直接展示帮助信息并返回非零状态。
