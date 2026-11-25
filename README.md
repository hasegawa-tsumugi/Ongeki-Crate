# Ongeki-Crate

オンゲキ曲庫検索ツール — 独立于原 Expo / React Native 项目，采用 Flutter/Dart 实现オンゲキ曲库查询。当前处于 Android 迁移阶段；原项目保留未改。

## 底部导航栏（2026-11-24 12:30）

按效果图（Google 电话 App 的悬浮底栏）重做底部：左侧一颗液态玻璃胶囊装三个页签，右侧一个独立玻璃圆钮做搜索入口（无色透明、无阴影，2026-11-24 晚按用户要求撤掉绿色与投影）。**原来左下菜单钮 + 右下搜索钮全部撤掉**。

| 元素 | 效果图实测（px / 1286 宽） | 实现（按屏宽比例） |
| --- | --- | --- |
| 左右外边距 | 166 = 12.9% | `insetOf` = 12.9%，clamp 16–56 |
| 胶囊高＝圆钮直径 | 164 = 12.75% | `heightOf` = 12.75%，clamp 40–64 |
| 胶囊与圆钮间隙 | 39 = 3.03% | `gapOf` = 3.03%，clamp 8–16 |
| 距屏幕底边 | 115 = 8.94% | `bottomOf` = 8.94%，且不小于安全区 + 8 |

胶囊内三格等分，选中格铺满整高（效果图里选中块与胶囊同高，不是「里面再放一个小按钮」）。图标在上、文字在下，页签文字**不跟系统字号缩放** —— 底栏高度是按屏宽算的固定值，跟着放大先挤爆的是三个两字标签。

**横屏要另压一道**：高度光按屏宽算，568×240 会得出 72dp（屏高才 240）。所以 `heightOf` 同时受「屏高 14%」约束，`bottomOf` 受「屏高 10%」约束，竖屏完全不受影响。

### 页面结构

三个页签用 `IndexedStack` 同框，切回去时列表滚动位置、搜索框里的字都还在（push/pop 换页会丢）。「工具」「我的」是占位页，但**「我的」里挂了两行入口：设置 / 关于** —— 菜单钮撤掉之后，这是主题、字体方案、曲库更新与删除的唯一通路，少一条就是功能失联。

push 上来的页面（详情、搜索与筛选、设置、关于）一律不带底栏，`AppPage` 里那段「按需渲染底栏」的逻辑整段删掉了。

### 材质：Kyant0 lens shader 的逐行移植

`assets/shader/glass.frag` 移植自 [AndroidLiquidGlass](https://github.com/Kyant0/AndroidLiquidGlass) 的 `RoundedRectRefractionShaderString`（`backdrop/.../internal/Shaders.kt`，Apache-2.0）：圆角矩形 SDF + 解析梯度 + `circleMap` 圆弧位移轮廓 + 1.5× 圆角的梯度平滑 + `vibrancy`（饱和 ×1.5）。管线与它家一致：`vibrancy ⇒ blur ⇒ lens`，表面色用 `LiquidBottomTabs` 的色值（0xFFFAFAFA / 0xFF121212），透明度按用户要求：**面板 5% 不透明（95% 透明）、拖拽拇指 3%**（参考原配面板是 40%）。

参数取自 demo 调参页（`GlassPlaygroundContent.kt`）的映射 + 用户指定滑杆值 `Blur radius 10%` / `Refraction height 20%` / `Refraction amount 20%` / `Chromatic aberration 0`：模糊 = 10%×32dp = **3.2dp**（绝对值）、折射带 = 0.2×minDim×0.5 = **6.4dp**（minDim = 玻璃件高）、位移 = 0.2×minDim = **12.8dp**、色散恒关、**depthEffect 恒开**（参考卡片 effects 块固定 `depthEffect = true`）。注意 demo 的折射带映射含 ×0.5，20% 的滑杆值 = 10% 件高，不是 20% 件高。（参考图滑杆像素实测 4dp / 23.7% / 23.4% / 0，与字面值差 <20%，按字面值实现。）`LiquidBottomTabs` 原配参数（blur 8dp + lens 24dp/24dp + 拇指色散）整份存档在 `presets/20261124-liquidbottomtabs-strict/`，要换回拷回去即可。

**边缘翻折是效果本身**：`circleMap: 1-√(1-x²)` 在边缘斜率无穷大，amount = 带高时映射在带内约三成处折返，背景翻折压缩 —— 这就是「厚玻璃透镜」的边缘质感。把 amount 压到带高一半以下能压住翻折，代价是退回磨砂玻璃。（旧版曾把翻折当伪影修掉、amount 改挂带宽，位移缩水 5 倍，效果发闷 —— 已改回。）

**与原版只差两处**：① 位移方向取 `-grad`（朝内采样）。原版朝外采样依赖 drawBackdrop 捕获时外扩 padding 环的真实背景；Flutter 的 BackdropFilter 纹理正好等于控件边界、外面没有内容，朝外采样会 clamp 出死色边。模糊层在下、边缘内外背景连续，朝内采样观感等价。② vibrancy 搬进 shader —— 饱和是线性变换、模糊是线性卷积，两者可交换，与原管线 `vibrancy ⇒ blur ⇒ lens` 等价。

**为什么用两层 `BackdropFilter` 而不是 `ImageFilter.compose`**：compose 的内层模糊会把输入纹理向外扩张 3σ，外层 shader 拿到的纹理比控件大一圈，`FlutterFragCoord()/uSize` 全跟着偏，圆角对齐会错位。拆成两层后，每层的输入都是 `ClipRRect` 的裁剪区，纹理尺寸正好等于控件尺寸。第一层糊背景，第二层读到的正是糊过的那张，顺序天然成立。

**三条引擎约束**（写在 `glass.frag` 里）：第一个 uniform 必须是 `vec2`，由引擎写入纹理尺寸，代码不许 `setFloat(0/1)`；至少一个 `sampler2D`，第一个由引擎绑定；GLES 后端 y 轴反向，要按 `IMPELLER_TARGET_OPENGLES` 翻一次。

**只在 Impeller 下生效**。`ImageFilter.shader` 在 Skia 上直接抛 `UnsupportedError`，所以用 `isShaderFilterSupported` 门控，加载失败一律退回磨砂玻璃 —— 观感降级可以接受，黑一块不行。

### 验证方式

`test/glass_render_test.dart` 把这份 `.frag` **真的跑起来**（`Paint.shader` 在 Skia 上能用），断言：左边缘变亮、右边缘变暗（梯度与偏移方向都对）、折返区区域极值（circleMap 翻折的指纹）、横向中部逐位不变、四个圆角之外全透明、窄折射带在带外零位移。覆盖不到的只剩「`BackdropFilter` 给 shader 的坐标语义」，那个只能在真机上看。

`test/glass_shader_test.dart` 守装配与移植保真：核心数学指纹（circleMap / 解析梯度 / 1.5× 平滑 / vibrancy）不许被换、`pubspec` 声明路径与加载路径一致、第一个 uniform 是 `vec2`、代码不碰第 0/1 位、amount 挂高度不挂带宽。`tool/preview_glass.py` 出离线原型图（位移场 + 合成对比），改参数前先在这里看。

**描边不能写 `Container.decoration.border`**：Container 会把描边宽度当 padding 塞给子节点，胶囊内三格整体内缩 1px、等分跟着偏，玻璃层和描边框之间还会露出 1px 缝。所以走 `_RimPainter` 自绘（描 `kRimStrokeDp` 的两倍宽、clip 掉外侧一半）。描边留着：浅色主题下 5% 白玻璃（95% 透明）压在近白底上，没有轮廓立不住形。

#### 描边为什么曾经显得「模糊」（2026-11-24 实测）

用户反馈「按键边框有些模糊」。**先量再改**，结论和直觉相反：

| 方案 | 厚度 | 模糊 σ | 白强度 | 深色剖面（物理像素） | 结论 |
|---|---|---|---|---|---|
| A 原版 | .5dp | .25 | .5 | `27 28 29 28 124 169 126 105` | 峰 169、过渡跨 2px，**糊** |
| B | .5dp | **0** | .5 | `29 28 125 182 185 122` | 峰只涨到 185，**几乎没改善** |
| C | .5dp | 0 | .85 | `29 28 161 245 248 137` | 亮了，但线仍太细 |
| **E（采用）** | **1dp** | **0** | **.85** | `28 29 28 161 245 248 137` | 峰 248、边缘清晰 |

三个发现：

1. **去掉模糊帮助极小**（A→B 峰值 169→185）。真正的病灶是**线太细**：0.5dp 在 dpr 3 下可见 1.5 物理像素，抗锯齿必然把线摊到两列上，中间那个 `124/125` 的半灰就是糊的来源。
2. **表面色透明度跟它是联动的**。参考项目的 `Highlight` 白强度 0.5 是配 40% 表面色设计的；本项目表面色只有 5%（95% 透明），底色明暗跨度更大，0.5 压不住 → 必须提到 **0.85**。
3. **像素对齐（painter 内部把尺寸吸到 1/dpr 网格）无效** —— 实测剖面与不对齐时几乎一致。因为底栏的 y 坐标本身落在半像素上，painter 内部对齐改变不了整个组件的亚像素偏移。想做真对齐得动布局，收益不抵风险，**已放弃**。

`test/glass_shader_test.dart` 加了护栏：`kRimBlurSigma` 必须为 0（带 reason 说明剖面中间灰的问题）、`kRimStrokeDp ∈ [.5, 2]`、`kRimInk == kRimWhite × kRimNormalDot`。

四个旋钮都在 `bottom_bar.dart` 顶部：`kRimStrokeDp` / `kRimBlurSigma` / `kRimWhite` / `kRimNormalDot`。

### 两处取舍

- **搜索钮的绿色已撤**（2026-11-24 晚）：按用户要求改无色透明玻璃圆钮（玻璃管线同面板、表面色 5%）。**左右两件玻璃均无投影**（`_Glass` 的 Shadow.Default 整个移除）——用户要求「按键下方不应该有阴影」且左右效果必须一致。效果图那颗绿钮只保留了尺寸与位置。
- **网页版没同步**：这轮只改 App。网页单文件里仍是旧的两个圆钮，双端要一致的话得另排一轮（`tool/webapp/index.template.html` 的 `.circle` 那套）。

验证：测试 **333 通过 / 1 跳过**；`corner_layout_test` 36 组（4 尺寸 × 2 字号 × 3 安全区）逐项断言外边距/高度/间隙/底距/三格等分；analyze 干净。

## 排序三栏改用游戏原文（2026-11-24 01:30）

用户拍板：**「不要翻译直接用原文」**，只有一处待定项选了「不带（標準）」。

三个下拉的 18 个选项全部换成表格「日文原名」列的原文，不再译成中文。原来那套译名（分类 / 角色 / 版本 / 推荐顺序 / 对手等级…）在还原游戏ソート設定这件事上是负资产 —— 玩家在游戏里看到的是 `ジャンル`、`オススメ順`，翻成中文反而对不上。

| 栏 | 原文选项 |
| --- | --- |
| タブ設定 | ジャンル / 全曲 / キャラクター / バージョン / 譜面レベル / 曲名 / 属性（灰） |
| タブ内 楽曲ソート | オススメ順 / バトルスコア順（灰）/ テクニカルスコア順（灰）/ プラチナスコア順（灰）/ 対戦相手のレベル順 / 曲名順 / 追加日順 / チャプター順 |
| ライバルスコア | テクニカルスコア / バトルスコア / プラチナスコア（整栏灰） |

**（標準）不加**：表格 C 列三个默认项写作 `ジャンル（標準）`，但那个后缀和 E 列的 ★ 是同一个信息（「默认」），游戏里下拉也只显示 `ジャンル`。默认项靠排在第一位体现。

**范围只到这三栏**：详情页的信息行（`版本` / `分类` / `对战角色`…）、搜索框占位文案、状态条里除选项名以外的字都是中文，没动。状态条因此长这样：`列表排序 · ジャンル › オススメ順`。

### 选项变长后的两处连带

- `対戦相手のレベル順` 有 10 个字（原「对手等级」4 个）。`sort_sheet_shot_test.dart` 里 320dp × 2.0 那条用例原来只验默认值，现在逐栏换成**最长的选项**再断言不溢出 —— 默认值是最短的三个，最坏情况从没上过场。
- `check_apk.py` 的包内文案断言同步换成原文，并把旧译名（`推荐顺序` / `对手等级` / `章节顺`）移进 `MUST_ABSENT`：漏改某一处会直接红，而不是悄悄混一个中文进去。
- 新增 `sort-options-{light,dark}.png` 出图用例，专门截「展开下拉看 8 个选项」——这是本轮唯一改到的东西，光看截图里的收起态看不出对错。

### 包身份改成直接读 manifest

以前 `check_apk.py` 验版本只有一条：在 `libapp.so` 里 grep `0.1.1+8`。那是**关于页显示的字**，不是**安装时判定新旧的字段**——两者可以不同步（pubspec 改了而构建缓存给出旧 manifest），而且 grep 命中一条字符串也证明不了它真挂在 `manifest` 上。`versionCode` 更彻底：它是整数，压根不在字符串池里，永远 grep 不到。

现在按 AXML 的 chunk 结构解析二进制 `AndroidManifest.xml`，直接从属性表取 `package` / `versionName` / `versionCode`，与 `pubspec.yaml` 的 `version` 逐项比对（`manifest_identity()` 函数，无第三方依赖、不需要装 Android SDK）：

```
[PASS] manifest 可解析
[PASS] 包名  dev.tsumugi.songquery
[PASS] versionName 与 pubspec 一致  manifest 0.1.1 / pubspec 0.1.1
[PASS] versionCode 与 pubspec 一致  manifest 8 / pubspec 8
```

解析失败一律判 FAIL，不静默跳过。反向验证：拿 build7 的旧包跑，明确报 `manifest 0.1.0 / pubspec 0.1.1`、`manifest 7 / pubspec 8`，exit 1。**这条能拦住「桌面上抓错包交付」**——文件名是人起的，manifest 不是。

**本轮交付（0.1.1+8）**：`songquery-v0.1.1-build8-arm64-release-20261124-0137.apk`，28,604,924 字节，md5 `86f3905bbe2ddd8fc974041bacaa0118`，`versionCode 8 / versionName 0.1.1`，仅 `arm64-v8a`。`check_apk.py` **34/34**；双端对拍 30/30 组合 0 差异；网页 120/120；浅色对比度 ALL PASS；测试 315 通过 / 1 跳过。网页同步重打：`songquery-web-v0.1.1-20261124-0137.html`。

**build number 没归零**：版本名升到 `0.1.1`，versionCode 仍从 7 递增到 8。Android 要求 versionCode 单调递增，归零会被当降级包拒装。

**2026-11-24 起发版约定（用户指示，两次变更后的最终版）**：

1. **版本号每次发版 +0.0.1**（0.1.1 → 0.1.2 → 0.1.3）。
2. **build 号彻底取消**，任何地方都不再出现 `+N`：
   - `pubspec.yaml` 只写纯版本名，如 `version: 0.1.2-beta1`（没有 `+12`）
   - `versionCode` 改为在 `android/app/build.gradle.kts` 里**写死 12**，不再跟版本联动。它是安装时判新旧的整数，侧载场景同 code 同签名可以覆盖安装，不需要递增；只有上架应用商店才要求递增
   - APK 文件名、关于页都不出现 build 号
3. **默认出 beta**：`0.1.2-beta1`、`0.1.2-beta2`……beta 数字每次出包 +1。
   **只有用户明确说「出正式版」时才去掉 beta**，写成 `0.1.2`。
   文件名形如 `songquery-v0.1.2-beta1-arm64-release-YYYYMMDD-HHMM.apk`。

对应代码：`lib/src/version.dart` 用 `appVersion` + `appBeta` 拼 `appVersionLabel`
（`appBeta = 0` 即正式版，拼出的标签不带后缀）。`test/version_sync_test.dart` 三条护栏
守住「与 pubspec 一致 / 不含 `+N` / beta 格式正确」。`check_apk.py` 的 versionCode
断言改为读 `build.gradle.kts` 里的写死值。

**注意**：pubspec 去掉 `+N` 后，Flutter 不再写 `flutter.versionCode`，若 gradle 里的
`versionCode = flutter.versionCode` 会得到空值 —— 所以那一行必须保留为常数，
不能改回去。

## 分组排序加固（2026-11-24）

三栏排序（分组 / 段内排序 / 对手分数）落地之后的本轮只做加固，**不动任何界面样式**。

### 一、比较器里不再重算组标签（18.8ms → 6.3ms）

`listGrouped` 原来在比较函数里现算 `groupLabelOf(a)`：`kanaRow` 要遍历假名行表，`topLevel` 每次访问都会重建并排序 `playableCharts`，于是「谱面等级 / 对手等级」18.78ms、「曲名 / 章节」18.06ms，而「分类 / 推荐」只要 5.64ms —— 三倍差距全在这里。改成排序前建一张 `labels` 表，比较器纯查表：

| 组合 | 优化前 | 优化后 |
| --- | --- | --- |
| genre / recommended | 5.64ms | 6.63ms |
| character / title | 3.85ms | 4.04ms |
| title / chapter | 18.06ms | 5.19ms |
| level / enemyLevel | 18.78ms | 6.06ms |

（1112 首，同机 10 次均值；`SONGQUERY_BENCH=1 flutter test test/perf_grouped_test.dart` 可复测。）

耗时类改动功能测试照样全绿，只有真机翻页会顿，所以在 `grouped_sort_test.dart` 里加了一条源码级护栏：`groupLabelOf(a|b)` / `groupRankOf(a|b)` 一旦出现在比较器里就红。

### 二、双端全量对拍（真抓到一个 bug）

网页 `filtered()` 与 `SongEngine.listGrouped` 是同一套规则的两份实现。以前靠人工翻两页比对，样本太小 —— 改成常驻的两条命令：

```
flutter test test/parity_export_test.dart   # -> build/_parity_app.json（6 组 × 5 排序 × 全部曲目）
node tool/check_parity.mjs                  # -> 无头 Chrome 里逐首比对，0 差异才 exit 0
```

跑起来立刻出现 17/30 个组合差异，全部是同分兜底：曲库里有同一首歌的多个版本（`DIE IN` 400643 / 910131 读音都是 `DIEIN`；`夢花火` 与 `ユメハナビ` 都读 `ユメハナヒ`），曲名比不出高下时 App 用 `a.id.compareTo(b.id)` 收尾，网页 `localeCompare` 返回 0 就退化成「保持 payload 原序」。给网页的 `byTitle` 补上 `idAsc` 后 30/30 组合、1112 首逐位一致。

**修复前后都跑过同一套对拍**，所以这次不是「看起来对了」，是「同一把尺子先报 17 个错、再报 0 个错」。

### 三、两处「静默通过」的体检脚本

- `tool/verify_button_layers.mjs` 还在点 `#btnDetailMenu` 和 `#sortSel`。前者是 11-21 撤掉的详情页菜单钮，后者已被三栏下拉取代 —— 两个 `null` 选择器让脚本在 `click()` 里抛异常整段中断，后面的检查一条没跑，报告却只写「1 项失败」。改成「详情页确实没有底部控件」的正向断言 + `tabGroupSel/tabSortSel/rivalSel` 三栏，现在 120 项全跑完。
- `tool/check_light_contrast.py` 默认读 `build/webapp.html`，那是 11-21 手工拷的一份快照，页面里根本没有 `tabGroupSel`，于是「排序下拉」长期 `[SKIP]`、结论照样 `ALL PASS`。默认路径改为真实构建产物，并把三栏下拉改成 `required` —— 量不到就判失败而不是跳过。拿旧快照反向验证过：现在会明确报两条 FAIL。

## 整词断行 + 文字底面（2026-11-09 23:55）

两件事：拉丁词不再被从中间劈开；压在背景黄绿斜带上的文字全部收进不透明卡片。

**本轮交付**：`songquery-wordwrap-0.0.1`，BUILD=0（1 分 41 秒），28,557,644 字节（连续第六版同尺寸，**不能拿大小判断是否重编**）。SHA-256 `9bcb706eb560890dc93f3abbbccc4a63cf0ed059bd0432da8e80f1ec8ba4b788`；`libapp.so` 5,964,680 / CRC `3424156747` → **`2292658115`**（新增代码落在同一个 64KB 对齐档里，所以 so 长度没变）。`check_apk` 20/20；三份副本哈希一致：构建产物 / `outputs/songquery-wordwrap-0.0.1.apk` / 桌面 `songquery-wordwrap-0.0.1-20261109-235641.apk`。

### 一、整词断行（`WordSafeText`，`lib/src/theme.dart`）

先量清楚再动手，结论和直觉相反：

- **数据里的曲名大量使用全角英数**。`card_real` 那首真名是 `ＧＯ！ＧＯ！ラブリズム♥`（U+FF27…），不是半角 `GO!GO!`。全角英数在换行算法里算「表意字符」，**任意两字之间都可断**，所以断成了「ＧＯ！Ｇ / Ｏ！」—— 这不是 emergency break，是合法断点。第一版把全角区（`\uFF00–\uFFEF`）整块当可断，等于没修，卡片截图字节都没变；改成只让半角片假名（U+FF61–FF9F）与全角符号（U+FFE0–FFEE）可断，全角英数归入「词」，才真正生效。
- 半角拉丁串只在「整段比行宽还宽」时才被硬断（`HOLIDAYS` 那种是同一个成因：它前面没有空格、整段放不下）。

实现：`unbreakableUnits()` 按「中日文/空白」切段，只对长度 × em > 行宽的段做 `TextPainter` 实测（绝大多数文本一次都不量），取 `maxWidth / 最宽段宽 × .99` 作字号比例，**一个字都不删**（沿用 11-02 的「不截断」规矩）。

| 位置 | 基准字号 | 下限 | 320@2.0 实际 |
|---|---|---|---|
| 卡片曲名 | 17（narrow） | .72 | 17 → **15.34**，`ＧＯ！ＧＯ！` 整段一行 |
| 卡片作者 | 13 | .62 | 只在长串上触发 |
| 详情页曲名/作者/`_Meta` 值/谱师 | — | .72 / .62 | 按可用宽度自行量 |

**`maxWidth` 必须由调用方传**：卡片内部有 `IntrinsicHeight`，里面再放 `LayoutBuilder` 会在测量阶段抛「不支持 intrinsic dimensions」，所以卡片的文字列宽度在 `build` 里按「屏宽 − 30 − 24 − 封面 − 间距 − 6」自己算好传进去。详情页没有这个问题，省略 `maxWidth` 时组件内部自己包一层 LayoutBuilder。

**封面 88 → 64**（仅 narrow 且字号 ≥ 1.8）：320 宽时文字列只有 162dp，6 个全角字符要 204dp，标题要么断词、要么缩到 26.7 —— 和作者名（26）一样大，标题层级就没了。让出 24dp 后标题停在 30.7（15.34 × 2），仍是标题。更宽的屏幕文字列本来就够，不动。

### 二、文字底面（设置页 + 搜索页）

背景三条斜带固定在视口 `.64H`，**与滚动无关**，列表一动就会横穿文字。320@2.0 实测「官方混排」的说明被劈成两半、「全部系统字体」整行压在黄带上；搜索页「列表排序 · 默认（固定规则）」同样。斜带位置是定死的配色（用户定的值），所以改的是**文字一侧**：设置页整页收进 `Chamfer(fill: card)`（和「关于」页同一做法），搜索页那两行状态文字收进一张小卡片。

踩坑：`RadioListTile` 放进带底色的 `DecoratedBox` 里会触发 `ListTile background color or ink splashes may be invisible` 断言，得用 `Material(type: MaterialType.transparency)` 承住水波纹；卡片是深色底，文字颜色也必须显式给（默认正文色是给白底页面的黑字）。

### 三、护栏与验证

新增 `test/word_safe_test.dart`（9 条：切分规则含全角、缩字比例、下限、2.0 判据、`WordSafeText` 行为、卡片真用了它）+ `screens_test` 里 1 条「设置页每个 `Text` 的祖先里必须有 `Chamfer`」。全量 **234 条通过**，`dart analyze lib test` 无 issue。

对照页 `outputs/songquery-wordwrap-settings-preview.html`，生成器 `tool/pack_fix_preview.py`，断词分布探针 `tool/probe_word_runs.py`。

**已知残留**（未改，等拍板）：中日文词本身仍会在任意两字之间折行（详情页 2.0 的「チュウマ / イ」）；行首禁则没做（「…オンザみ / んマンション」的「ん」落在行首）；19 字符的 `Sugarfull:Overbloom` 整段要 646dp，缩到下限仍需断，这是刻意保住的字号底线。


## 列表卡片长作者名降字号（2026-11-09 22:28）

卡片规矩是「不截断、自然增高」（11-02 定），所以长文本必然把卡片撑高。先加了 `test/card_extremes_test.dart`（4 条）量出自然高度，再按用户选定的**方案2「降一档字号」**处理 —— **一个字都没删**。

作者名长度阈值 55 来自数据集分布（1112 首歌）：p50=16、p90=38、**p95=55**、p99=81、max=131。只有 `length > 55` 那 5% 降档：

| 作者名长度 | 字号 / 行高 |
|---|---|
| ≤ 55（95%） | 13px / 1.5（原样） |
| > 55（5%） | 11.5px / 1.35 |

实测卡片自然高度（dp）：

| 场景 | 常规卡 | 131 字符作者 | 52 字符曲名 |
|---|---|---|---|
| 320 × 1.0 | 227.0（不变） | 361.0 → **308.0**（−15%） | 263.0（不变） |
| 320 × 1.6 | 361.0（不变） | 735.0 → **611.0**（−17%） | 477.0（不变） |
| 390 × 1.0 | 243.7（不变） | 320.0 → **275.0**（−14%） | 243.7（不变） |
| 390 × 1.6 | 317.0（不变） | 556.0 → **486.0**（−13%） | 408.0（不变） |

最坏一档 320@1.6 从 735dp（占屏 87%）降到 **611dp（72%）**；另外 8 档一分未动。护栏断言「极端卡不得 ≥ 屏高 95%，常规卡 < 420dp」，既钉住当前值也不许以后更差。

对照页 `outputs/songquery-card-artist-preview.html`（12 档改前/改后并排 + 高度表）；截图目录 `build/card-shots-{before,after}/`，生成器 `tool/pack_card_preview.py`，测试用 `--dart-define=SHOT_DIR=...` 切换输出目录。

**这里踩过一个坑**：上一轮用 `ListView` 包卡片量高度，`testWidgets` 会**静默挂死**（日志停在用例名之后，既不报错也不超时，等过 7 分半和 4 分半）。根因是卡片内层 `IntrinsicHeight` 在 ListView 的无界高度 + `scrollCacheExtent` 下互相索取高度。改用 `Column` 提供无界高度，布局语义等价，1 秒内跑完。另外卡片曲绘的图片请求会留下 pending Timer，用例末尾必须 `pumpWidget(SizedBox())` + `pump(10s)` 推掉。

全量 `flutter test` 至此 **216 条通过**（212 + 卡片 4），`flutter analyze` No issues。

**已知残留**：拉丁词会被字中断开（`HOLIDAYS` → `HOLIDA / YS`，降字号后变成 `HOLIDAY / S`）。Flutter 默认换行对 CJK 混排按字符断，要修得引入 line-break 逻辑，超出本轮。

## 2.0 字号覆盖（2026-11-09 22:38，系统字号上限）

原来所有测试只跑 1.0 / 1.6 两档，2.0 是系统字号上限却没人测。把 `detail_extremes_test` 与 `card_extremes_test` 都扩到 2.0（+5 条），详情页 2.0 全部安全，卡片查出两个问题：

- **`LEVEL` 被硬断成 `LEVE / L`**（320@2.0）。标签宽度原为 `scale > 1.2 ? 76 : …` 固定 76dp，12px 在 2.0 下变 24px，放不下。改为 `max(76, 46 × scale)`，2.0 时为 92dp；下方 `available` 的扣减同步用同一变量。
- **320@2.0 + 131 字符作者 = 871dp，超过屏高 844**。窄屏、系统最大字号、全 CV 名单三者叠加，一张卡比一屏还高。**不修** —— 这是「不截断」的必然结果，继续缩字号会让作者名比正文还小，与「用户调大字号是为了看清」相悖。护栏按档设上限（1.0/1.6 用 95% 屏高，2.0 用 105%），紧贴实测值以便捕捉回归。

**试过但回退的一处**：把 `Character : ` 标签从 `Flexible` 改成自然宽度，可以避免 2.0 下冒号掉行，但 320×1.6 与 320×2.0 会溢出 0.6px（`app_smoke_test` 抓到 3 条红），已恢复 `Flexible`。

**后来换法修好了**：`scale >= 1.8` 时把该行改成分行排（标签一行、角色名一行），1.0/1.6 仍走原 `Row`，不再溢出，冒号也不会独占一行。

## 全页面 2.0 排查（2026-11-09 22:50，当前实现）

把 `official_visual_test` 的矩阵也扩到 2.0（3 宽 × 3 字号 = 9 条，覆盖 home / card / card_real / detail / search / menu / settings / about）。溢出断言全绿，但目视查出三处 2.0 专属排版错误：

| 页面 | 改前 | 改后 |
|---|---|---|
| 搜索 | 标题「搜索与筛选」折成「搜索与筛 / 选」，末字孤儿 | `AppPage` 标题套 `FittedBox(scaleDown)` 单行缩放 |
| 搜索 | 输入框提示被截成「曲名／读音／别…」 | `hintMaxLines: 2`，整句可见 |
| 首页卡片 | 「Character : 星咲 あかり」压成「Character 星咲 あか / : / り」，冒号独占一行 | `scale >= 1.8` 时标签与值分行 |

**未修**：设置页说明文字整段压在黄绿斜带上（2.0 下内容变高正好穿过条纹）。属背景与内容的层叠关系，改法要么挪斜带位置（`.64H` 是设计定值）、要么给内容加底板，是视觉决策，留给用户定。

对照页 `outputs/songquery-2x-textscale-preview.html`（每页 320@1.0 与 320@2.0 并排），生成器 `tool/pack_2x_preview.py`。

全量 `flutter test` **221 条通过**，`flutter analyze` No issues。

**本轮交付（2026-11-09 22:53 +09:00）**：exit 0，约 1 分钟。成品 **28,557,644 字节**（连续第五版同尺寸）；SHA-256 `34f7565063bc5fd07c1d901bccea6222d70680809101ee3aed5bb1ac639a37d0`；`tool/check_apk.py` **20/20 通过**。三份一致：

- `D:\WorkBuddy space\outputs\songquery-2x-layout-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-2x-layout-0.0.1-20261109-225344.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

`libapp.so` 5,964,680 / 377 条目不变，CRC `670151700` → `3424156747`。

### 上一版交付（2026-11-09 22:43 +09:00，LEVEL 标签修复）

成品 28,557,644 字节；SHA-256 `4d6d5e796c565249bc36b04c5b73fe0bd76723f26bd2f90e9d16066f2819325b`；`tool/check_apk.py` **20/20 通过**。三份一致：

- `D:\WorkBuddy space\outputs\songquery-level-label-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-level-label-0.0.1-20261109-224302.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

`libapp.so` 5,964,680 / 377 条目不变，CRC `3442677293` → `670151700`。

### 更早交付（2026-11-09 22:30 +09:00，卡片长作者名降字号）

exit 0，53 秒。成品 28,557,644 字节；SHA-256 `687aee8027fbee9d93c577fd9ff73f88b0c61be553c8ac2012160c39cd76e0af`；`check_apk` **20/20 通过**。三份一致：

- `D:\WorkBuddy space\outputs\songquery-card-artist-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-card-artist-0.0.1-20261109-223032.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

大小与上两版完全相同（28,557,644 / `libapp.so` 5,964,680 / 377 条目），只有 CRC 变了：`131643873` → `3442677293`。

## 详情页文案完整显示（2026-11-09 22:15）

用户拍板：**「1 需要完整显示；2 先出 HTML 我确认后再出 APK」**。所以本轮只做一件事 —— 把详情页里所有省略号截断删掉，曲名、读音、作者名、信息条的值一律完整排版，与列表卡片「不截断、自然增高」的规矩（11-02 定）统一。改完 `grep -rn TextOverflow.ellipsis lib/src` **一处都没有**。

| 位置 | 改前 | 改后 |
|---|---|---|
| 作者名 | `maxLines: 2` + 省略号，131 字符那首只露前两行 | 不限行数完整显示；空串仍不占位 |
| 曲名 | 需缩到 70% 以下时走 `maxLines: 2` + 省略号 | 一律完整换行，尾字不再被吞 |
| 信息条的值 | `maxLines: 2` + 省略号，`bright MEMORY Act.1`（19 字符）在窄屏会变 `bright MEMORY Ac…` | 不限制，固定宽度内自然增高 |

- 代价（用户已确认接受）：131 字符作者在 320@1.6 会占掉大半屏，谱面区被挤出首屏，需滚动。这是「完整」的必然结果，不是回归。
- 常规曲目曲名与作者都短，本来就不触发截断，改前改后视觉一致 —— 差异只在极端样本上可见。
- 验收：`flutter test` **212 条通过**，`flutter analyze` No issues，截图按当前源码重生成。改前截图备份在 `build/shots-before-author-full/`（33 张）。
- 对照页 `outputs/songquery-detail-fulltext-preview.html`：**改前 / 改后左右并排**，12 档全部有 before 图；生成器 `tool/pack_detail_preview.py`（新增 `BEFORE` 目录与 `bsrc/bwc/bhc` 字段）。

### 本轮交付（2026-11-09 22:15 +09:00）

成品 **28,557,644 字节**；SHA-256 `8fee18c5d9412ba39aad9aab272360e7d4e493dac8a536cc6cc4e0dd03d0acc6`。`tool/check_apk.py` **20/20 通过**。三份复制后哈希一致：

- `D:\WorkBuddy space\outputs\songquery-detail-fulltext-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-detail-fulltext-0.0.1-20261109-221523.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

**大小与上一版完全相同（28,557,644、`libapp.so` 5,964,680），只有 CRC 变了**：`370766845` → `131643873`。删掉 `maxLines` / `overflow` 参数没有跨过 64KB 对齐档。再次印证：判新旧只看 `libapp.so` CRC 或全包 SHA-256。

## 详情页硬缺陷修复（2026-11-09 21:28，已被上一节取代截断部分）

用户明确限定「只修硬缺陷、谱面区保持四张全展开、视觉风格不动」。改动全在 `lib/src/app.dart`：

- **信息条列宽**：原 `max(72, 宽/4−24)` 固定四等分，320 宽可用仅 260，四 × 72 = 288 必定换行成 3+1；1.6 字号下每项塞不下「チュウマイ」，被硬断成「チュウ／マイ」。改为 `LayoutBuilder` 按 `(4×72 + 3×gap) × textScale` 判断走 4 列还是 2 列，窄屏与大字号走 2×2。`_Meta` 从自己推算宽度改为接收外层算好的 `width`。
- **头部布局**：字号 > 1.3 时改为上下堆叠（封面 88 在上、曲名在下占满整行）；横排与堆叠共用抽出的 `_titleBlock`。
- **曲名单行自适应**：堆叠时套 `FittedBox(scaleDown)`。390@1.6 实测曲名差几像素，会把结尾「♥」挤到单独一行，比断词更难看。
- **谱面副信息**：`谱师 / 物量 / 铃铛` 缺失项整段省略，不再固定输出「谱师 — · 物量 —」；全缺才显示「暂无谱面信息」。
- **副信息不再拼成一行**：用「 · 」拼字符串时，谱师名一长就断在分隔符上，换行后行首挂一个「·」（EXPERT 那条实测如此）。改成 `Wrap` 拆成独立项，换行只发生在项之间。
- **等级列固定宽**：`3 / 6 / 8+ / 11.8` 宽度相差 28dp，会带着左侧文字区的可用宽度一起变，于是四张卡片换行位置各不相同（320 宽下 EXPERT 的「物量 685」被 8+ 挤断）。改为 `40 × textScale` 固定列宽并右对齐。

### 极端数据压力测试（同日）

新增 `test/detail_extremes_test.dart`，用数据集里**真实存在的极值**渲染详情页，在 320/390/400 × 1.0/1.6 下断言不抛异常（overflow 会以异常形式冒出），截图落在 `build/extreme-screenshots/`：

| 样本 | 实测内容 | 发现的问题 |
|---|---|---|
| 最长作者 | 131 字符（`曲：…／歌：…[CV：…]、…[CV：…]`） | 不限行数时 320@1.6 排 **9 行**，首屏只剩曲名和作者，谱面区被整屏挤走 |
| 最长曲名 | 52 字符 | `FittedBox` 把它硬缩到约 13dp，**比正文还小**，标题层级倒挂 |
| 最长谱师 | 64 字符 | 换行正常，无溢出（`Wrap` 拆项后不吊标点） |
| 字段全缺 | 只有 id 与曲名、无谱面 | **DETAILS 渲染成一条没有内容的黑色薄片**；作者为空还留一个空行 |

对应修复：

- **作者名限 2 行 + 省略号**，空串不渲染。完整 CV 名单去 wiki 看。（**已于 22:15 版废除**：改为完整显示，见上节）
- **曲名缩放下限 0.7**：用 `TextPainter` 预量宽度，缩一点点能放下就单行缩放（避免「♥」掉行），要缩到 70% 以下则改排两行 —— 硬缩会让标题比正文小，此时宁可两行截断。
- **DETAILS 整节跟内容走**：所有字段为 null 时连标题一起不渲染。
- **最高难度在无谱面时不再染难度色**（原来空曲目会显示一个绿色「—」）。

### 返工记录

第一版把封面改成 `min(88 × scale, 屏宽 × 0.32)`，本意是修「曲名比封面高导致留白失衡」，结果 320@1.6 曲名被挤成「GO! G / O! ラブリ / ズム」，**比改动前更碎**。

结论：修留白失衡不能靠放大封面 —— 那等于抢文字宽度。正确手段是改排布（堆叠），堆叠后封面回到 88，不再随字号变化。

### 本轮刻意未改

- **底角菜单按钮会压在卡片文字上**：它是全页复用的浮层，滚动中途必然经过内容；`BottomControls.clearance` 已保证滚到底可完全避让。彻底消除须改成底部固定栏，会改变所有页面布局高度，超出本轮范围。
- `OfficialTitle`（大英文水印标题）仍是全项目 0 引用的死代码。

### 本轮交付（2026-11-09 21:28 +09:00）

`flutter test` **212 条通过**（原 206 + 极端数据 6），`flutter analyze` No issues，`tool/check_apk.py` **20/20 通过**。常规截图 `build/official-screenshots/detail_*`、极端样本 `build/extreme-screenshots/*` 均按当前源码重生成；对照页 `outputs/songquery-detail-fixes-preview.html`（12 张，含「常规曲目」「极端数据」两组，生成器 `tool/pack_detail_preview.py`）。

成品 **28,557,644 字节**；SHA-256 `5a80b5e645233d508c296f064575867c9cf5523a27b10e615380d96edb75a170`。三份复制后哈希一致：

- `D:\WorkBuddy space\outputs\songquery-detail-extremes-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-detail-extremes-0.0.1-20261109-212833.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

**尺寸终于变了**：此前连续四版都是 28,492,108、`libapp.so` 都是 5,899,144；本版 `libapp.so` 涨到 5,964,680（+65,536，正好一个 64KB 对齐档），全包随之到 28,557,644 —— 新增的 `TextPainter` 预量代码跨过了对齐边界。条目数仍是 377（没多资源）。所以「大小相同不能证明没重编」成立，但「大小变了」也只是跨档，判新旧依然只认 `libapp.so` 的 CRC（`4229788106` → `370766845`）或全包 SHA-256。

## 背景斜带端点修复（2026-11-09）

用户 11-04 指出搜索页右侧三条黄绿斜带被切成平头，端点露在屏内。本轮只动背景，卡片/菜单/搜索/详情等其余界面一行未改。

- 源码仅改 `lib/src/theme.dart` 的 `MusicBackdrop` 两处：`width` 由 `1.5W` 增为 `3W`，`left` 由 `0.23W` 改为 `0.23W - 1.5W`。旋转中心仍是 `x=0.23W`，角度 −20°、条厚 10/30/10、纵向 `.64H + [0,20,60]`、颜色、网格全部保持原值。
- 新增 `test/background_regression_test.dart`：320×844 / 390×667 / 390×844 / 400×869 / 844×390 各 1.0 与 1.6 字号共 10 组真实搜索路由，取 `RenderTransform` 子节点旋转后四角，断言所有条端都在视口外、中心与角度条厚不变、滚动前后背景四角相等、`IgnorePointer` 保留。修前版本不强求端点出屏，也不人为制造端点。
- 验证：该文件 10/10 通过；全量 `flutter test` **206 条通过**；`flutter analyze` No issues。日志 `build/_bgtest.log`、`build/_alltest.log`、`build/_analyze.log`（UTF-16LE，直接 `tail`/`grep` 是乱码）。
- 真实字体渲染的修前/修后截图 20 张：`outputs/background-flutter-search-{320x844,390x667,390x844,400x869,844x390}-{1.0,1.6}-{before,after}.png`，几何报告 `outputs/background-flutter-checks.json`。静态对照页 `outputs/songquery-background-fixed-preview.html`（可切视口/字号/修前后，全内联 base64，不是可操作搜索）。曲绘走网络、截图为占位，不作本轮验收依据。
- 仍未做真机验收；横屏 `document` 宽 1085 是卡片 `width 800` 撑出来的既有行为，与本轮背景无关。

### 本轮交付（2026-11-09 19:31 +09:00）

`flutter build apk --release --target-platform android-arm64 --no-pub`，Gradle `assembleRelease` 实跑 94.5s，exit 0。`tool/check_apk.py` **20/20 项通过**（仅 arm64-v8a、包名、关键文案、字体与数据资源齐）。

成品 **28,492,108 字节**；SHA-256 `3dd515e6e39a3b01fb6608e3893ac7ec5edd731cc2250ae035ecea273e3c0ffc`；md5 `2595817d21dfaf3b6e8114b5e8131e5a`。三份复制后哈希一致，桌面为排他新建：

- `D:\WorkBuddy space\outputs\songquery-bgfix-0.0.1.apk`
- `C:\Users\Tsumugi\Desktop\songquery-bgfix-0.0.1-20261109-193113.apk`
- 构建产物 `build/app/outputs/flutter-apk/app-release.apk`

**包体大小与 11-03 的 corner-spacing 包完全相同，但内容已变**：改动只替换 AOT 常量，`libapp.so` 字节数仍是 5,899,144。判据不是大小，而是 `libapp.so` 的 CRC（`2139597237` → `2765244357`）、全包 SHA-256 变化，以及构建日志里真实的 `assembleRelease` 耗时。另注：`libapp.so` 逐字节 diff 有 204 万字节、1.1 万段差异，那是 Dart AOT 快照重排与重定位偏移平移，**不能当作「只改一处」的证据**。

旧包全部保留未覆盖：`songquery-corner-spacing-0.0.1.apk`、`songquery-fullpage-0.0.1.apk`、`songquery-music-card-0.0.1.apk`，以及 `outputs/songquery-flutter-arm64.apk`（仍为 11-03 corner-spacing 基线）。

## 卡片与底角按钮版本（2026-11-03，卡片规格仍有效）

该卡片规格的确认基准为 `outputs/songquery-corner-spacing-preview.html`，已实际移植到Flutter，不是仅重打整页旧包。下方整页及11-02章节均为历史记录。

- 卡片左右15dp、gap12dp、右上透明切角18dp；默认最小高度390宽231.6875dp、320宽215dp。取消固定itemExtent，长文字/大字号自然增高，标题作者及Character不ellipsis截断。
- 图390宽104dp、320宽88dp，含黑框、原图contain；顶部/左侧内padding12dp，图文top齐；标题18/窄17、作者13浅灰、分类12；五等宽难度槽，缺失谱面不编造；Character白尾栏保留。
- 菜单全页左下、搜索仅首页右下；43dp视觉圆、48dp触区、2dp绿边、半透明黑底白图标。左右触区21.5+对应viewPadding，视觉侧距24。用视口Stack定位，不叠加SafeArea；视觉底距max(27.5,max(viewPadding.bottom,24))，触区底距max(25,max(viewPadding.bottom,24)-2.5)。底部24是保守fallback，不是设备实测。键盘viewInsets>0时隐藏控件，收起恢复。
- 页面与列表保留底部滚动补偿，末项可滚到控件上方；搜索/菜单/详情/设置/关于/删除确认/许可全文仍完整页，零转场。原生更新/缓存/字体持久化未替换为HTML预览设置，领域排序搜索未改。
- 测试的58dp圆角仅模拟已知设备参考，不是生产代码硬编码机型角半径。未安装本轮APK或操作设备。

### 当次构建交付（2026-11-03 14:36 +09:00，历史记录）

完整 `tool/verify.py --build --coverage` 为 VERIFY OK：analyze无问题，196/196测试通过（新增24安全区布局场景及400宽截图组合），覆盖1658/1727行=96.0%，APK内容20/20项。日志 `build/corner-spacing-verify-passed.log`；真实字体几何 `build/corner-layout-geometry.json`。

真实字体默认首卡：320为290×215、390为360×231.6875、400为370×231.6875，图88/104、内padding12、top80；大字首卡320高355、390/400高269，与HTML约342.67/263.11不同，属于Flutter字形/行高/换行及尾栏尺寸差异，保留文字自然增高，没有裁字凑高度。字体未加载的widget测试高度也可能不同，最终几何报告已加载真实随包字体。

截图 `build/official-screenshots/` 更新home/menu/search/detail/settings/about共320/390/400×1.0/1.6，已Read首页390/320默认、320大字、400默认及菜单代表图。曲绘在测试为占位，仍非真机或逐像素验收；本轮未安装设备。Java native-access与NDK插件版本提示未阻止构建。

AAPT确认dev.tsumugi.songquery、0.0.1+1；仅arm64-v8a，apksigner签名有效CN=Android Debug。成品28,492,108字节；SHA256 `69a0a256ae0f08a9bf9bdcf8980670a7ece1f384398912c6c8befe6c70cd68c6`。
- `D:\WorkBuddy space\outputs\songquery-corner-spacing-0.0.1.apk`
- `D:\WorkBuddy space\outputs\songquery-flutter-arm64.apk`
- `C:\Users\Tsumugi\Desktop\songquery-corner-spacing-0.0.1-20261103-143620-244676.apk`

三份复制后SHA256一致，桌面排他新建，未覆盖移动删除旧文件。机器校验结果 `outputs/corner-spacing-apk-delivery.json`。

## 整页版本（2026-11-03，历史记录）

已根据用户确认的 `D:\WorkBuddy space\outputs\songquery-fullpage-preview.html` 实际修改 Flutter；下方 11-02 视觉与迁移统计为历史记录，不代表当前页面或本轮测试数量。

- 首页仅固定圆菜单与右下搜索，无 logo/MUSIC/常驻搜索；浅网格和彩带位于滚动内容之外。
- 搜索、菜单、详情、设置、关于、删除确认及许可全文均为完整路由页，零过场动画；菜单只有实际设置/关于。没有功能 dialog 或 bottom sheet 调用。
- 搜索保留五种排序和分类/角色/版本/读音行筛选，增加审批稿中的难度/等级；方向独立，同项不反转，切换新排序升序且仅清 rows；默认没有方向，关键词搜索仍相关度优先、先取最多60首再筛选。
- 返回保留查询/排序/筛选与列表 ScrollController 位置；列表采用 Flutter 惰性构建，无需照搬 HTML 的“再显示30首”。
- 详情保留真实谱面、收录信息、外链及内部信息，使用紧凑粉色英文小节和透明切角深色容器；设置保留三套实际字体方案与持久化，关于保留原生更新、体积、删除及许可能力，不使用 HTML 预览设置替代。
- `AppRoute` 禁用页面转场，菜单固定在安全区内右上 15dp，48dp 触控区。真实 Flutter 截图覆盖 320/390 × 1.0/1.6 的首页、菜单、搜索、详情、设置、关于，目录 `build/official-screenshots/`。

边界：尚无真机验收，也不声称与 HTML/官网逐像素一致。搜索分类/角色/版本仍为原生多选 chips，而非官网单选下拉；触控尺寸按至少48dp保留。Flutter 曲绘继续网络缓存与镜像回退，截图测试为占位图，未把 HTML 的6张示例图当作全库离线曲绘。背景保持静态彩带，不复制官网随机动效。APK 仅 arm64、自用、debug 签名；应用 ID `dev.tsumugi.songquery`、版本 `0.0.1+1` 不变，旧字体未删。

### 本轮交付验证（2026-11-03 01:36 +09:00）

`tool/verify.py --build --coverage` 最终 `VERIFY OK`：analyze 无问题，170/170 测试通过，行覆盖率 1638/1706（96.0%），APK 内容 20/20 项通过。日志 `build/fullpage-verify-passed.log`。新增/迁移回归包含完整页导航、圆菜单矩形不变、搜索条件保存、独立方向与同项不反转、详情返回滚动位置、原生更新/删除/字体持久化。真实字体截图已复查，修复搜索下拉中文缺字和禁用方向按钮低对比度；仍非真机验收。Java native-access / 插件 NDK 版本提示未阻止构建。

AAPT 核实包名 `dev.tsumugi.songquery`、versionName `0.0.1`、versionCode `1`；仅 arm64-v8a。apksigner 验证签名有效，证书 `CN=Android Debug`。APK 28,557,644 字节；SHA-256 `c42637a3c4fdd1082c9e64722ca65a70fd909575eec9d3fb3026503a999dbf6a`。

以下三份复制后 SHA-256 完全相同；桌面采用排他新建，未覆盖/移动/删除原有文件：
- `D:\WorkBuddy space\outputs\songquery-fullpage-0.0.1.apk`
- `D:\WorkBuddy space\outputs\songquery-flutter-arm64.apk`
- `C:\Users\Tsumugi\Desktop\songquery-fullpage-0.0.1-20261103-013606-576096.apk`

当前六页截图命名 `{home|menu|search|detail|settings|about}_{320|390}_{1.0|1.6}.png`；目录中还保留历史截图，旧 `dialog`/`filters` 图不代表当前实现。

## 官网视觉整改（2026-11-02，历史记录）

官网依据保存在 `tool/official-style.css` 与 `tool/official-music.html`（来源 https://ongeki.sega.jp/）。
实际标题选择器是 `.c-sectionTitle`，不是 `c-title`：手机端 MUSIC 为 65px/小屏 50px、绿色 #32c63a、透明度 .2；中文叠放 20px/小屏 16px。本应用保留中文“曲目查询”，采用 65px 与 20px，支持系统字号。
`body` 使用 Josefin Sans bold → M+ 1p bold 字体链与 bg_mesh 平铺；默认方案已改为该字体链，中文缺字用 MiSans 补全。旧 SEGA 字体及 classic/system 方案保留。
`.p-music__choice` 为 #222 双切角；`.p-music__choice:before` 与 `.p-music__listChildInner:before` 使用 bg_circuit / .1；搜索边框来自 `.p-music__inputWrapper` 的 #949494 / 1.5px，粉色选中态来自 `.p-music__numberBtn.is-select` / `.p-music__sortBtn`。
卡片右上 10px 切角来自 `.p-music__listChildInner`；曲名/艺人使用手机端 13px/11px，曲绘黑框 3px，难度分隔线 #888 来自 `.p-music__listLevel`。详情/设置/关于共用纹理、标题和主题化按钮/对话框/筛选控件，不改变查询逻辑、签名、应用 ID 或 0.0.1+1。
官网下载的 M PLUS 1p Bold/Medium 原文件与原始 OFL 许可随包保留，详见 `assets/fonts/THIRD-PARTY-NOTICES.txt`；纹理版权归 © SEGA，仅自用，非官方应用。
`test/official_visual_test.dart` 使用真实随包字体渲染首屏、详情、设置与关于，覆盖 390/320 宽度及 1.0/1.6 字号，输出 `build/official-screenshots/`。测试环境曲绘为占位图。尚未做官网浏览器截图逐像素比对，不能宣称全视觉一致。

本次最终验证（按用户第二张官网目标图精修卡片后）：`tool/verify.py --build --coverage` 返回 VERIFY OK；analyze 无问题，173/173 测试通过，行覆盖率 1606/1619（99.2%），APK 内容 18/18 项通过。成品 28,557,732 字节，仅 arm64-v8a；SHA-256 `7dd6ed31da2c832cd057e3979f87aaabcf7e8c06b17bbb2a061d649ac3599641`。日志：`build/music-card-verify-passed.log`。插件要求 NDK 28.2 的既有警告仍在，沿用本机可用的 27.1，构建成功。

本轮以实时 https://ongeki.sega.jp/music/ 为唯一布局依据，刷新HTML/CSS并读取music.bundle.js动态模板（tool/official-music.js）。已通过本机Chrome + Node原生WebSocket获取真正390/320移动视口截图与computed样式，脚本为tool/capture_official_music.mjs，参考图build/official-reference/music-390.png、music-320.png，对应music-*-computed.json。
官网实测：choice宽度为视口减20、padding 15px 10px、三行控件间距12px，标题390时65px/320时50px；曲绘105px/90px；列表左右15px、间距30px，角色footer白底黑色3px边框。应用已落地全宽独立标题、深色切角三行分类/关键词/排序面板、输入框右侧白底搜索标识、105/90曲绘、独立难度栏与白底角色尾栏、30px列表间隔。保留现有一键排序与筛选抽屉而非替换成官网单选下拉；输入仍防抖实时搜索，无新增动画。为手机触控及字号保留48dp控件，不机械复制官网30px高度。新增首页结构断言，业务测试滚动到目标卡片后再检查；空态可滚动避免面板变高后的溢出。应用24张截图已更新并复查。
按用户目标图追加卡片精修：ARTIST: 白色粗体最多3行；内容使用Official/Josefin + MPLUS1p/MiSans回退；LEVEL独立68dp左栏及竖分隔；灰色#787878/2px圆环加右上90度彩弧、白色业务数值；Character : 白底黑框，按footer伪元素复刻#e9e9e9、150/10px、skew(-30deg)斜纹。电路纹理opacity仍为CSS .1，但改fit:none原尺寸平铺，修复默认缩放导致纹理过密。背景斜带依据c-bgAnime的rotate(-20deg)、c1/c3黄绿、h1/h3=10/30px静态实现；位置固定适配应用视口，不复制官网随机滚动动画。原始脚本依据tool/official-common.js。
新增card/card_real及对应crop局部截图，390/320 × 1.0/1.6；card是Sugarful:Overbloom目标曲，card_real是匹配到本地缓存文件的另一首曲名（缓存插件测试环境注入挂起已撤，截图仍是占位图，名字不代表曲绘已成功加载）。未新增网络下载。完整截图目录当前40张。优先核对card_crop_390_1.0.png和card_crop_320_1.6.png。
交付同字节两份APK到工作区outputs/songquery-flutter-arm64.apk和songquery-music-card-0.0.1.apk，未触碰桌面。未复制官网导航/品牌横幅、角色插画及版权尾注；长艺人名超过3行仍截断，卡片高度适配无障碍字号，非整页像素复制。

跨页一致性修正：AppTokens 统一控件48dp最小高度、12px粗体和7px切角；补齐所有按钮/正文/对话框的中文字体回退（修复粉色更新按钮中文不可见）；筛选 chip 取消额外描边，统一首页字重/字号/选中配色。AppInfoRow 统一详情与关于的88dp标签列、8dp列间距、11/12px标签/数值及1.7行高；设置/关于/筛选的小节标题共用17px粉色样式。详情返回控件补48dp触控区域与安全区，不改导航或数据逻辑。保留现有页面标题结构与深色AppBar，不做整页重设计。

截图现为24张：原四页面16张，加筛选及对话框8张；命名 `{home|detail|settings|about|filters|dialog}_{390|320}_{1.0|1.6}.png`。新增公共控件字体回退/形状/高度的回归断言；许可弹窗测试等待滚动稳定后点击。

## 当前已迁移

- 曲库模型、在线 otoge-db 数据转换与本地 JSON 持久化；更新使用暂存文件、备份回滚
- 上游字段改名按比例兜底（缺 `lev_bas` / 空 `title` / 无正定数超阈值即拒绝更新，保留本地曲库），
  并有一份真实上游样本与随包快照逐字段对拍，防止转换器抄错却「条数不变、校验全过」
- 落盘曲库带**格式版本戳**：旧版本算错的本地数据会被判为过期并自动重下（ETag 没变也照下）
- 启动时用 ETag 做一次协商：上游没变就只花一个 HEAD 请求，不再重下 1.6MB 数据
- 关键词搜索（曲名、读音、别名/ID、编辑距离回退及排序键读音折叠）
- 排序区三栏 = 游戏里三组互不冲突的设置（见 `楽曲ソート排序方式汇总.xlsx` 的茶/绿/蓝三色）：
  **分类**（タブ設定，怎么分段：分类／全曲／角色／版本／谱面等级／曲名／属性）、
  **排序**（タブ内ソート，段内顺序：推荐顺序／…／对手等级／曲名顺／追加日期／章节顺）、
  **对手榜**（ライバルスコア，显示哪项分数）。每栏各选一个，默认取表格 ★ 那一项。
  快照里没有数据的 7 项（属性、三种分数排序、三种对手榜分数）照表格列出但置灰不可选；
  三种分数属于玩家成绩，非曲目元数据。领域层对应 `TabGroup` / `TabSort` / `RivalScore`
  与 `SongEngine.listGrouped`；分组会真的在列表里画组头（角色 111 段、分类 6 段、五十音 15 段）。
  「重置排序」把三栏复位。旧的主排序与五十音·版本行条已在 0.1.0 下线，
  `SortKey` 仅保留给引擎与测试
- 同分兜底：曲名按 ICU 的分层模型比较（主权重 → 浊点级别 → 小写级别）；符号/拉丁/汉字三张权重表
  由 `tool/gen_collation_table.mjs` 从 ICU 反推生成（含长音符继承元音、全角折叠、汉字读音序）
- 分类、角色、版本、难度、等级筛选；搜索结果同样应用筛选（搜索态不分段，相关度优先）
- 曲目卡、难度定数、详情与外链
- 字体方案设置（三档角色：曲目内容 / 数字 / 界面文案，随方案切换或退回系统字体）、关于页和曲库更新进度条/清理
- 切角形状、背景网格、字体与曲绘多镜像回退；曲绘缓存键固定在图片文件名上，三条线路共用一份磁盘缓存
- 曲绘预取：限并发 2、失败重试一次、按文件名去重，滚动时提前取往下 4 张（曲绘 TTFB 实测 0.6–1.8 秒，等卡片被构建才取就晚了）
- 行高随系统字号放大（上限 1.5×）：固定 130dp 行高在 1.6 倍字号的小屏上会让卡片内容垂直溢出 19px，已改

## 当前数据源

在线上游按 jsDelivr Fastly → Cloudflare → Gcore → GitHub Raw 顺序下载，安装之前解析并验证。曲库既含打包的 2026-10-15 初始快照，也在首启尝试更新。曲绘按 Gcore → testingcf → otoge-db.net 回退。

### 上游体检

数据会不会哪天悄悄变了（字段改名、曲目被清、曲绘改名、某条线路坏掉），本机没法靠单测发现
——单测用的是固定夹具。跑这个：

```powershell
python tool/check_upstream.py            # 默认抽 6 张曲绘
python tool/check_upstream.py --samples 12
```

要联网，所以**没有放进 `verify.py`**（那条命令要保持离线可跑）。它查三件事：

1. 四条数据线路给出的是不是**同一份**文件（字节数 + sha256）
2. 抽样的曲绘在三家线路上是不是**同一张完好的图**（PNG 魔数 + 字节数一致）
3. 上游曲目数有没有比随包快照更少

2026-11-02 实测结论：

- 上游 `music-ex.json` **1,656,352 字节，1112 行**，与随包快照 **1112 首逐 id 一致**（用真实
  `Dataset.fromUpstream` 解析后：1112 首 / 4208 张谱面，`titleKana`、角色、版本字段无空缺，
  没有字段漂移）
- 三条 jsDelivr 线路的 sha256 完全相同（`8e5c72c1…`）
- 曲绘跨三家字节数**逐字节一致**，PNG 魔数正确，TTFB 约 **0.6 秒**
- **`raw.githubusercontent.com` 从这台机器下 1.6MB 会超时**（HEAD 能通、秒回，GET 40 秒读不完）。
  它是最后一条兜底线路，实际基本不可用 —— 这也解释了为什么「ETag 要连线路一起存」那个
  bug 在真机上很难触发：会走到那条线路的人本来就不多。

判据一律用**内容**而不是 HTTP 200：截断的响应、占位图、被 CDN 换掉的错误页都可能返回 200。
这条有来由 —— 我一开始用 `curl -o /dev/null` 量曲绘大小，读到的是一堆 270B / 2738B 的
「疑似截断包」，看着像 CDN 在给残包；换成写真实文件再量，三条线路全是完整的 80KB 级 PNG。
**是这个沙箱里 `-o /dev/null` 会让 curl 提前中止写入，`size_download` 只报前一段。**
量吞吐/大小一律落盘再 stat，别信 /dev/null。

## 上游转换：精度、漂移与预言机

`Dataset.fromUpstream` 把 otoge-db 的二十多个扁平字段翻译成 `charts[]`。这一层错一处，
**条数不变、格式校验也能过**，用户要到在线更新成功之后才会看出不对。

### `lev_*_i` 是小数，不是「定数×10」

上游这一列是**小数形态的字符串**：实测 5560 个取值全部是 `str`，且每个非空值都带小数点
（`'11.8'`、`'13.0'`），没有整数形态。

Dart 移植版一开始写成了 `_int(raw['lev_mas_i'])` + `~/ 10` / `% 10` / `/ 10`，等于把它当成
「定数×10 的整数」：`_int('11.8')` 先截成 `11`，`~/10` 得 `1`、`/10` 得 `1.1`。于是
**只要在线更新成功一次**，全库 MASTER 定数就从 `11.8` 变成 `1.1` —— 每首歌顶栏显示 `1.x`。

它特别难发现，有三个叠加原因：

- 随包快照是 RN 管线生成的、值是对的 `11.8`，所以**只装包不更新永远看不到**；
- 默认排序（按 `topLevel` 降序）因为「全体除以 10」是单调的，**顺序居然还是对的**；
- 长度校验、往返校验全部通过，不报任何错。

修法是照抄 RN 原版 `src/sources/ongeki.ts` 的语义：`Number(t)` 浮点解析，`floor` 拆整数、
`round((value-level)*10)` 拆小数。顺带对齐了同一处源码里三组「0 等于没有」的语义
（`int(x) || undefined`）：`bpm`、`enemyLevel`、`noteCount`/`bells` 在空串或 0 时为 `null`
而不是 `0`，否则与快照逐字段比对必然对不上。

### 转换器的独立预言机

`test/fixtures/upstream_sample.json` 存了 40 行**真实上游数据**。测试拿它转换后与
`assets/songs-2026.10.15.json` 逐字段比对 —— 快照是 RN 管线的产物，不是这份 Dart 代码
生的，所以它是真正独立的期望值。上面那个精度 bug 就是被它精确指到某一首歌的 MASTER 上：

```
Expected: <11.8>
Actual: <1.18>
520100「ＧＯ！ＧＯ！ラブリズム♥」 chart[3] levelValue
```

fixture 由 `tool/gen_upstream_fixture.py` 生成，只收录「当前上游转出来仍与快照逐字段
一致」的行（排除快照日期之后上游改过定数造成的假红），再按边界形态取样：整数难度、
LUNATIC 独立条目、缺 bpm、缺物量、带 `+` 标签、高难 14.x。**换快照后要重跑一次**，
让期望值跟上：

```powershell
python tool/gen_upstream_fixture.py            # 自动下载上游
python tool/gen_upstream_fixture.py --dry-run  # 只看统计不落盘
```

### 字段漂移按比例兜底

上游改名不会抛异常，只会让数据安静地少一块，所以按**占比**兜底。阈值来自上面那份
1112 行的实测基线，都留了 10 倍以上余量：

| 现象 | 真实基线 | 阈值 | 说明 |
|---|---|---|---|
| 缺 `lev_bas` | 0 / 1112 | 5% | 难度字段改名 |
| `id` / `title` 为空 | 0 / 1112 | 2% | 会被 `fromJson` 丢掉，留着只会让往返校验失败 |
| 无正 `levelValue` 的曲目 | 19 / 1112（1.71%） | 20% | `lev_*_i` 漂移的指纹，**条数完全不变** |

全中的情况（整列改名）直接抛「上游 N 行缺少 id 或 title，数据格式可能已变」，不会装一份
空标题曲库。样本不足 20 行时跳过比例判断 —— 2 行里坏 1 行就是 50%，比例没有意义，
而不足 500 条的负载在仓储层已经被拒。

### 格式错误不再重试线路

字段改名时四条线路下的是**同一份坏文件**，重试只会白下 4.8MB，最后报「所有曲库线路均
失败」，把真实原因彻底埋掉。现在第一条就抛
`FormatException: 上游数据不可用，已保留本地曲库：…`。

反过来，**截断 / 乱码的响应仍然会换线路重试** —— 那是传输问题，换一条可能就好了。
所以 `_decodePayload` 把「字节解不出 JSON」转成 `HttpException` 走重试分支，
只让 `Dataset.fromUpstream` 自己抛的 `FormatException` 触发快速失败。这两条都有测试
（`does not retry other mirrors when the payload is malformed` /
`retries the next mirror when the body is truncated json`）。

### 坏数据怎么自愈：落盘格式版本戳

上面那个定数 bug 修好之后还有个尾巴：**已经被旧版本装到本地的坏数据修不回来**。
ETag 协商在「上游没变」时直接返回本地数据（这正是它省流量省的地方），而那份坏文件
条数够、编码对、结构合法 —— `_decodeStored` 挑不出任何毛病，于是它会被一直用到
下次上游真的变了为止。

解决办法是给落盘文件盖版本戳：`Dataset.toJson` 一律写入 `meta.schema = datasetSchemaVersion`，
`_decodeStored` 要求它等于当前值，否则当作不可用。于是整条链自己接上了：

1. `loadLocal()` 返回 null → 启动时直接用随包快照，用户先看到对的数；
2. 后台 `fetchAndInstall()` 走到「ETag 没变但本地读不出来」的分支 → 重新下载；
3. 重装后的文件带上新戳，不会反复重下。

版本号**只在「旧文件读进来会得到错的数」时才 +1**，不是每次改格式都加 ——
现在的 `2` 对应「修正 `lev_*_i` 解析之前算出的 1.1」。

已知小瑕疵：坏文件要等重下成功才会被覆盖，这期间「关于」页的**本地体积**仍按那份旧文件
算（`localBytes()` 只 stat 文件），数字上看起来像还装着一份。没有改成「读的时候顺手删掉」
—— `loadLocal()` 保持只读这个不变量，比省一次下载更值钱。

### 关于页原先显示的是占位符

顺手修掉的另一处：`本地体积` 那行原来写死成字符串 `'在线缓存'`，而 `localBytes()`
只有测试在调 —— 占位符冒充数据。现在真读本地文件并格式化成 `1.6 MB / 50 KB / 0 B`。

同时修了**关于页不跟着根状态刷新**：它是路由栈里的一页，拿到的是入栈那一刻的快照，
所以「删完曲库，统计还是 1112 首、删除按钮还能再按一次」。改法是在 `HomeScreen`
里放一个 `ValueNotifier` 当刷新信号 —— 根状态一换值，`didUpdateWidget` 就 +1，
挂在路由里的 `ValueListenableBuilder` 跟着重建。

一个细节：`didUpdateWidget` 发生在**构建阶段**，那里直接置值会让监听者「在 build 期间
被标脏」，撞上框架断言，所以推到帧后（`addPostFrameCallback`）再通知。

### 空态文案：三种「空」不是一回事

结果为空时原来一律写「曲库是空的」。这句只有**库里真的没有歌**时才对 —— 选了分类 +
角色、交集为空的时候，界面是在说图书馆没书。现在分开：

| 情况 | 文案 |
|---|---|
| 有搜索词 | 没有匹配的曲目 |
| 无搜索词、筛没了 | 没有符合筛选条件的曲目 |
| 曲库确实是空的 | 曲库是空的 |

顶部计数也跟着改：筛选生效时从固定的「全部曲目」变成「筛选后 N 条」。

测这条有个陷阱：卡片上也会渲染分类名（`song.genre`），直接 `find.text('A')` 会同时命中
卡片文案和面板里的 chip —— 得用 `find.descendant(of: find.byType(FilterSheet), ...)`
限定范围，否则报「found 2 widgets」。

## 滚动卡顿：定位与实测（2026-11-24）

用户报「滑动或滚动时严重卡顿」。**先量化再动手**，结论分「本机可测」与「只能在真机测」两层。

### 本机怎么量

`test/bench_scroll.dart` 是基准探针（不是断言，跑起来只打印）。**故意不叫
`_test.dart`** —— 不进常规回归（否则每次全量多跑 2 秒并往输出里塞噪声），
要显式指定路径：

```powershell
flutter test test/bench_scroll.dart
# BENCH mounted_cards_initial=6          首屏构建了几张卡
# BENCH scroll30_total_us=... median_frame_us=... p90_frame_us=... max_frame_us=...
# BENCH single_card_rebuild median_us=... 单卡 rebuild+layout 成本
```

**它能测什么、不能测什么，务必分清：**

- **能测** UI 线程的 build/layout 成本 —— 与真机同向，比例可信。
- **不能测** 光栅化（BackdropFilter / shader / 平铺纹理）与图片解码 ——
  `tester.pump()` 只到 layer 树，不真正光栅化；曲绘在测试环境走占位块。
  所以「去掉玻璃底栏」「去掉 IntrinsicHeight」在本机测出来数字**没有变化**，
  这不代表真机没收益，只代表本机测不到。**别用本机数字否掉 raster 侧的假设。**

### 实测（3 次稳定值）

| 指标 | 值 | 解读 |
|---|---|---|
| 滚动中位帧 | 11–12ms | 匀速滚动还行，**不是**匀速掉帧 |
| 滚动 p90 / max | 21–27ms / 52–57ms | **长尾才是「严重卡顿」的体感来源**：新卡首次进视口那一下 |
| 单卡 rebuild | 3.5–4.3ms | 一张卡本身的 UI 成本，乘上每帧进出的张数就是长尾 |
| 首屏已建卡片 | 6 张 | cacheExtent 3 屏卡的代价（默认 250px 时是 4 张） |

### 已修（确定性浪费，不影响观感）

1. **拇指玻璃每帧新建 shader**：`_ThumbGlass._refraction` 原先把每帧都在变的
   弹簧值 `press` 也当缓存 key → 拖动/按压期间每帧 `FragmentShader` 新建 +
   dispose 旧的。改为只按 `(size, dpr)` 重建、press 变化只刷 uniform。
2. **预取判重从 O(n) 拷贝改 O(1)**：`PrefetchQueue.seen` 是 `Set.unmodifiable`
   （每次拷贝整个集合），滚动上千首后每次 build 都白复制一遍 → 新增 `contains()`。
3. **滚动回调做无谓计算**：`ScrollUpdateNotification` 每帧触发，而一屏内首索引
   通常不变 → 加 `_prefetchFirst` 短路（数据/排序变更处复位，避免换了结果集不取图）。
4. **全屏背景每帧重画**：`MusicBackdrop` 是静态的（平铺纹理 + 反相 colorFilter，
   满屏几十次带滤镜 draw），却与列表同层 → 包 `RepaintBoundary`。
5. **起手滚动必触发的整卡重绘**：每次开始滚都会先触发一次 `PressScale` 按压
   （`onPointerDown` 立即 down，位移超 8dp 才取消），而它的 Transform 在
   ListView 自带边界**里面** → 整卡（纹理+文字+4 个难度环）重绘 240ms。
   在 `PressScale` 内层再包一层 `RepaintBoundary`，缩放只更新 layer transform。

### 待选（需要真机 profile 或产品取舍，未擅自改）

| 项 | 位置 | 为什么没直接改 |
|---|---|---|
| 曲绘按原图解码 | `_Jacket` 无 `memCacheWidth` | 真机 raster 侧大头（每张新图解码+上传纹理）。但 `cacheKey` 是文件名、与预取/磁盘缓存共用，加尺寸约束要么改缓存粒度、要么只让内存缓存变异，需真机验证不破预取 |
| 底栏 4 个 BackdropFilter | `_Glass` 两个实例各 2 层 | Impeller 下每帧 4 个 backdrop pass + 2 个 shader pass，且底下内容每帧在动。这是「只要滚就卡、与内容无关」的唯一恒定开销，但降它是产品取舍（减层/降采样/滚动时降级） |
| `_groups` 每次 build 全量排序 | `HomeScreen._groups` | 实测 5–7ms/次，任何 setState 都付。可缓存但失效点有四个（dataset/排序/筛选/搜索词），属于易引 bug 的改动 |
| 搜索跑两遍 | `_groups` + `reasons` | 同一 query 全量搜两次（含编辑距离模糊）。可合并成一次，属重构 |
| 卡片每帧读 MediaQuery | `SongCardView.build` | 弹键盘 → viewInsets 变 → 全列表 10~14 张卡重建 |

### 真机怎么验（本机做不了的那一半）

```powershell
flutter run --profile                      # Impeller 默认开
# DevTools → Performance：看 UI 还是 Raster 先超 16ms
#   UI 超   → 卡片构建 / 排序 / 重建（本机可测那一类）
#   Raster 超 → BackdropFilter / shader / 平铺纹理 / 图片解码

adb shell dumpsys gfxinfo dev.tsumugi.songquery framestats   # 逐帧耗时分布
```

判据：把底栏临时换成纯色块再滚 —— **卡顿减半 → 主因是 BackdropFilter**；
滚已加载过的区域顺滑、只有新图出来时顿 → 主因是图片解码。



```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### 交付前体检

一条命令跑完 analyze → test → APK 内容校验（双击 `verify.bat` 或命令行都行）：

```powershell
python tool/verify.py            # 分析 + 测试 + 校验已有 APK
python tool/verify.py --build    # 顺带重打 arm64 release APK
python tool/verify.py --coverage # 测试带覆盖率，并打印分文件汇总
```

逻辑写在 `tool/verify.py` 里而不是 `.bat`：cmd 的 label / errorlevel 链路没法自测，
Python 每一步都能在本机真跑通再交付；`verify.bat` 只是个找 python 的启动器。

`tool/check_apk.py` 单独也能跑（默认查 release 产物），它验的是「包里是不是对的东西」：

- 只含 `arm64-v8a`（多 ABI 会让包体从 25MB 涨到 100MB 级）
- `AndroidManifest.xml` 里的包名是 `dev.tsumugi.songquery`
- `libapp.so` 里 **按 UTF-16LE** 搜关键文案：新文案必须在、旧文案必须不在
  （Dart AOT 把字符串存成 UTF-16LE，用 UTF-8 grep 中文永远 0 命中）
- 曲库快照与三款字体都确实打进去了

两个与构建环境有关的注意点：

- `android/gradle.properties` 里设了 `kotlin.incremental=false`。release 构建会稳定复现
  `Could not close incremental caches`（清 `build/` 目录、停 Gradle daemon 都没用），关掉增量换稳定构建。
- 插件（`shared_preferences_android` 等）打包的预编译 `.so` 是全 ABI 的，`--target-platform`
  管不到，所以 `app/build.gradle.kts` 用 `packaging.jniLibs.excludes` 排掉 `armeabi-v7a` / `x86_64`。
  同一处的 `defaultConfig.ndk.abiFilters` 在 AGP 9 上不生效，别再改回去。

## 日文排序

RN 版用 `localeCompare(…, 'ja')`，那是完整的 ICU 实现；Dart 没有 locale 排序 API，
这里按 ICU 的分层模型自己实现：**先比整串主权重，相等再比浊点层，最后比小写层**
（三层压成一个序列按字符比是错的，那样「A」和「ab」的先后会反过来）。

权重不手排：用 Node/ICU 对每个字符单独跑 `localeCompare(…, 'ja')` 求序，固化成常量。
手写权重表实测比纯码位更差（79.4% vs 81.3%）。

拿曲库里 1044 个真实标题和 ICU 真值对照（`test/collation_export_test.dart` 导出
Dart 侧的排序结果，`node tool/compare_collation.mjs` 逐对比较）：

| 指标 | 纯码位（改前） | 现在 |
|---|---|---|
| 相邻对·全部 | 73.06% (762/1043) | **100% (1043/1043)** |
| 相邻对·含汉字标题 | 67.98% (329/484) | **100% (484/484)** |
| 全对·Kendall（544446 对） | 94.22% | **100%** |

实现里几个不显然的点，都是实测出来的：

- **平假名与片假名主权重相同**（`あ` = `ア`）。按码位排会把整块平假名标题挤到所有片假名标题前面。
- **拉丁主权重不分大小写**，`Ä` 是「A + 第二层变音」。所以先折小写、折基字母，变音落到第二层。
- **汉字不能用码位排**。ICU 的汉字主权重来自 CLDR unihan（大致按读音），与码位大量互逆：
  ICU 里 `亜 < 一`、`日 > 月`、`火 < 月`。`lib/src/collation_han.dart` 收了随包曲库出现过的
  480 个汉字，按 ICU 序固化成表；这一步单独把含汉字标题从 68.0% 拉到 99.0%。
- **`ー` 继承前一个假名的元音**（JIS X 4061：`カー` ≈ `カア`、`コー` ≈ `コオ`）。
  给长音符一个固定符号权重会让 `シークレット` 排到 `シアワセ` 前面。
- **全角 Ａ/！/： 与半角完全等价**（`localeCompare('Ｇ','G','ja') === 0`），Ⅲ/⑨ 折成 III/9。
  不折它们会掉进码位兜底、排到所有汉字之后。
- **分层顺序**：符号 < 数字 < 拉丁 < 假名 < 汉字 < 希腊/西里尔（`∀ < 亜 < α < Я`）。

已知边界：`表外字符`（曲库换快照后新增的汉字/符号）退回码位比较，会排到本表所有字之后。
曲库更新后重跑 `node tool/gen_collation_table.mjs` —— 它会从数据集重新推导两张表并直接改写
`lib/src/domain.dart` 与 `lib/src/collation_han.dart`；`domain_test.dart` 里有一条护栏会在
出现表外汉字时变红提醒。

## 字体与许可

三款随包字体共 10.6 MB（启动时按方案渐进加载，只等当前方案那一款）：

| 字体 | 体积 | 角色 | 覆盖 |
|---|---|---|---|
| SEGA MaruGothic DB | 2.4 MB | 曲名 / 读音 / 角色名 | 1105/1108 (99.7%) |
| Josefin Sans Bold | 0.1 MB | 数字、定数、拉丁装饰 | 14/14 (100%) |
| MiSans Medium | 8.1 MB | 中文界面文案 | 232/232 (100%) |

覆盖率由 `tool/check_font_coverage.py` 按**实际渲染角色**统计（不是「字体有多少字」）：
字符集来自曲库内容与 Dart 字符串字面量，注释和权重表不算。曲库换快照后跑一次——
SEGA 出现新的缺字时脚本以非零码退出，当护栏用。

已知缺口，都是「掉到系统字体」而非豆腐块（Flutter 有逐字形 fallback）：

- SEGA 缺 `ά` `ゔ` `髙`。`ά` 只在「μάγια」这一首的曲名与读音里；`ゔ` `髙` 只出现在艺人字段
  （「DIVA… いゔどっと」「髙橋 ミナミ」）。
- MiSans 缺 `・`（U+30FB）。界面里原本的「曲名・读音・艺人・ID」与详情页分隔符已改用
  `／`（U+FF0F，三款字体都覆盖），避免这处掉到系统字体。

**许可文本已随包**（`assets/fonts/LICENSE-JosefinSans.txt` + `THIRD-PARTY-NOTICES.txt`，
打进 APK，应用内「关于 → 查看许可全文」可直接阅读）：

- **Josefin Sans**：SIL OFL 1.1，允许嵌入分发，全文随包（版权行与保留名
  `"Josefin Sans"` 一并保留）。
- **MiSans**：小米免费商用许可，**协议要求软件内注明使用了 MiSans 字体** ——
  「关于」页有专门一行「本软件使用了 MiSans 字体。」（有测试盯着，删了算违约），
  第三方声明文件里也有同样注明。不得单独分发字体文件本身、不得改编。
- **SEGA MaruGothic DB**：从游戏数据描出（字体 name 表内嵌声明
  `Traced from SDEZ170 SDF atlas (game data)`），**无任何再分发许可**，
  仅限自用安装包；对外分发前必须移除或替换该字体。

## 迁移状态

这是功能迁移开发版，不声称和 RN 旧版逐像素/逐行为等价。`flutter analyze` 输出 `No issues found!`（0 error / 0 warning / 0 info，连 `curly_braces_in_flow_control_structures` 也一并清掉了）。

自动化测试 **294 条全绿**（下列逐文件条数为 2026-11 初的统计，之后又加了排序、角色分组、三栏常显等用例，未逐条回填）：

| 文件 | 条数 | 覆盖内容 |
|---|---|---|
| `domain_test.dart` | 51 | 日文 ICU 排序、搜索归一化、模糊匹配（含 `fuzzy.clear()` 的「更近的清掉更远的」）、BPM/版本排序、缺失值垫底、落盘格式版本戳、`SongFilters.matches` 四条分支（含角色排序下 `rows` 取角色读音的岔路）与「浏览/搜索同一份判断」对拍、`collectFolded` 的前缀与包含两条岔路、同 ID / 同版本 / 双缺失三种 tie-break |
| `app_smoke_test.dart` | 30 | 真实曲库渲染、五种排序、搜索（含 × 一键清空）、筛选抽屉、详情页（含返回键、外链行真的发起打开）、稀疏曲目、空态三种（搜不到 / 筛没了 / 库真空）、更新失败原因显示、宽度 × 字号矩阵（一条循环展开 5 组合）、卡片跳转、排序方向反转、换排序清 `rows` 保 `releaseTags`、版本/五十音胶囊条的选中与收起、NEW 角标、滚动预取链路、顶部入口、关于页跟随根状态刷新、筛选判断单份实现的源码级护栏 |
| `repository_test.dart` | 29 | 线路回退、断流、ETag 协商（含「存的是哪条线路」）、安装提升与回滚、格式错误不重试 vs 截断重试、旧版本曲库自动重下 |
| `upstream_drift_test.dart` | 15 | 与随包快照逐字段对拍的预言机、字段改名护栏、单字段形态容错（小数定数、`0` 等于没有、`+` 标签、日期形态） |
| `screens_test.dart` | 16 | 筛选抽屉交互（切换/取消/全部清除保留 `rows`）、设置页方案切换与预览联动、关于页统计与删除确认、本地体积三档量级、`FontRoles.copyWith` / `lerp`、MiSans 使用注明的合规断言、许可全文弹窗（注入加载器） |
| `app_root_test.dart` | 10 | 应用根状态：内置库启动、优先本地、静默更新成功/失败、手动更新失败提示、清空曲库、字体方案持久化与非法值兜底、`loadBundled` 打包护栏 |
| `widget_test.dart` | 8 | 首屏外壳 |
| `prefetch_test.dart` | 8 | 并发上限、去重、重试、`dispose` 后不再接单、非零 `retryDelay` 的真实等待（`fakeAsync` 推时钟） |
| `collation_export_test.dart` | 1 | 导出 Dart 侧排序结果供与 ICU 对拍 |

行覆盖率 **99.0%**（1512/1527 行，`python tool/verify.py --coverage` 一条命令出全部数字）：`domain.dart` 100%、`theme.dart` 100%、`prefetch.dart` 100%、`collation_han.dart` 100%、`app.dart` 98.7%、`screens.dart` 98.2%、`repository.dart` 97.2%。剩下的 15 行分三类：`app.dart` 的 8 行是曲绘失败后的镜像重试排程与 clipper 的 `shouldReclip`（只有真实网络失败或真机重挂载才走）；`screens.dart` 的 4 行是 `loadFontLicenseText()` 的 `rootBundle` 真实读取（测试注入假加载器，与 app.dart 那 8 行同类，属真机路径）；`repository.dart` 的 3 行是 promotion 失败后「恢复备份」的兜底分支（见下面「有个坑」）。

arm64 release APK 已在 `build/app/outputs/flutter-apk/app-release.apk` 构建成功（26,179,830 字节，md5 `d0103ff5538d1088db41b6cbfbeb85db`，包内仅含 `arm64-v8a`，应用 ID `dev.tsumugi.songquery`，versionName `0.0.1` / versionCode `1`）。NDK 用本机已安装的 27.1.12297006；部分插件声明依赖 28.2，构建只会警告。release 仍使用 debug 签名，仅适合安装测试。尚未完成真机检查。原 RN 版保持为回退方案。

### 更新流程有个坑：清理半成品失败会让「检查更新」直接崩

`_recoverInterruptedInstall()`（安装前清掉上次中断留下的 `.bak`/`.tmp`）原本**不带任何
异常保护**，而它的 catch 分支假设 `target.delete()` 和 `backup.rename()` 都能成功。真实
故障下两个都可能抛（比如 `songs.json` 被换成非空目录：`File.delete()` 删不掉非空目录、
`rename()` 到已存在目录也抛），异常就从 catch 里**逃逸出 `fetchAndInstall` 的开头** ——
用户点「检查更新」直接崩，而 `loadLocal()` 因为有自己的 try/catch 反而看不出来。

修法：把整个 `_recoverInterruptedInstall()` 包进 try/catch，清理失败不外抛 —— 它只是
清理动作，留着现场让安装流程自己去覆盖或报错，都比把更新变成未捕获异常强。

顺带查清两件容易误判的事（写测试前先看，能省很多力气）：

- **`File.existsSync()` 对目录返回 `false`**。所以 `.bak` 若被换成目录，仓储里所有
  `backup.exists()` 检查都看不见它，`backup.delete()` 根本不执行。想靠「`.bak` 造目录」
  触发 promotion 的 catch 是**做不到的**，现场会直接被跳过。
- **catch 里「恢复备份」那两行（`movedOldFile && backup.exists()` → rename）在注入数据下
  造不出来**。能让它们执行的失败点只有二次校验之后，而那时 `.bak` 已被删掉；二次校验的
  schema 戳又被 `toJson()` 覆盖成正确值。那两行是纯防御代码，只有 rename 后文件损坏这类
  真实文件系统故障才能触发 —— 所以 `repository.dart` 的覆盖率停在 97.2%、剩 3 行是故意的。

### ETag 协商有个坑：各家口径不一样

同一份文件，实测（2026-11-02）：

| 线路 | ETag |
|---|---|
| `fastly/cdn/gcore.jsdelivr.net` | `W/"194620-47007985bd6c1c6f"`（弱 ETag，包里含大小与时间戳） |
| `raw.githubusercontent.com` | `"7359e9a1…"`（强哈希） |

所以**存 ETag 时必须连「产出它的线路」一起存**，下次 HEAD 打同一条。只存 ETag 一行、
固定去 HEAD 第一条线路的话，一旦某次是回退线路装成功的，存下来的值永远对不上，
之后每次冷启都白下一次 1.6MB —— 正好把这个优化抵消掉，而且日志上完全看不出来
（不报错，只是慢）。侧车文件因此是两行：`线路` + `ETag`；老的单行格式按「通常是第一条」兜底。

### 上游连通性（2026-11-02 实测）

四条线路当天都通，jsDelivr 三条回包一致（1,656,352 字节）。`HEAD` 时延不到 1 秒，
所以「每次冷启一个 HEAD」这个前提成立。`raw.githubusercontent` 的 ETag 与 jsDelivr 不同源，
这也是上面那个坑的由来。

### 整机级冒烟抓到过什么

这一层不是形式主义，它在无人碰真机的情况下抓到四个真 bug，都已修：

- **列表行高写死**。`itemExtent` 与卡片 `height` 原本是常量 130 / 120，320dp 屏 + 1.6 倍字号下 `RenderFlex overflowed by 19 pixels`。现在由 `rowExtentOf(context)` 按 `MediaQuery.textScalerOf` 算行高（**放大封顶 1.5 倍**，2.0 倍字号以下的挤压靠卡片内部自适应吸收），曲绘预取的行号换算共用同一个 extent，不会错行。
- **详情页「屏幕宽 / 4 - 24」为负**。宽度不足 96dp 时算出负的 `SizedBox` 宽度，直接撞 `BoxConstraints has a negative minimum width`。改成 `LayoutBuilder` 取真实可用宽度并保底 72dp。
- **手动更新失败的提示永远弹不出来**。`_SongQueryAppState` 里写的是 `ScaffoldMessenger.of(context)`，而这个 State 的 context 在 **`MaterialApp` 之上**，`ScaffoldMessenger` 是 MaterialApp 自己插在内部的 —— 往上找必然为空，于是「更新失败，保留现有曲库」这条提示从来没显示过，还顺手往 zone 里扔一个 `No ScaffoldMessenger widget found` 异常（异步吞掉，线上看不出来）。改用 `scaffoldMessengerKey: _messenger` + `_messenger.currentState?.showSnackBar(...)`。**这类 bug 只有把根状态挂起来点一遍才抓得到** —— 之前所有冒烟都直接挂 `HomeScreen`，绕过了整层。

- **关于页从不跟着根状态刷新**。它是 `Navigator.push` 出去的一页，`dataset` / `status` /
  `busy` 都是入栈那一刻的副本，之后根状态怎么变都不会通知它 —— 表现是「在关于页删掉
  曲库，曲目数还是 1112、删除按钮还能再按一次，要退回首页才正常」。改成
  `ValueNotifier` + `didUpdateWidget`（帧后通知）驱动 `ValueListenableBuilder` 重建。
  这条同样属于「只有把整棵树挂起来点一遍才看得见」。

### 筛选判断只留一份

浏览列表（`SongEngine.list`）和搜索结果（`HomeScreen._passesSearchFilters`）都要按
分类 / 角色 / 版本 / 五十音行四条维度过滤。原先两边各抄一份一模一样的四段判断，
改一边忘一边就会出现「浏览时筛掉了、搜出来又有」这种鬼现象 —— 而 UI 冒烟只覆盖到
分类这一条分支，另外三条回归时不会红。现在判断收敛成 `SongFilters.matches(song, sort)`
一个纯函数（`rows` 那组按 `sort` 取角色读音或曲名读音，是唯一的岔路），两处都委托它；
另有一条源码级护栏（`app_smoke_test.dart` 里的「搜索路径的筛选判断只留一份实现」）
盯着 `app.dart` 不要再长出第二份判断。

### 根状态为什么要留两个注入点

`SongQueryApp` 现在能注入 `repository` 和 `bundledLoader`。后者不是为了好看：

`rootBundle`（内置曲库）在 flutter_test 里需要**真实事件循环**才推进。同一个测试文件里连跑多个 widget 用例时，第二个之后它就不再有进展，界面永远停在「正在读取曲库…」—— 单独跑那条用例却完全正常。表现出来像业务 bug（数据没加载），实际是测试环境。把加载器做成接缝之后，widget 用例全走假数据、完全确定；真实资产通道另用一条**普通 `test`**（`loadBundled really reads the packaged snapshot`）单独验，顺带当「资产有没有漏打进包」的护栏。

写这类测试时还有个坑：不要用 `MediaQuery(data: MediaQueryData(textScaler: ...))` 包在 `MaterialApp` 外面覆盖字号 —— 新建的 `MediaQueryData` 里 `size` 是 `Size.zero`，`MediaQuery.sizeOf` 会全树返回 0，反而制造出上面那种负宽度崩溃。正确做法是走 `MaterialApp.builder`，用 `MediaQuery.of(context).copyWith(textScaler: ...)` 只覆盖字号、保留真实尺寸。

另一个更容易骗人的坑是**假通过**：筛选抽屉里的「版本」组落在 ListView 视口之外时，`Text` 组件其实还在树里，`find.text('R1')` 找得到、`tap()` 也「成功」返回 —— 只是点在别的东西上（flutter_test 只打印一条 warning 就算过）。于是「点两下把选项取消掉、计数回到 0」这种断言恒真。规避办法：`ensureVisible` / `scrollUntilVisible` 先把它滚进视口，并且**必须断言中间态**（点一次时是 1，再点一次才是 0）。

判断「更新到底被调用了几次」也别数 `SnackBar`：提示进出场动画期间 `find.byType(SnackBar)` 会短暂命中两个。用假仓储里的调用计数断言（`installs == 2`：启动一次 + 手动一次）才可靠。

## 上架前清单

离线能做的都做完了（analyze / 168 条测试 / APK 内容校验含许可文本）。四项外部条件里两项已拍板（字体仅自用、签名先用 debug），上游体检已建每日 09:00 自动任务（`tool/check_upstream.py`，otoge-db.net 超时判为慢镜像噪音）：

| # | 事项 | 现状 | 需要什么 |
|---|---|---|---|
| 1 | **真机验收** | 未做，`adb devices` 一直为空 | 一台 arm64 设备。装好后走一遍：首屏、滚动曲绘、搜索、筛选、详情页、更新、删除本地曲库 |
| 2 | **正式签名** | **已决策：先用 debug 签名继续**，真机验收不受影响 | 分发/上架前再换 release 签名（换签名后旧包不能覆盖安装，要提醒卸载重装） |
| 3 | **字体许可** | **已决策：仅自用、不分发**。许可材料已随包（OFL 全文、第三方声明、关于页 MiSans 注明） | 无。若将来对外分发，须先移除或替换 SEGA traced 字体 |
| 4 | **应用 ID / 版本号** | **已定稿**：ID `dev.tsumugi.songquery`、版本号 `0.0.1+1`（versionName 0.0.1 / versionCode 1） | 无。上架后 ID 不能再改 |

换曲库快照（`assets/songs-YYYY.MM.DD.json`）时按这个顺序跑，别漏：

```text
python tool/gen_upstream_fixture.py       # 重生成转换器对拍样本
python tool/check_font_coverage.py        # 新曲名/谱师是否超出字体覆盖
python tool/check_upstream.py             # 上游数据体检（要联网）
python tool/verify.py --build --coverage  # 全绿才算完
```

`test/domain_test.dart` 里那条「汉字权重表覆盖快照里所有 CJK 字」是护栏：换快照引入新汉字
它会红，提醒重跑 `tool/gen_collation_table.mjs`。
