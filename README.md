# Neovim 配置说明

当前 `leader` 键是 `Space`。

## 中文文档

- [Java / Lombok / LSP / Leader 键说明](docs/java-lsp-and-keymaps.zh-CN.md)

## 快速入口

| 按键 | 说明 |
| :--- | :--- |
| `gd` / `<C-]>` | 跳到定义；在 Java 中可进入 JDK / JAR 类源码或反编译内容 |
| `SPC l ...` | LSP 操作组：定义、引用、重命名、诊断、格式化、按类名跳转（视觉模式下 `SPC l f` 可格式化选中内容） |
| `SPC j ...` | Java 操作组：organize imports、运行、测试、重构 |
| `SPC f ...` | 查找操作组：文件、grep、buffer、recent、tags |
| `SPC w ...` | 窗口操作组 |
| `SPC x ...` | 诊断操作组 |
| `SPC m ...` | make / build 操作组 |
| `<S-f>` | 当前行的 stack trace / reference / `path:line` 精确跳转；失败时回退到 `gF` |
| `,,` | 在 `html` / `xml` / `css` / `svg` / `xhtml` buffer 里展开 Emmet 缩写 |
| `SPC ?` | 查看当前 buffer 可用快捷键 |

按下 `Space` 或其它前缀键的一半时，会通过 `which-key.nvim` 在底部显示可继续输入的操作。

视觉模式下的 leader 提示也已经显式注册，像选中文本后使用 `SPC o t` 时，会直接显示 `Translate selection with Ollama`，不再退化成 `1+ mappings`。

## 项目结构说明 (Project Structure)

本配置是基于 Lua 的模块化 Neovim 配置，核心结构如下，便于未来快速了解和二次开发：

- [init.lua](file:///Users/suremoon/.config/nvim/init.lua)：配置的主入口文件，负责加载核心配置模块、全局选项及第三方插件。
- [lua/user/options.lua](file:///Users/suremoon/.config/nvim/lua/user/options.lua)：Neovim 核心选项与全局变量配置（包含 Spring Boot LSP 开关等）。
- [lua/user/keymaps.lua](file:///Users/suremoon/.config/nvim/lua/user/keymaps.lua)：全局快捷键映射（包含窗口导航、终端切换、C/C++ 宏展开以及 **Dirvish 快捷键**）。
- [lua/user/plugins.lua](file:///Users/suremoon/.config/nvim/lua/user/plugins.lua)：基于 `lazy.nvim` 的插件定义与各自的 setup 配置（包含 **Telescope 搜索过滤**）。
- [lua/user/java.lua](file:///Users/suremoon/.config/nvim/lua/user/java.lua)：Java 相关的高级集成，处理 JDTLS 配置、Lombok 与 Mapper/XML 配对跳转。
- [lua/user/lsp.lua](file:///Users/suremoon/.config/nvim/lua/user/lsp.lua)：LSP 客户端挂载（`on_attach`）与标准语言特性的按键绑定。
- [lua/user/templates.lua](file:///Users/suremoon/.config/nvim/lua/user/templates.lua) **[NEW]**：自动化模板引擎，在新文件创建时自动填充标准模板体。
- [lua/user/select.lua](file:///Users/suremoon/.config/nvim/lua/user/select.lua) **[NEW]**：高质感悬浮式全局选择菜单，深度定制 `vim.ui.select` 交互体验。
- [lua/user/printf_highlight.lua](file:///Users/suremoon/.config/nvim/lua/user/printf_highlight.lua)：跨语言占位符/参数联动高亮，支持 printf 风格与 Java / Rust 的 `{}` 风格格式串。
- [lua/user/file_actions.lua](file:///Users/suremoon/.config/nvim/lua/user/file_actions.lua) **[NEW]**：统一封装文件重命名/删除动作，供当前 buffer 与 Dirvish 文件列表复用。

---

## 新增功能与用法 (New Features & Usage)

配置近期新增了以下核心功能与性能优化：

### 1. 新建代码文件自动填充模板
在新创代码文件时，会自动触发 `BufNewFile` 钩子生成对应语言的模板文件体：
- **支持语言**：Java, Go, Python, Rust, Shell (`sh`/`bash`), C, C++, JS/TS, HTML。
- **Java 自动包解析**：创建 Java 文件时，会智能向上解析 `src/main/java` 等目录，自动生成正确的 `package com.xxx;` 包声明并匹配类名。
- **创作者注释**：文件头部会自动生成作者和当前时间。作者查找优先级为：`vim.g.file_author` &rarr; `git config user.name` &rarr; 系统主机 `$USER` 变量。

### 2. Spring Boot LSP 启动速度优化
- **背景**：默认开启 Spring Boot LSP 会导致每次启动都通过网络请求 `spring.io/projects` 抓取数据或进行遥测，从而拖慢 LSP 启动速度，在弱网/离线环境下尤为严重。
- **优化**：在 `options.lua` 中默认配置了 `vim.g.enable_spring_boot_tools = false`。这将在保证标准 Java 特性（定义跳转、自动补全、Lombok 等）完整可用的前提下，**跳过**请求 `spring.io` 的过程，大幅提升打开 Java 时的 LSP 启动速度。
- **手动开启**：如果需要 Spring 相关的属性/注解高级补全，可以在 `options.lua` 中将该变量改为 `true`。

### 3. Telescope 搜索文件排除二进制 class
- **快捷键**：`<C-p>`
- **优化**：在 Telescope 搜索文件的参数中，显式加入了排除 glob (`!target`, `!target/**`, `!*.class`)。这可确保在 LSP 编译项目并生成 `.class` 字节码文件到 `target` 目录后，搜索列表中不会被大量编译产生的垃圾文件所充斥。

### 4. Dirvish 列表页实用工具与快捷键
使用 `-` 键进入目录列表（Dirvish 文件列表页）后，新增了以下几个高效率本地命令：
- **新建文件 (`a` 或 `SPC b a`)**：在当前目录下新建文件；支持输入相对路径，新建后会直接打开该文件开始编辑，并自动套用已有的新文件模板内容。
- **快速执行终端命令 (`x` / `!` / `SPC b x`)**：在当前选中的文件上执行 shell 命令，会在下方打开输入框，且自带 **Shell 终端命令补全** 体验。支持使用 `%` 代表当前文件路径。输入指令后会在切分终端中实时执行。
- **智能重命名 (`r` 或 `SPC b r`)**：在选中的文件/目录上重命名时，会保留 Vim 里已打开的 buffer；若目标是 Java 文件，则优先走 JDTLS 的文件重构流程，连同类名与引用一起更新。
- **删除文件 (`D` 或 `SPC b d`)**：可直接删除当前选中的文件或目录；若该文件已经在 Neovim 中打开，其 buffer 会继续保留，不会被自动 wipe 掉。

### 5. 高端悬浮式 LSP Code Action 选择界面
- **快捷键**：`ff` 或 `<leader>la` （触发 LSP 的 code action 动作）
- **优化**：完全取代了粗糙的终端式选项卡，改为弹出置中的圆角悬浮框，带有漂亮的边框、高亮光标行和底部状态栏说明：
  - **数字直接跳转**：支持按下数字键 `0-9` 直接跳转对应行（例如输入 `1` 跳转第一行，若再输入 `5` 且存在该选项，则会智能组合输入为 `15` 并自动跳到第 15 行）。
  - **顶部红色输入提示**：浮窗顶部会显眼显示当前已输入的数字，并用红色高亮；只有在输入数字能命中有效条目时，才会直接跳转到对应行。
  - **退格回滚 (`<BS>`)**：输入错误时按退格键能立刻删除上一位数字，并退回原选项位置。
  - **运行与退出**：选中后按 `<CR>` 执行当前项；在需要切换成员勾选/反勾选的场景里可直接按 `.`；任何时候按 `q` 或快速连按两次 `<Esc>` 退出悬浮框且不进行任何操作。

### 6. 当前文件 buffer 的快捷编辑
- **重命名 (`SPC b r`)**：对当前打开文件执行重命名；若是 Java 文件，会优先通过 LSP/JDTLS 做安全重构，而不是只改磁盘文件名。
- **删除 (`SPC b d`)**：删除当前打开文件对应的磁盘文件，但保留当前 Vim buffer，便于继续查看、复制或手动另存。

### 7. 跨语言格式串占位符联动高亮
- **覆盖语言**：`c` / `cpp` / `java` / `lua` / `go` / `typescript` / `rust` / `python`。
- **效果**：当光标停在格式串里的占位符上时，会联动高亮对应参数；当光标停在参数上时，也会反向高亮对应占位符。
- **支持格式**：
  - C / Lua / Go / TypeScript / Python / Java `String.format` / `printf` 一类的 `%s` / `%d` 风格；
  - Java `@Slf4j` / `log.info("x {}", value)` 这类 SLF4J 的 `{}` 风格；
  - Rust `println!` / `format!` / `panic!` 一类的 `{}` / `{:?}` 风格。

### 8. 精确跳转与 Copy Reference
- **快捷键**：`<S-f>`、`SPC o f`、`SPC o r`
- **功能**：
  - `<S-f>` 会优先解析当前行里的 Java stack trace、异常类名、`path:line[:col]`、项目内精确文件路径或 Java `com.example.Class#member` 引用并直接跳转；
  - 若当前行不匹配这些格式，则自动回退到原来的 `gF` 行为；
  - `SPC o f` 会弹出输入框，手动输入精确 reference 后跳转；
  - `SPC o r` / `:CopyReference` 会复制当前文件/Java 成员的 reference；Java buffer 优先输出 `com.example.Class#method` 这类形式。

### 9. XML 编辑增强
- **Emmet**：`mattn/emmet-vim` 只在 `html` / `xml` / `css` / `svg` / `xhtml` buffer 里安装映射，默认触发键是 `,,`。
- **标签联动**：在 XML 里修改 `<hello></hello>` 任一侧标签名时，另一侧会跟着改；`<hello/>` 这种自闭合标签不会误改；如果原本就是 `<hello></world>` 这种不匹配状态，也不会强行“修正”另一侧。
- **Treesitter**：现在会一并确保 `yaml` / `json` / `json5` / `toml` 等常用 parser 自动安装。

### 10. 调试配置
- **调试入口**：
  - `:DebugStart`：从项目配置启动调试；
  - `:DebugConfigEdit`：创建/编辑项目级调试配置；
  - `:DebugToggleBreakpoint`：切换当前源码行断点；
  - `:DapAttach 5005`：按端口附加到本机 Java 进程，默认连接 `127.0.0.1:{port}`。
- **自定义 DAP leader 键默认关闭**：为了便于隔离 `nvim-dap` / `nvim-java` 本身的问题，仓库默认不再注册 `SPC d*` / `SPC D*` / `<CR>` 这些自定义 DAP 键位。
- **如需临时恢复旧键位**：可手动执行 `:lua require('user.dap_keymaps').setup()`。
- **调试面板**：现在只保留两个普通 split 面板：最下层是 output，上一层是 locals；断点停住时如果当前焦点在 DAP 面板里，会先切回源码窗口，避免把 locals/output 面板直接替换成源码页。
- **弹窗动作**：
  - 这些动作仍由 `lua/user/dap_ui.lua` 提供，但默认不再绑定到 `SPC d*`。
- **LSP 跳到类**：`SPC l c` 会按类名发起 workspace symbol 搜索，并跳到匹配的类定义；在 Java/JDTLS 下也可跳到依赖里的 `.class` 类型。
- **C/C++ 切换键**：在真实 C/C++ 项目里，`M-y` 和 `<leader>oh` 会切换头文件 / 源文件；`M-h` 改回统一的“切到左侧分屏”。
- **快捷键文件**：旧的 DAP leader 键仍保留在 `lua/user/dap_keymaps.lua`，但默认不自动加载。
- **调试配置文件**：项目根目录下会使用隐藏文件 `.nvim-dap.json` 保存配置列表；`:DebugConfigEdit` 首次打开时会自动生成默认配置。
- **默认模板**：
  - Java 项目默认生成 `port`（按端口 attach）和 `launch`（按 main class 启动）；
  - CMake C++ 项目默认生成 `launch` 和 `attach-process`；
  - 会尽量根据 Maven / Gradle / Eclipse / main class / CMake target 信息生成默认值，并写入 `_detected`；
  - Java 的 `port` 会直接带上检测到的 `mainClass`，这样可以兼容 `nvim-java` 当前的 Java attach 处理；
  - Java 的 `port` / `launch` 都要求当前项目已有活动的 Java LSP，所以先打开一个该项目里的 Java 文件，确认 `:LspInfo` 里有 `jdtls` 这个 Java client，再启动调试；
  - C++ 的 `attach-process` 会先弹出一个搜索框，默认按配置里的进程关键字搜索；只命中一个进程就直接附加，命中多个时会列出线程数和启动参数供选择。

## 测试

运行仓库根目录下的 `./test/run_regression_suite.sh` 会执行当前配置的回归脚本，覆盖：

- 无界面启动 smoke test；
- 现有注释行为测试；
- 悬浮 `vim.ui.select` 行为测试；
- 精确跳转 / Copy Reference 测试；
- 当前 buffer / Dirvish 文件动作测试；
- XML 标签联动与 Emmet 安装测试；
- 直接 JSON DAP 配置模板、命令式启动与端口附加测试；
- Java Spring demo 上的 DAP 命令/动作集成测试（launch 选择、`step_project`、`next`、`repeat_last_action`）；
- DAP 面板 / 自定义命令 / C++ 进程选择测试；
- 跨语言格式串占位符高亮测试；
- 仓库内置 `test-projects/java17-spring-demo/core` 上的 Java LSP 文件重命名集成测试。

### Java LSP 安装

Java 语言服务默认使用 `ProtossGenius/java-lsp`，而不是 Mason 下载的 `jdtls` 二进制。

- 首次安装或手动升级可执行 `:JavaLspInstall`
- 该命令会通过 `go install` 安装：
  - 如果本机存在 `~/workspace/java-lsp`，则直接从本地仓库执行 `go install ./cmd/java-lsp`
  - 否则回退到 `go install github.com/ProtossGenius/java-lsp/cmd/java-lsp@latest`

安装后的二进制会放在 `stdpath('data')/java-lsp/bin/java-lsp`，Java buffer 启动时也会优先使用它。

## Java 示例项目

仓库内置了一个可直接用于手工验证 Java / Spring / Mapper / XML / YAML / Lombok / Slf4j / Maven LSP 行为的示例项目：

- 路径：`test-projects/java17-spring-demo`
- 根标记：`.root`
- 构建：Maven
- Java 版本：17
- 结构：`Controller` / `Model` / `Service` / `ServiceImpl` / `Mapper.java` / `Mapper.xml` / `application.yml`

在该目录下运行 `mvn test` 即可验证项目本身可编译、可启动 Spring 上下文，并能跑通一个基础的 service smoke test。

## C++ 示例项目

仓库内置了一个可直接用于验证 CMake / C++ / 多文件结构 / lldb-dap launch 与进程附加流程的示例项目：

- 路径：`test-projects/cpp-cmake-demo`
- 根标记：`.root`
- 构建：CMake
- 结构：`include/demo/*.h` + `src/*.cpp` + `CMakeLists.txt`

在该目录下运行 `cmake -S . -B build && cmake --build build` 即可完成构建；随后可用生成出来的 `.nvim-dap.json` 直接测试 `launch` 和 `attach-process`。

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

安装阶段还会把打包时机器里的旧 `~/.local/share/nvim` 绝对路径，重写成当前机器的实际 XDG data 路径；因此不只是 `jdtls`，所有 Mason 管理、且在文本 wrapper / launcher 里内嵌了旧路径的 LSP / 工具入口，都会一起被修正，不会继续指向原机器上的旧路径。

`./package_nvim.sh -h` 和生成后的 `target/install.sh -h` 都可查看帮助；传入不支持的参数时会直接展示帮助信息并返回非零状态。
