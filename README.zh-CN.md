# NotesBridge

[English](./README.md) | [简体中文](./README.zh-CN.md) | [Français](./README.fr.md)

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NotesBridge/ci.yml?branch=main&label=CI)](https://github.com/peizh/NotesBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NotesBridge?style=social)](https://github.com/peizh/NotesBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NotesBridge?style=social)](https://github.com/peizh/NotesBridge/network/members)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

![NotesBridge social banner](./images/notesbridge-social.svg)

网站: [notesbridge.peizh.live](https://notesbridge.peizh.live/)

NotesBridge 是一个面向 Apple Notes 的原生 macOS 伴侣应用。它以菜单栏应用的形式运行，在 Apple Notes 之上提供行内编辑增强能力，并将笔记导出为可保存、搜索、版本管理、并可与 AI agents 协作的本地 Markdown 文件和文件夹。

## 状态

NotesBridge 是一个仍在积极开发中的 macOS 伴侣应用，适合那些在 Apple Notes 中接收或整理笔记，但希望将长期可信版本保存在本地 Markdown 文件和文件夹中的用户。

当前版本主要聚焦于两项工作：

- 增加 Apple Notes macOS 版本的编辑体验，提供增强行内编辑工具，例如 slash commands 和 markdown-style 触发器
- 将 Apple Notes 同步到本地优先、类似 Obsidian 仓库的本地文件夹中，并保留文件夹结构、附件、front matter 和内部链接等元素

Apple Notes 很适合在手机上轻松编辑，也适合与家人和朋友共享笔记。NotesBridge 会把这些共享输入转化为一个更便于组织、自动化、版本管理以及与 AI agents 协作的 Markdown 工作区。

如果你已经使用 Apple Notes 进行记录，再使用 Obsidian 或其他本地优先的笔记应用做长期整理，那么 NotesBridge 就是为这种工作流设计的。

## 为什么值得试

- 直接在 Apple Notes 之上使用 slash commands 和行内格式化工具。
- 以轻量 macOS 菜单栏应用的方式运行，而不是替换你现有的记笔记流程。
- 将 Apple Notes 的结构保留为真实的 Markdown 文件和文件夹。
- 保留原生附件、扫描件导出、表格和内部笔记链接。
- 让同步后的笔记更易于搜索、版本管理和交给 AI agents 处理。

## 快速开始

1. 从 [Releases](https://github.com/peizh/NotesBridge/releases) 下载最新的直装版构建。
2. 将 `NotesBridge.app` 移动到 `/Applications`。
3. 启动应用，并授予所需的 macOS 权限。
4. 第一次全量同步时选择你的 Apple Notes 数据目录。
5. 开始将内容同步到你的 Obsidian 仓库。

## 当前能力

- 作为菜单栏伴侣应用运行，并提供轻量级设置窗口。
- 选中文本后弹出浮动格式快捷工具条，提供快捷的文本格式操作，如标题格式、粗体、斜体、删除线等。
- 将行首的 markdown / 列表触发器转换为 Apple Notes 原生格式命令。
- 支持 slash commands，包括行内精确匹配执行和浮动建议菜单。
- 将 Apple Notes 同步到本地文件夹，并导出 front matter 元数据和原生附件。

## 产品约束

Apple Notes 没有公开的插件或扩展 API。因此，NotesBridge 的行为是一个伴侣应用，而不是真正嵌入 Notes 内部的扩展。

当前实现刻意保持保守：

- 行内增强依赖辅助功能权限和事件合成，因此直装版是提供完整体验的主要交付方式。
- 当前主要同步方向仍然是 Apple Notes -> 本地文件夹，没有反向同步功能。
- 当前 slash commands 支持“精确命令 + 空格”的触发方式，以及鼠标驱动的建议项选择，而无需 Input Monitoring。
- 全量同步会提示你选择 macOS 的 `group.com.apple.notes` 数据目录，以便 NotesBridge 直接读取 Apple Notes 数据库和附件文件。

## 赞助

如果 NotesBridge 对你的工作流有帮助，你可以通过 GitHub Sponsor 按钮支持项目的持续维护和发布成本。

赞助将帮助覆盖 bug 修复、版本发布、签名 / notarization 以及项目日常维护所花费的时间。赞助不构成支持 SLA，也不保证功能开发优先级。

## 许可协议

MIT。见 [LICENSE](./LICENSE)。
