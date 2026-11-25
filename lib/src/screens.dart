import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'bottom_bar.dart';
import 'domain.dart';
import 'theme.dart';
import 'version.dart';

/// 字体许可全文：第三方声明 + Josefin Sans 的 OFL 1.1 全文拼接。
/// 真机从随包 assets 读；测试注入假实现（rootBundle 在 flutter_test 里
/// 有顺序依赖，同一文件连跑多个用例第二个起不再推进，别直接在测试里读）。
Future<String> loadFontLicenseText() async {
  final notices = await rootBundle.loadString(
    'assets/fonts/THIRD-PARTY-NOTICES.txt',
  );
  final ofl = await rootBundle.loadString(
    'assets/fonts/LICENSE-JosefinSans.txt',
  );
  final mplus = await rootBundle.loadString('assets/fonts/LICENSE-MPLUS1p.txt');
  return '$notices\n\n$ofl\n\n$mplus';
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.initial,
    required this.genres,
    required this.characters,
    required this.releases,
  });
  final SongFilters initial;
  final List<String> genres, characters, releases;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Set<String> genres, characters, releases;
  @override
  void initState() {
    super.initState();
    genres = {...widget.initial.genres};
    characters = {...widget.initial.characters};
    releases = {...widget.initial.releaseTags};
  }

  void _toggle(Set<String> set, String value) =>
      setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  Widget _group(String title, List<String> values, Set<String> selected) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(title),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                FilterChip(
                  // 显式给标签定色：只靠 chipTheme 时浅色主题会拿到白色文字，
                  // 白底白字等于整组筛选项「消失」（见 chamfer/light 回归用例）。
                  label: Text(
                    value,
                    style: TextStyle(
                        color: selected.contains(value)
                            ? Colors.white
                            : context.cardInk),
                  ),
                  selected: selected.contains(value),
                  onSelected: (_) => _toggle(selected, value),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(context).height * .82,
          decoration: BoxDecoration(
            color: context.canvas,
            border: const Border(
                top: BorderSide(color: AppPalette.magenta, width: 4)),
            image: DecorationImage(
                image: const AssetImage('assets/tex/bg_mesh.webp'),
                opacity: context.meshOpacity,
                repeat: ImageRepeat.repeat),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '筛选曲目',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        genres.clear();
                        characters.clear();
                        releases.clear();
                      }),
                      child: const Text('全部清除'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    _group('分类', widget.genres, genres),
                    _group('角色', widget.characters, characters),
                    _group('版本', widget.releases, releases),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      SongFilters(
                        genres: genres,
                        characters: characters,
                        releaseTags: releases,
                        rows: widget.initial.rows,
                      ),
                    ),
                    child: Text(
                      '应用筛选（${genres.length + characters.length + releases.length}）',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.scheme,
    required this.onChange,
    this.themeMode = ThemeMode.system,
    this.onThemeMode,
    this.menuAction,
  });
  final VoidCallback? menuAction;
  final String scheme;
  final Future<void> Function(String) onChange;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode)? onThemeMode;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String scheme;
  late ThemeMode themeMode;
  @override
  void initState() {
    super.initState();
    scheme = widget.scheme;
    themeMode = widget.themeMode;
  }

  Future<void> _change(String value) async {
    setState(() => scheme = value);
    await widget.onChange(value);
  }

  @override
  Widget build(BuildContext context) {
    // 预览跟随 Radio 的当前选择，而不是主题里已生效的方案 —— 点下选项到
    // 应用层保存并重建主题之间有一帧延迟，用主题会让预览闪一下旧字体。
    final fonts = FontRoles.forScheme(scheme);
    const choices = <String, String>{
      'official': '官方混排',
      'classic': '旧版游戏圆体 · 系统界面字',
      'system': '全部系统字体',
    };
    const descriptions = <String, String>{
      'official': '遵循官网：拉丁与数字用 Josefin Sans，日文用 M PLUS 1p，中文缺字用 MiSans 补全。',
      'classic': '曲目内容与数字保留原字体，界面文案使用系统字体。',
      'system': '不使用随包字体，统一交给系统渲染。',
    };
    return AppPage(
      title: '设置',
      topSpacing: 40,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Chamfer(
            child: Material(
              type: MaterialType.transparency,
              child: RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => themeMode = value);
                  await widget.onThemeMode?.call(value);
                },
                child: Column(children: [
                  for (final mode in [
                    ThemeMode.light,
                    ThemeMode.dark,
                    ThemeMode.system
                  ])
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(
                          switch (mode) {
                            ThemeMode.light => '浅色',
                            ThemeMode.dark => '深色',
                            ThemeMode.system => '跟随系统',
                          },
                          style: TextStyle(color: context.cardInk)),
                    ),
                  Text('手动选择立即生效并自动保存，不依赖系统配色。',
                      style: TextStyle(color: context.cardMuted)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 统一卡片表面：白色 / 半透明深灰基底，电路在卡片内。
          Chamfer(
            fill: AppPalette.card,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle('字体方案'),
                Text(
                  '切换后立即生效并自动保存。',
                  style: TextStyle(color: context.cardMuted),
                ),
                const SizedBox(height: 12),
                // Flutter 3.32 起 Radio 的 groupValue/onChanged 被废弃，改由祖先
                // RadioGroup 统一持有。写成祖先而不是逐项传参，切换时也不会有一帧
                // 出现「两个都被选中」的中间态。
                // ListTile 的水波纹要画在最近的 Material 上；卡片本身是带底色的
                // DecoratedBox，夹在中间时 Flutter 会断言「背景或水波纹可能看不见」。
                // 透明 Material 承住水波纹，卡片的底色照旧由 Chamfer 提供。
                Material(
                  type: MaterialType.transparency,
                  child: RadioGroup<String>(
                    groupValue: scheme,
                    onChanged: (value) {
                      if (value != null) _change(value);
                    },
                    child: Column(
                      children: [
                        for (final entry in choices.entries)
                          RadioListTile<String>(
                            value: entry.key,
                            // 卡片是深色底，文字颜色必须显式给 —— 默认的正文色
                            // 是给白底页面的黑字，放进卡片就看不见了。
                            title: Text(
                              entry.value,
                              style: TextStyle(
                                color: context.cardInk,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              descriptions[entry.key]!,
                              style: TextStyle(color: context.cardMuted),
                            ),
                            activeColor: AppPalette.magenta,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '字体文件随安装包分发；切换字体方案不会改变曲库数据。',
                  style: TextStyle(
                    color: context.cardFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Chamfer(
            fill: AppPalette.card,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle('预览'),
                Text(
                  'We Are Us!',
                  style: TextStyle(
                    fontFamily: fonts.content,
                    fontSize: 20,
                    color: context.cardInk,
                  ),
                ),
                Text(
                  'うぃーあーあす',
                  style: TextStyle(
                    fontFamily: fonts.content,
                    color: context.cardMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '定数',
                      style: TextStyle(
                        fontFamily: fonts.label,
                        color: context.cardMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '13.7',
                      style: TextStyle(
                        fontFamily: fonts.numeric,
                        color: context.cardInk,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      '物量',
                      style: TextStyle(
                        fontFamily: fonts.label,
                        color: context.cardMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '1024',
                      style: TextStyle(
                        fontFamily: fonts.numeric,
                        color: context.cardInk,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「工具」页签的占位页。
///
/// 底栏三格已经接好，但工具类功能（随机选曲、练习用谱面表这些）还没做。
/// **只留标题、不放说明文字**（2026-11-24 用户要求删除页内文字解释）。
class ToolsPlaceholderScreen extends StatelessWidget {
  const ToolsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => const _PlaceholderPage(
        tab: AppTab.tools,
      );
}

/// 「我的」页签的占位页。
///
/// 个人资料一块还没做，但**设置与关于必须挂在这里**：它们原来的入口是左下角
/// 那个菜单圆钮，圆钮撤掉之后如果不接过来，主题、字体方案、曲库更新与删除
/// 就全都点不到了。
class ProfilePlaceholderScreen extends StatelessWidget {
  const ProfilePlaceholderScreen({
    super.key,
    required this.onSettings,
    required this.onAbout,
  });

  final VoidCallback onSettings;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => _PlaceholderPage(
        tab: AppTab.profile,
        entries: [
          (label: '设置', icon: Icons.tune_rounded, onTap: onSettings),
          (label: '关于', icon: Icons.info_outline_rounded, onTap: onAbout),
        ],
      );
}

/// 两个占位页共用的骨架：大标题 +（可选）入口列表。
///
/// 用 ListView 而不是 Column：小屏 + 2.0 字号下内容会超过一屏，Column 直接溢出。
///
/// **没有说明文字卡片**：原先这里有一段 `body` 文案，2026-11-24 按用户要求
/// 删掉（「工具和我的内的文字解释删除」）。页面只保留标题与真实入口。
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.tab,
    this.entries = const [],
  });

  final AppTab tab;
  final List<({String label, IconData icon, VoidCallback onTap})> entries;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(
            20, 28, 20, LiquidGlassBar.clearance(context)),
        children: [
          Row(children: [
            Icon(tab.activeIcon, size: 26, color: AppPalette.magenta),
            const SizedBox(width: 10),
            Text(tab.label,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold)),
          ]),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 18),
            Chamfer(
              padding: EdgeInsets.zero,
              // ListTile 的水波纹要画在最近的 Material 上；卡片本身是带底色的
              // DecoratedBox，夹在中间会断言「水波纹可能看不见」。
              child: Material(
                type: MaterialType.transparency,
                child: Column(children: [
                  for (final entry in entries)
                    _PlaceholderEntry(
                      label: entry.label,
                      icon: entry.icon,
                      onTap: entry.onTap,
                    ),
                ]),
              ),
            ),
          ],
        ],
      );
}

class _PlaceholderEntry extends StatelessWidget {
  const _PlaceholderEntry({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(children: [
            Icon(icon, size: 20, color: context.cardInk),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: context.cardInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: context.cardFaint),
          ]),
        ),
      );
}

/// 1_656_352 → `1.6 MB`。这行只是让人有个量级概念，不需要更细的精度。

String _formatBytes(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).round()} KB';
  return '$bytes B';
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    required this.dataset,
    required this.status,
    required this.error,
    required this.busy,
    required this.onUpdate,
    required this.onClear,
    required this.loadBytes,
    required this.loadLicense,
    this.revision = 0,
    this.menuAction,
  });
  final VoidCallback? menuAction;
  final Dataset? dataset;
  final String status;
  final String? error;
  final bool busy;
  final Future<void> Function() onUpdate, onClear;

  /// 本地曲库占多少字节。走回调而不是传数值：只有真打开这页才需要读。
  final Future<int> Function() loadBytes;

  /// 许可全文（第三方声明 + OFL）。走回调注入：测试里 rootBundle 有顺序
  /// 依赖，假实现才能稳定断言弹窗内容。
  final Future<String> Function() loadLicense;

  /// 曲库变过几次。变一次就重取一次体积（删库之后不能还写着 1.6 MB）。
  final int revision;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AboutScreen old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _reload();
  }

  Future<void> _reload() async {
    final value = await widget.loadBytes();
    if (mounted) setState(() => _bytes = value);
  }

  @override
  Widget build(BuildContext context) {
    final dataset = widget.dataset;
    final songs = dataset?.songs ?? const <Song>[];
    final charts = songs.fold<int>(
      0,
      (count, song) => count + song.playableCharts.length,
    );
    final genres =
        songs.map((song) => song.genre).whereType<String>().toSet().length;
    return AppPage(
      title: '关于',
      topSpacing: 40,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppSectionTitle('数据更新'),
          _InfoBox(
            rows: [
              ('状态', widget.busy ? '下载中' : widget.status),
              ('曲目 / 谱面', '${songs.length} / $charts'),
              ('分类', '$genres'),
              ('数据快照', '${dataset?.meta['version'] ?? '—'}'),
              ('曲库来源', 'otoge-db オンゲキ'),
            ],
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                widget.error!,
                style: const TextStyle(color: AppPalette.danger),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.busy ? null : widget.onUpdate,
            icon: const Icon(Icons.sync),
            label: Text(widget.busy ? '正在下载…' : '检查更新'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.dataset == null
                ? null
                : () async {
                    final confirmed =
                        await Navigator.of(context).push<bool>(AppRoute(
                      builder: (dialogContext) => AppPage(
                          title: '删除确认',
                          menuAction: widget.menuAction,
                          child: Column(children: [
                            const SizedBox(height: 20),
                            const Text('删除本地曲库？'),
                            const Text('删除后需要联网重新下载。'),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('删除')),
                          ])),
                    ));
                    if (confirmed == true) await widget.onClear();
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除本地曲库'),
          ),
          const AppSectionTitle('下载线路'),
          const _InfoBox(
            rows: [
              ('1', 'jsDelivr · Fastly'),
              ('2', 'jsDelivr · Cloudflare'),
              ('3', 'jsDelivr · Gcore'),
              ('4', 'GitHub Raw'),
            ],
          ),
          Text(
            '更新器按线路顺序尝试；下载成功后先写入暂存文件并重新解析，再替换本地曲库。网络中断时保留已有版本。',
            style: TextStyle(color: context.inkFaint, fontSize: 12),
          ),
          const AppSectionTitle('数据集'),
          _InfoBox(
            rows: [
              ('曲目', '${songs.length}'),
              ('可用谱面', '$charts'),
              ('分类', '$genres'),
              ('本地体积', _bytes == null ? '读取中…' : _formatBytes(_bytes!)),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final text = await widget.loadLicense();
              if (!context.mounted) return;
              await Navigator.of(context).push(AppRoute(
                  builder: (_) => AppPage(
                      title: '字体与第三方许可',
                      menuAction: widget.menuAction,
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            const Text('本软件使用了 MiSans 字体。'),
                            Text(text),
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'))
                          ])))));
            },
            icon: const Icon(Icons.description_outlined),
            label: const Text('查看全文许可'),
          ),
          const AppSectionTitle('应用'),
          const _InfoBox(
            rows: [
              ('版本', appVersionLabel),
              ('包名', 'dev.tsumugi.songquery'),
            ],
          ),
          const AppSectionTitle('渲染诊断'),
          _RenderDiagnostics(),
        ],
      ),
    );
  }
}

/// 玻璃渲染的自诊断。
///
/// 存在的理由：液态玻璃有两级降级，**都是静默的** ——
/// 1. 这台设备的图形后端不支持 shader 滤镜（Skia）→ 只剩磨砂，没有折射扭曲；
/// 2. `fluid_glass` 的 fragment program 没加载成功 → 同样只剩磨砂。
///
/// 两种情况下界面完全正常、不报错，只是「效果不见了」。真机上说「没有扭曲」
/// 时，光看界面分不清是哪种，所以把状态摆在这里。
class _RenderDiagnostics extends StatefulWidget {
  @override
  State<_RenderDiagnostics> createState() => _RenderDiagnosticsState();
}

class _RenderDiagnosticsState extends State<_RenderDiagnostics> {
  @override
  void initState() {
    super.initState();
    // 加载是异步的：首帧可能还在「加载中」，完成后刷一次。
    if (!FluidGlass.isReady) {
      FluidGlass.ensureInitialized().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = isRuntimeShaderSupported();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoBox(
          rows: [
            ('shader 滤镜', supported ? '支持（Impeller）' : '不支持（磨砂回退）'),
            ('玻璃 shader', FluidGlass.isReady ? '已加载' : '加载中…'),
            ('玻璃库', 'fluid_glass 0.6.1（Kyant0 移植）'),
          ],
        ),
        if (!supported)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              '当前图形后端不支持 shader 滤镜，底栏退化为纯磨砂玻璃。'
              '这通常意味着 Impeller 未启用。',
              style: TextStyle(fontSize: 12, color: context.cardMuted),
            ),
          ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.rows});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => Chamfer(
        fill: AppPalette.card,
        child: Column(
          children: [
            for (final row in rows) AppInfoRow(row.$1, row.$2),
          ],
        ),
      );
}
