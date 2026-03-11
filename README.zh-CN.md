# NotesBridge

[English](./README.md) | [简体中文](./README.zh-CN.md) | [Français](./README.fr.md)

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NoteBridge/ci.yml?branch=main&label=CI)](https://github.com/peizh/NoteBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/network/members)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

![NotesBridge social banner](./images/notesbridge-social.svg)

> 该文档可能会略晚于英文版更新。

NotesBridge 是一个面向 Apple Notes 的原生 macOS 伴侣应用。它以菜单栏应用的形式运行，为 Apple Notes 增加行内编辑增强能力，并将笔记导出到 Obsidian 仓库。

## 项目状态

NotesBridge 仍在持续开发中。当前以直装版 macOS 构建为主要体验形态；Apple Notes 集成依赖本地 macOS 权限以及对 Apple Notes 数据容器的直接访问。

## 当前原型支持

- 以菜单栏伴侣应用方式运行，并提供轻量级设置窗口。
- 在 Apple Notes 位于前台且编辑器获得焦点时进行监听。
- 在支持的构建中，在选中文本上方显示浮动格式工具条。
- 将行首的 Markdown / 列表触发符转换为 Apple Notes 原生格式命令。
- 支持 slash commands，包括精确命令直接执行和浮动建议菜单。
- 将 Apple Notes 同步到 Obsidian 仓库，并导出 front matter 元数据与原生附件。

## 产品约束

Apple Notes 没有公开的插件或扩展 API，因此 NotesBridge 是一个伴侣应用，而不是真正嵌入 Notes 内部的扩展。

当前实现刻意保持保守：

- 行内增强依赖辅助功能权限和事件合成，因此直装版是完整体验的主要载体。
- 可通过 `NOTESBRIDGE_APPSTORE=1` 模拟 App Store 版本；该模式会禁用 Apple Notes 行内增强，但保留设置和同步能力。
- 当前主要同步方向仍然是 Apple Notes -> Obsidian。
- slash command 菜单键盘导航可能需要 Input Monitoring；如果拦截不可用，精确命令加空格和鼠标点选仍然可用。
- 全量同步会提示你选择 macOS 的 `group.com.apple.notes` 数据目录，以便 NotesBridge 直接读取 Apple Notes 数据库和附件文件。

## 构建与运行

```bash
./scripts/run-bundled-app.sh
```

这是推荐的开发入口。它会构建 SwiftPM 可执行文件，将其包装为已签名的 `NotesBridge.app`，并从 `~/Library/Application Support/NotesBridge/NotesBridge.app` 启动该 bundle。

当前 bundled app 使用稳定的 designated requirement，因此辅助功能和 Input Monitoring 权限在重建之后仍可持续绑定。如果你此前授予的是旧版 NotesBridge，而应用仍显示 `Required`，请在系统设置中删除旧条目后重新添加当前 bundled app。

如果只是快速进行非 bundle 运行，也可以使用：

```bash
swift run
```

但 `swift run` 启动的是裸可执行文件，因此依赖真实 app bundle 的 macOS 权限流程，尤其是 slash 菜单键盘导航所需的 Input Monitoring，在这种模式下不会正常工作。

如果你只想重建 `.app` 而不立刻启动：

```bash
./scripts/run-bundled-app.sh --build-only
```

首次以 bundled 方式启动时，macOS 可能会请求辅助功能和自动化权限，以便 NotesBridge 观察 Apple Notes 并同步内容。第一次全量同步还会要求你选择 `~/Library/Group Containers/group.com.apple.notes`，以便应用读取 `NoteStore.sqlite` 和二进制附件。

## 建议的下一步

1. 强化多显示器与全屏空间下的选区锚点和格式工具条定位。
2. 增加更丰富的同步索引和增量笔记变更跟踪能力。
3. 从同一代码库中打包直装版与 App Store 版两个交付物。

## License

MIT。见 [LICENSE](./LICENSE)。
