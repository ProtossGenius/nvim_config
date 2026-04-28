# Java / Lombok / LSP / Leader 键说明

## 1. 这次补了什么

这套配置现在额外接入了以下插件：

- `nvim-java/nvim-java`：接管 Java 专项支持，补齐 JDTLS、class file/decompile、Lombok、测试/运行命令。
- `folke/which-key.nvim`：在按下前缀键时显示底部按键提示，风格接近 Doom。
- `ahmedkhalf/project.nvim`：让原来的 `:Telescope projects` 真正可用。

同时保留了原有快捷键，并为常用操作补了一套基于 `Space` 的 leader 映射。

## 2. Java 现在的行为

### 2.1 跳转到 JDK / JAR / 系统包

现在 Java 里：

- `gd`
- `<C-]>`
- `SPC l d`

都会走 LSP definition。对于 `String`、JAR 里的类、外部依赖类，优先打开源码；如果没有源码，就打开反编译后的 class 内容。

### 2.2 Lombok 支持

已经打开 `nvim-java` 的 Lombok 支持；它会在启动 JDTLS 时注入 `lombok` agent，所以语言服务器能感知 `@Data` 一类注解生成的成员。

这意味着在大多数正常配置的 Lombok 项目里：

- 自动补全可以看到 getter / setter / builder 等生成成员；
- hover / definition / references 能识别这些成员的类型与来源；
- 在字段上执行重命名时，外部对生成访问器的调用通常也能跟着更新。

这次配置里，`person.getName()` 这类外部调用已经能够被解析回 `Person.java`；把字段 `name` 重命名为 `fullName` 时，外部调用会同步变成 `getFullName()`。

### 2.3 Lombok 的边界

仍然有两个前提：

1. 你的 Maven / Gradle 项目本身要正确声明 Lombok 依赖；
2. 更推荐在“字段”或“类”本身上做重命名，而不是把生成出来的 `getXxx()` / `setXxx()` 当成普通手写方法去改名。

也就是说，这次已经把 **Neovim 侧** 的 Lombok 感知链路补齐了；如果项目本身没配好 Lombok，LSP 还是无法凭空推断。

## 3. which-key 提示

现在按下这些前缀后，会在底部弹出提示：

- `Space`
- `g`
- `z`
- `<C-w>`

其中最常用的是：

- `SPC ?`：查看当前 buffer 的可用快捷键；
- `SPC l`：LSP；
- `SPC j`：Java；
- `SPC f`：查找；
- `SPC w`：窗口；
- `SPC x`：诊断；
- `SPC m`：make / build。

视觉模式下的 leader 提示也补齐了显式注册，像选中文本后按 `SPC o t`，which-key 会直接显示翻译动作说明，而不是泛化成 `1+ mappings`。

## 4. 常用 leader 映射

> 说明：下面是“新增或重点整理后的” Space leader 入口；原有快捷键仍然保留。

### 4.1 LSP

| Leader | 作用 | 旧快捷键 |
| :--- | :--- | :--- |
| `SPC l d` | 跳到定义 | `gd`, `<C-]>` |
| `SPC l D` | 跳到声明 | `gD` |
| `SPC l r` | 查看引用 | `gr` |
| `SPC l i` | 跳到实现 | - |
| `SPC l t` | 跳到类型定义 | - |
| `SPC l h` | Hover 文档 | `K` |
| `SPC l a` | Code Action | `ff` |
| `SPC l R` | 重命名 | `<leader>rn` |
| `SPC l s` | 当前文件符号 | `<leader>ds` |
| `SPC l S` | 工作区符号 | - |
| `SPC l e` | 当前行诊断 | `<leader>e` |
| `SPC l n` | 下一条诊断 | `<M-n>` |
| `SPC l p` | 上一条诊断 | `<M-p>` |
| `SPC l f` | 格式化当前 buffer | 自动保存格式化仍保留 |

### 4.2 Java

| Leader | 作用 |
| :--- | :--- |
| `SPC j o` | organize imports |
| `SPC j v` | 提取变量 |
| `SPC j V` | 提取变量（全部出现处） |
| `SPC j c` | 提取常量 |
| `SPC j m` | 提取方法 |
| `SPC j f` | 提取字段 |
| `SPC j r` | 运行当前 main |
| `SPC j s` | 停止当前 main |
| `SPC j l` | 打开/关闭运行日志 |
| `SPC j t c` | 运行当前测试类 |
| `SPC j t m` | 运行当前测试方法 |
| `SPC j t r` | 查看最近一次测试报告 |
| `SPC j j` | 切换 Java runtime |

## 4.3 查找 / 文件 / 项目

| Leader | 作用 | 原快捷键 |
| :--- | :--- | :--- |
| `SPC f a` | 查找所有文件（含隐藏文件） | `<C-p>` |
| `SPC f b` | 查找 buffer | `<A-r>` |
| `SPC f g` | 全局 grep | `<A-f>` |
| `SPC f r` | 最近文件 | `<C-n>` |
| `SPC f t` | tags | `<leader>ts` |
| `SPC f f` | Git tracked files | 原映射保留 |
| `SPC f h` | help tags | 原映射保留 |
| `SPC p p` | 项目列表 | `<leader>p` |

## 4.4 窗口 / 诊断 / 构建 / 终端

| Leader | 作用 | 原快捷键 |
| :--- | :--- | :--- |
| `SPC w h/j/k/l` | 窗口切换 | `SPC ←/↓/↑/→` |
| `SPC w v` | 垂直分屏 | `<leader>sv` |
| `SPC x n` | 下一条诊断 | `<M-n>` |
| `SPC x p` | 上一条诊断 | `<M-p>` |
| `SPC x e` | 当前行诊断 | `<leader>e` |
| `SPC t t` | 浮动终端开关 | `<M-t>` |
| `SPC m r` | `make qrun` | `<F5>` |
| `SPC m m` | `make` | `<F6>` |
| `SPC m t` | `make tests` | `<F8>` |
| `SPC m d` | `make debug` | `<F9>` |
| `SPC o h` | C/C++ 头源切换 | `<M-h>` |
| `SPC o a` | Aerial 大纲开关 | `<leader>a` |

## 5. 第一次使用 Java 的注意事项

第一次启用这套配置，或第一次真正打开 Java 项目时，`nvim-java` 可能会自动准备：

- JDTLS
- Lombok
- Java test / debug 支持
- 它需要的运行时 JDK

这是正常现象。准备完成后，后续进入 Java 项目的体验会稳定很多。

另外，配置里也把 `jdtls` 加进了 Mason 的默认安装列表；在一台全新的机器上，只要装好这套 Neovim 配置，首次进入 Java 项目时也会自动补齐并启用对应语言服务，而不需要手动先装系统级 `jdtls`。

这次没有额外叠加 `nvim-jdtls`。原因是它更偏向手工配置：README 明确写了更适合“偏好 configuration as code、且不把易用性放在首位”的用户；而 `nvim-java` 这边已经覆盖了 JDTLS、Lombok、测试、调试、运行器和 Spring 支持，并且它自己的配置项里还带有 `nvim_jdtls_conflict` 检查。对这份仓库来说，继续保持单一的 `nvim-java + jdtls` 方案更稳，也更省维护成本。
