# MacFind

中文 | [English](README.md)

一个基于 Spotlight 索引的 macOS 文件搜索面板 —— 自用的 Spotlight UI 替代品。

<p align="center"><img src="docs/icon.png" width="128" alt="MacFind 图标"></p>

MacFind **不自建索引**。它通过 `NSMetadataQuery` **在进程内查询系统 Spotlight 索引**,全盘文件名搜索几百毫秒返回 —— 没有常驻 daemon、没有本地数据库、走 Spotlight 路径时也**不需要完全磁盘访问权限(FDA)**。

> 如果你不喜欢 Spotlight 的界面、但认可它的索引,这个薄壳就是为你准备的。

## 功能

- 全盘文件名搜索(Spotlight 索引)
- 富过滤:`ext:` / `size:` / `date:` / `kind:` / `in:` 与 `!` 取反
- 输入即实时收窄(100ms debounce)
- 结果表(名称 / 大小 / 修改时间 / 路径),默认按修改时间倒序
- 打开、在 Finder 中显示、复制路径
- 单实例(`LSMultipleInstancesProhibited` + 运行时兜底)
- 零网络调用、零遥测
- 仅 macOS 13+ / Apple Silicon (arm64)

## 查询语法

查询请用**单引号**包裹,避免 shell 吃掉特殊字符。

| 过滤器 | 示例 | 含义 |
|---|---|---|
| 普通文本 | `'report'` | 文件名含 `report` |
| 取反 | `'!ext:tmp'` | 排除 `.tmp` |
| `ext:` | `'ext:pdf,epub'` | 扩展名(逗号分隔) |
| `size:` | `'size:>10M'`、`'size:<=1K'` | `>` `>=` `<` `<=`,后缀 `K`/`M`/`G` |
| `date:` | `'date:7d'`、`'date:today'`、`'date:>2024-01-01'` | 修改时间晚于… |
| `kind:` | `'kind:file'`、`'kind:dir'`、`'kind:symlink'` | 类型 |
| `in:` | `'in:~/Downloads'` | 限定目录(`~` 由 MacFind 展开) |
| `name:` | `'name:config'` | 只匹配文件名 |

```sh
report
ext:pdf size:>5M
in:~/Downloads ext:zip
'!node_modules' ext:ts
date:today ext:log
```

## 构建与运行

需要 **Xcode**(工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成)。

```sh
git clone https://github.com/nekoinosaka/MacFind.git
cd MacFind

brew install xcodegen        # 若未安装
xcodegen generate            # 由 project.yml 生成 MacFindApp.xcodeproj

xcodebuild -project MacFindApp.xcodeproj -scheme MacFindApp \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/MacFind.app
```

或直接用 Xcode 打开 `MacFindApp.xcodeproj`,按 ⌘R。

### 安装到 /Applications

```sh
rm -rf /Applications/MacFind.app
ditto build/Build/Products/Release/MacFind.app /Applications/MacFind.app
codesign --force --deep --sign - /Applications/MacFind.app
```

## 测试

```sh
xcodebuild test -project MacFindApp.xcodeproj -scheme MacFindApp -destination 'platform=macOS'
```

共 19 个:16 个查询 DSL 解析用例 + 3 个针对真实 Spotlight 索引的端到端用例。

## 目录结构

```
MacFindApp/
├── project.yml                 # XcodeGen 定义(真源)
├── MacFindKit/                 # 查询层(静态库,单测无需启动 GUI)
│   ├── QueryParser.swift       # DSL -> NSPredicate
│   ├── SpotlightBackend.swift  # NSMetadataQuery 封装
│   └── ResultItem.swift
├── MacFindApp/                 # SwiftUI 应用
│   ├── ContentView.swift       # 搜索框 + Table + 状态行
│   ├── SearchViewModel.swift   # 输入 debounce + 结果操作
│   └── AppDelegate.swift       # 单实例守卫
├── MacFindKitTests/            # 16 解析 + 3 Spotlight 集成测试
└── Tools/make_icon.swift       # CoreGraphics 图标生成脚本
```

## 已知限制

- **依赖 Spotlight 索引。** `.git` 与隐藏目录内的文件不在索引里,搜不到;刚创建的文件可能有几秒延迟。
- 结果确定性取决于 Spotlight —— 它可能静默遗漏。
- **不做内容搜索**(请用 [`ripgrep`](https://github.com/BurntSushi/ripgrep))。
- 外接卷仅在 Spotlight 索引了它时才可搜。
- 仅 macOS 13+ / Apple Silicon (arm64)。

## 实现注记

- 查询层放在独立的 `MacFindKit` 静态库,测试目标因此无需启动 GUI 宿主。
- `NSMetadataQuery` 只接受 metadata 谓词:它**拒绝** `NSPredicate(value: true)`,也**拒绝**只有一个子谓词的 `NSCompoundPredicate` —— 两处都已在 `QueryParser` / `SpotlightBackend` 中处理。
- 图标由代码生成:`swift Tools/make_icon.swift <输出.iconset>`,再 `iconutil -c icns <输出.iconset> -o MacFindApp/Resources/AppIcon.icns`。
