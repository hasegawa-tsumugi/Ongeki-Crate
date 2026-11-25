# Ongeki-Crate

オンゲキ曲庫検索ツール —— 用 Flutter / Dart 实现的 オンゲキ（O.N.G.E.K.I.）曲库查询 App，面向 Android。

曲库整份存在本地，断网也能查；更新走 jsDelivr / GitHub Raw 四条线路，失败时保留旧版本。

> 非官方作品，与 SEGA 无关。曲名、角色名、谱面数据等权利归 SEGA / 各版权方所有。

## 功能

| | |
| --- | --- |
| 曲库列表 | 全量曲目；可按曲名、角色、版本、分类、等级排序，按 五十音行 / 分类 / 角色 / 版本 / 等级分组 |
| 搜索与筛选 | 曲名即时搜索；难度档位、谱面等级、分类、版本、角色可组合筛选 |
| 曲目详情 | 各难度谱面的定数、物量、谱面设计者、对战角色、谱面链接 |
| 设置 | 主题（浅色 / 深色 / 跟随系统）、字体方案、字号 |
| 关于 | 曲库条目数与快照版本、检查更新、删除本地曲库、第三方许可 |

底栏左侧是装三个页签的玻璃胶囊，右侧是一颗独立的圆形搜索钮。「工具」页尚未实现；「我的」页目前只挂设置与关于两个入口。

## 技术要点

- **底栏玻璃来自 [`fluid_glass`](https://pub.dev/packages/fluid_glass)**（Kyant0/AndroidLiquidGlass 的 Flutter 移植）。本项目不自己写 shader，用它的 `LiquidBottomTabs` 与 `LiquidButton`。
- 该包被整份 copy 到 `third_party/fluid_glass` 打了两处补丁：面板模糊 8dp → 2dp（与右侧按钮一致）、描边羽化 0.25dp → 1.0dp。差异见 `third_party/fluid_glass/PATCHES.md`，`pubspec.yaml` 用 `dependency_overrides` 钉住这份副本。
- 库依赖的是 `material_ui`，因此全项目统一 `import 'package:material_ui/material_ui.dart'`，不要混用 SDK 的 `flutter/material.dart`（两套类型不通用）。
- 折射（refraction）只在 **Impeller** 下生效。`flutter test` 跑在 Skia 上，截图里没有折射，只能核对版式与配色。

## 数据

曲库来自 [otoge-db](https://github.com/hasegawa-tsumugi/otoge-db)（`ongeki` 目录，`music-ex.json`），随包附一份快照 `assets/songs-2026.10.15.json`，首次启动即可离线使用。曲绘走 jsDelivr / `otoge-db.net` 并按 URL 落盘缓存。

解析层对上游字段漂移有校验（定数、难度字段、条目数阈值），校验不过就拒绝替换本地曲库，不会把坏数据写进去。

## 目录

```
lib/
  main.dart            入口（FluidGlass 初始化）
  src/
    app.dart           根组件、路由、首页列表与排序/筛选状态
    screens.dart       设置 / 详情 / 搜索与筛选 / 关于
    bottom_bar.dart    底栏（fluid_glass 组件 + 本项目几何常量）
    domain.dart        领域模型、排序分组、上游数据校验
    repository.dart    数据下载、四线路重试、本地缓存
    theme.dart         配色、字体方案、字号
    version.dart       版本号（与 pubspec 的 version 同步）
assets/
  songs-*.json         曲库快照
  fonts/               随包字体 + 许可文本
  tex/                 背景纹理
third_party/fluid_glass 打补丁的玻璃库副本
tool/check_apk.py      安装包体检（45 项）
test/                  单元 / 组件 / 截图测试
```

## 构建

```bash
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64
```

只出 arm64。`versionCode` 固定写在 `android/app/build.gradle.kts`（当前 12），不随版本递增。

## 版本约定

- `pubspec.yaml` 的 `version` 与 `lib/src/version.dart` 的 `appVersion` / `appBeta` 必须一致，`test/version_sync_test.dart` 会逐字比对。
- 每次发版主版本 +0.0.1；测试包写成 `0.1.2-beta1`、`0.1.2-beta2`……（`appBeta` 递增），正式版去掉后缀、`appBeta = 0`。

## 字体

| 字体 | 用途 | 许可 |
| --- | --- | --- |
| Josefin Sans | 拉丁与数字（official 方案） | SIL OFL 1.1 |
| M PLUS 1p | 日文 | SIL OFL 1.1 |
| MiSans | 中文补字 | 随包注明使用 |
| SEGA 丸ゴシック | 曲目内容 | 版权归 SEGA，仅随包自用 |

许可全文随包分发（`assets/fonts/`），App 内「关于 → 字体与第三方许可」可查看。
