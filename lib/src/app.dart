import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluid_glass/fluid_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
// 只为 ScrollCacheExtent：material/widgets 都没把它 re-export 出来，
// 而 ListView.cacheExtent 已废弃、替代品正是这个类型。
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bottom_bar.dart';
import 'domain.dart';
import 'motion.dart';
import 'prefetch.dart';
import 'repository.dart';
import 'screens.dart';
import 'theme.dart';

class SongQueryApp extends StatefulWidget {
  const SongQueryApp({
    super.key,
    required this.preferences,
    this.repository,
    this.bundledLoader,
  });

  final SharedPreferences preferences;

  /// 注入点：默认走真实仓储。测试里换成假的，就能跑真正的启动 / 更新 / 失败 / 清空
  /// 流程 —— 这层是应用级的错误兜底（网络挂了要保留旧曲库、不能把界面清空），
  /// 之前因为构造写死 `SongRepository()` 而完全没被覆盖到。
  final SongRepository? repository;

  /// 注入点：内置曲库怎么读。默认走 `rootBundle`（真实资产通道）。
  ///
  /// 单测里换成直接读文件的实现：`rootBundle` 在 flutter_test 里要真实事件循环
  /// 才推进，同一文件里连跑多个 widget 用例时它会在第二个之后卡住，
  /// 表现出来就是界面永远停在「正在读取曲库…」—— 这是测试环境的问题，
  /// 但也说明启动链路该有个明确的接缝。
  final Future<Dataset?> Function()? bundledLoader;

  @override
  State<SongQueryApp> createState() => _SongQueryAppState();
}

class _SongQueryAppState extends State<SongQueryApp> {
  late final _repository = widget.repository ?? SongRepository();

  /// 必须用 key 拿 messenger，不能 `ScaffoldMessenger.of(context)`。
  ///
  /// 这个 State 的 context 在 `MaterialApp` **之上**，而 ScaffoldMessenger 是
  /// MaterialApp 自己插在内部的 —— 往上找永远找不到，会直接抛
  /// 「No ScaffoldMessenger widget found」，提示弹不出来还顺带扔个异步异常。
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Dataset? _dataset;
  String _status = '正在读取曲库…';
  String? _error;
  String _scheme = 'official';
  ThemeMode _themeMode = ThemeMode.system;
  bool _busy = false;
  int _revision = 0;

  /// 0..1 的下载进度；null 表示进度未知（服务器没给 Content-Length）。
  double? _progress;

  @override
  void initState() {
    super.initState();
    final savedScheme =
        widget.preferences.getString('fontScheme') ?? 'official';
    _scheme = switch (savedScheme) {
      'official' || 'classic' || 'system' => savedScheme,
      _ => 'official',
    };
    _themeMode = switch (widget.preferences.getString('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => widget.preferences.getBool('followSystemDarkMode') == false
          ? ThemeMode.light
          : ThemeMode.system,
    };
    _boot();
  }

  String get _effectiveScheme => switch (_scheme) {
        'official' || 'classic' || 'system' => _scheme,
        _ => 'official',
      };

  Future<void> _boot() async {
    final local = await _repository.loadLocal();
    final bundled = local == null
        ? await (widget.bundledLoader ?? SongRepository.loadBundled)()
        : null;
    if (!mounted) return;
    setState(() {
      _dataset = local ?? bundled;
      _status = local != null
          ? '本地曲库已就绪'
          : bundled != null
              ? '已加载内置曲库'
              : '尚未安装曲库';
    });
    if (local == null) {
      await _update(silent: true);
    } else {
      unawaited(_update(silent: true));
    }
  }

  Future<void> _update({bool silent = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final next = await _repository.fetchAndInstall(
        onProgress: (received, total, _) {
          if (!mounted || total <= 0) return;
          final ratio = (received / total).clamp(0.0, 1.0);
          // 数据流按块回调，逐块 setState 会把主线程刷爆；变化满 2% 才重建。
          final last = _progress;
          if (last == null || (ratio - last).abs() >= 0.02) {
            setState(() => _progress = ratio);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _dataset = next;
        _status = '曲库已更新';
        _error = null;
        _progress = null;
        _revision++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = _dataset == null ? '曲库下载失败' : '离线使用已安装曲库';
        _progress = null;
      });
      if (!silent) {
        _messenger.currentState
            ?.showSnackBar(SnackBar(content: Text('更新失败，保留现有曲库：$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _clear() async {
    await _repository.clear();
    if (!mounted) return;
    setState(() {
      _dataset = null;
      _status = '本地曲库已删除';
      _revision++;
    });
  }

  Future<void> _setScheme(String value) async {
    final normalized = switch (value) {
      'official' || 'classic' || 'system' => value,
      _ => 'official',
    };
    await widget.preferences.setString('fontScheme', normalized);
    if (mounted) setState(() => _scheme = normalized);
  }

  Future<void> _setThemeMode(ThemeMode value) async {
    if (mounted) setState(() => _themeMode = value);
    await widget.preferences.setString('themeMode', value.name);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '音击曲库',
        scaffoldMessengerKey: _messenger,
        theme: buildTheme(_effectiveScheme),
        darkTheme: buildTheme(_effectiveScheme, brightness: Brightness.dark),
        themeMode: _themeMode,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: context.systemBars,
          child: child!,
        ),
        home: HomeScreen(
          dataset: _dataset,
          status: _status,
          error: _error,
          busy: _busy,
          progress: _progress,
          revision: _revision,
          scheme: _scheme,
          themeMode: _themeMode,
          onThemeMode: _setThemeMode,
          onUpdate: () => _update(),
          onScheme: _setScheme,
          onClear: _clear,
          loadLocalBytes: _repository.localBytes,
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.dataset,
    required this.status,
    required this.error,
    required this.busy,
    required this.progress,
    required this.revision,
    required this.scheme,
    required this.onUpdate,
    required this.onScheme,
    required this.onClear,
    required this.loadLocalBytes,
    this.themeMode = ThemeMode.system,
    this.onThemeMode,
  });
  final Dataset? dataset;
  final String status;
  final String? error;
  final bool busy;
  final double? progress;
  final int revision;
  final String scheme;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode)? onThemeMode;
  final Future<void> Function() onUpdate;
  final Future<void> Function(String) onScheme;
  final Future<void> Function() onClear;

  /// 关于页要显示「本地体积」。走回调而不是传数值：这个数只有真去看的时候才需要，
  /// 而它的大小又要跟着删除/更新变。
  final Future<int> Function() loadLocalBytes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  /// 排序区三栏 = 游戏里三组设置，各选一个、互不冲突：
  /// 茶色「タブ設定」决定怎么分段，绿色「タブ内ソート」决定段内顺序，
  /// 蓝色「ライバルスコア」决定对手榜显示哪项分数（本曲库无成绩数据）。
  TabGroup _tabGroup = TabGroup.genre;
  TabSort _tabSort = TabSort.recommended;
  RivalScore _rivalScore = RivalScore.technical;
  SongFilters _filters = SongFilters.empty;
  SongEngine? _engine;

  /// 「关于」是**路由栈里的一页**，它拿到的是入栈那一刻的快照。曲库被删、更新完成
  /// 都发生在根状态里，而这页不会自己重建 —— 于是「删完曲库，统计还是旧的、
  /// 删除按钮还能再按一次」。这个计数器就是那页的刷新信号。
  final _libraryTick = ValueNotifier<int>(0);

  /// 卡片高度 120 + 底部间距 10。字号放大时整行必须跟着长 —— 固定 130 在
  /// 1.6 倍字号下会让卡片内容垂直溢出（实测溢出 19px，小屏 + 无障碍字号的常见组合）。
  static const _cardBody = 231.6875;
  static const _cardGap = 12.0;

  static double rowExtentOf(BuildContext context) {
    // 上限 1.5：再大就让卡片长得过头，宁可在极端字号下接受稍紧的排版。
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.5);
    return (_cardBody + _cardGap) * scale;
  }

  /// 曲绘预取。与 [_Jacket] 共用同一份磁盘缓存（key 就是文件名）。
  late final PrefetchQueue _jackets = PrefetchQueue(load: _loadJacket);

  Future<void> _loadJacket(String artwork) async {
    // 只预取首选镜像；失败交给队列重试。可见图本身另有三条线路的回退。
    await DefaultCacheManager().downloadFile(
      '${jacketBases.first}$artwork',
      key: artwork,
    );
  }

  /// 上一次预取用了哪个起始索引。滚动回调是**每帧**触发的，而一屏内首索引
  /// 通常不变；不短路的话每帧都要算一遍索引、再对 4 个已去重条目做 Set.add。
  /// 成本不大但完全没必要，何况它跑在滚动回调里（UI 线程最敏感的路径）。
  int _prefetchFirst = -1;

  /// 预取滚动方向往下 4 张。等卡片真被构建才去取就晚了 —— 曲绘 TTFB 一秒以上。
  void _prefetchAhead(List<Song> results, double offset, double extent) {
    if (results.isEmpty) return;
    final first =
        (offset / extent).floor().clamp(0, results.length - 1);
    if (first == _prefetchFirst) return;
    _prefetchFirst = first;
    final end = (first + 4).clamp(0, results.length);
    _jackets.prefetch([for (var i = first; i < end; i++) results[i].artwork]);
  }

  @override
  void initState() {
    super.initState();
    _rebuildEngine();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.dataset != widget.dataset) {
      _rebuildEngine();
    }
    final libraryChanged = oldWidget.dataset != widget.dataset ||
        oldWidget.status != widget.status ||
        oldWidget.error != widget.error ||
        oldWidget.busy != widget.busy ||
        oldWidget.revision != widget.revision;
    if (!libraryChanged) return;
    // 推到帧后再通知：didUpdateWidget 发生在构建阶段，这里直接置值会让
    // 监听者在 build 期间标脏，撞上框架「build 期间不能 markNeedsBuild」的断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _libraryTick.value++;
    });
  }

  void _rebuildEngine() {
    _engine = widget.dataset == null ? null : SongEngine(widget.dataset!.songs);
    // 结果集换了，预取短路键必须复位，否则同索引的新结果不会去取图。
    _prefetchFirst = -1;
  }

  @override
  void dispose() {
    _jackets.dispose();
    _listController.dispose();
    _searchController.dispose();
    _libraryTick.dispose();
    _backdrop.dispose();
    super.dispose();
  }

  /// 列表数据按段返回：段头 + 段内曲目。搜索态不分段（相关度顺序本身就是
  /// 一层排序，再套分组只会把最相关的结果拆散）。
  List<SongGroup> get _groups {
    final engine = _engine;
    if (engine == null) return const [];
    if (_query.trim().isEmpty) {
      return engine.listGrouped(
        group: _tabGroup,
        sort: _tabSort,
        filter: _filters,
        predicate: _passesLevels,
      );
    }
    final hits = engine
        .search(_query)
        .map((hit) => hit.song)
        .where(_passesSearchFilters)
        .where(_passesLevels)
        .toList();
    return [SongGroup('', hits)];
  }

  List<Song> get _songs => [for (final g in _groups) ...g.songs];

  /// 搜索结果也要过筛选 —— 直接复用 [SongFilters.matches]，
  /// 别再在这里抄一份判断（抄出来的那份迟早和浏览列表的走偏）。
  bool _passesSearchFilters(Song song) => _filters.matches(song, SortKey.title);

  bool _passesLevels(Song song) =>
      (_levels.isEmpty && _difficulties.isEmpty) ||
      song.charts.any((c) =>
          c.enabled &&
          (_difficulties.isEmpty || _difficulties.contains(c.difficulty)) &&
          (_levels.isEmpty ||
              _levels.contains(c.levelLabel ?? c.level.toString())));

  /// 排序状态栏文案：写清当前「分组 › 段内排序」的组合。
  String get _sortStatus {
    if (_query.trim().isNotEmpty) {
      return '搜索结果 · 相关度优先（最多先取60首再筛选）';
    }
    return '列表排序 · ${_tabGroup.label} › ${_tabSort.label}';
  }

  final _listController = ScrollController();

  /// 页面内容的 backdrop：`BackdropLayer` 把整屏内容捕获进它，底栏的玻璃
  /// 从这里取"下面的东西"来折射。**两侧必须是同一个实例**，否则玻璃折到
  /// 的是一片空白。
  ///
  /// 以前这里挂着一个 `_scrolling` notifier，用来在滚动时让手写玻璃跳过
  /// 折射层。换成 `fluid_glass` 后不需要了：库自己把 accent 副本的捕获
  /// 做成"内容不变就只抓一次"，滚动帧本来就不额外付捕获的钱；而在滚动时
  /// 偷偷关掉折射反而会让玻璃在起手/停手的瞬间闪一下。
  final _backdrop = LayerBackdrop();

  final Set<int> _difficulties = {};
  final Set<String> _levels = {};

  /// 「重置排序」：三栏回到各自的默认（表格里 ★ 标的那一项）。
  void _resetSortSlots() => _changed(() {
        _tabGroup = TabGroup.genre;
        _tabSort = TabSort.recommended;
        _rivalScore = RivalScore.technical;
      });

  /// 三栏下拉的统一外观。
  ///
  /// 快照里没有数据的项（`available == false`）照表格列出来，但
  /// `enabled: false` + 灰字 —— 既看得出游戏里还有这一项，也不会让人选进去
  /// 之后发现列表根本没动。当前值本身不可用时同样显示成灰色。
  Widget _sortDropdown<T>({
    required String keyPrefix,
    required T value,
    required List<T> options,
    required String Function(T) labelOf,
    required bool Function(T) enabledOf,
    required ValueChanged<T>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DropdownButtonFormField<T>(
          // 选中值变了要换 key，否则 FormField 会抱着旧的 initialValue 不放。
          key: ValueKey('$keyPrefix-$value'),
          initialValue: value,
          isExpanded: true,
          dropdownColor: context.controlSurface,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: enabledOf(value) ? context.cardInk : context.cardFaint,
              ),
          iconEnabledColor: context.cardInk,
          iconDisabledColor: context.cardFaint,
          items: [
            for (final option in options)
              DropdownMenuItem<T>(
                value: option,
                enabled: enabledOf(option),
                child: Text(
                  labelOf(option),
                  style: TextStyle(
                    color: enabledOf(option)
                        ? context.cardInk
                        : context.cardFaint,
                  ),
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      );

  StateSetter? _refreshSearch;
  void _changed(VoidCallback action) {
    setState(action);
    // 排序/筛选/搜索词变了 → 结果集变了，预取短路键复位。
    _prefetchFirst = -1;
    _refreshSearch?.call(() {});
  }

  /// 当前页签。三个页签用 IndexedStack 同框：切回「主页」时曲库列表的滚动位置、
  /// 搜索框里没提交的字都还在 —— 换成 push/pop 换页会把这些状态一起丢掉。
  AppTab _tab = AppTab.home;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 选中胶囊放大的是「染过色的页签副本」（库的 accent 层）。参考 App 用
    // 蓝色 #0088FF / #0091FF 标记选中，但本项目是黑白街机风，用户也明确
    // 「不要加多余的颜色」—— 所以 accent 直接取内容的墨色：
    // 选中态只靠「玻璃胶囊 + 按压放大」表达，不引入第二种色相。
    final ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return LiquidGlassTheme(
      colors: LiquidGlassColors.forBrightness(Theme.of(context).brightness)
          .copyWith(accent: ink),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) => Scaffold(
          // **整屏内容都交给 BackdropLayer 捕获**，底栏的玻璃才有东西可折。
          // 玻璃组件画在它上面，是它的兄弟节点而不是子节点 —— 子节点会被
          // 一起捕获进纹理，等于玻璃折自己。
          //
          // Stack 必须 Clip.none：选中胶囊按压时会长到面板外并带投影，
          // Flutter 的 Stack 一溢出就裁剪（参考实现是 Compose 的 Box，不裁）。
          body: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: BackdropLayer(
            backdrop: _backdrop,
            child: Stack(children: [
              // RepaintBoundary：全屏背景是**静态**的（平铺纹理 + 反相
              // colorFilter，满屏下来是几十次带滤镜的 drawImageRect），
              // 隔成独立 layer 后只在主题/尺寸变化时重画。
              const Positioned.fill(
                  child: RepaintBoundary(
                      child: IgnorePointer(child: MusicBackdrop()))),
              Positioned.fill(
                  child: SafeArea(
                      child: IndexedStack(index: _tab.index, children: [
                Column(children: [
                  if (widget.busy) LinearProgressIndicator(value: widget.progress),
                  Expanded(child: _buildResults(widget.dataset, _groups)),
                ]),
                const ToolsPlaceholderScreen(),
                ProfilePlaceholderScreen(
                    onSettings: _openSettings, onAbout: _openAbout),
              ]))),
            ]),
          ),
        ),
        LiquidGlassBar(
            current: _tab,
            onTab: (tab) => setState(() => _tab = tab),
            onSearch: _openSearch,
            backdrop: _backdrop),
      ]));

  Future<void> _openSearch() async {
    await Navigator.of(context).push(AppRoute(
        builder: (_) => StatefulBuilder(builder: (context, refresh) {
              _refreshSearch = refresh;
              final songs = widget.dataset?.songs ?? <Song>[];
              final genres = songs
                  .map((s) => s.genre)
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();
              // 角色按 id 去重：上游存在同名不同 id 的联动角色，
              // 只按名字 toSet 会把它们合并成一条。
              final characterIds = <String, String>{};
              for (final s in songs) {
                final name = s.character;
                if (name == null) continue;
                characterIds.putIfAbsent(name, () => s.characterId ?? '');
              }
              final homeCharacters = [
                for (final e in characterIds.entries)
                  if (isHomeCharacterId(e.value)) e
              ]..sort((a, b) {
                  final ai = int.tryParse(a.value) ?? 999999;
                  final bi = int.tryParse(b.value) ?? 999999;
                  return ai.compareTo(bi);
                });
              final otherCharacters = [
                for (final e in characterIds.entries)
                  if (!isHomeCharacterId(e.value)) e.key
              ];
              final releases = songs
                  .map((s) => s.releaseTag)
                  .whereType<String>()
                  .toSet()
                  .toList();
              return AppPage(
                  title: '搜索与筛选',
                  topSpacing: 40,
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    Chamfer(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text('关键词', style: TextStyle(color: context.cardInk)),
                          _SearchInput(
                              controller: _searchController,
                              onChanged: (v) => _changed(() => _query = v),
                              onClear: () {
                                _searchController.clear();
                                _changed(() => _query = '');
                              }),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton(
                                onPressed: () => _changed(() {
                                      _filters = SongFilters.empty;
                                      _difficulties.clear();
                                      _levels.clear();
                                    }),
                                child: const Text('清空全部筛选')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('应用并返回')),
                          ]),
                          const SizedBox(height: 12),
                          // 三栏对应游戏里三组设置，各选一个、可同时生效：
                          // 分类（怎么分段）→ 排序（段内顺序）→ 对手榜（哪项分数）。
                          // 快照里没有数据的项照表格列出来，但灰掉不可选。
                          _sortDropdown<TabGroup>(
                            keyPrefix: 'tab-group',
                            value: _tabGroup,
                            options: TabGroup.values,
                            labelOf: (v) => v.label,
                            enabledOf: (v) => v.available,
                            onChanged: _query.trim().isNotEmpty
                                ? null
                                : (v) => _changed(() => _tabGroup = v),
                          ),
                          _sortDropdown<TabSort>(
                            keyPrefix: 'tab-sort',
                            value: _tabSort,
                            options: TabSort.values,
                            labelOf: (v) => v.label,
                            enabledOf: (v) => v.available,
                            onChanged: _query.trim().isNotEmpty
                                ? null
                                : (v) => _changed(() => _tabSort = v),
                          ),
                          _sortDropdown<RivalScore>(
                            keyPrefix: 'rival-score',
                            value: _rivalScore,
                            options: RivalScore.values,
                            labelOf: (v) => v.label,
                            enabledOf: (v) => v.available,
                            onChanged: _query.trim().isNotEmpty
                                ? null
                                : (v) => _changed(() => _rivalScore = v),
                          ),
                          Wrap(spacing: 8, children: [
                            OutlinedButton(
                                onPressed: _resetSortSlots,
                                child: const Text('重置排序')),
                          ]),
                        ])),
                    const SizedBox(height: 12),
                    // 这两行原本裸在背景上，320@2.0 时正好被黄绿斜带横穿，
                    // 黑字压在黄带上完全看不清 —— 和设置页一样收进卡片。
                    Chamfer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _sortStatus,
                            style: TextStyle(color: context.cardInk),
                          ),
                          Text(
                            '结果 ${_songs.length} 首 · 筛选 ${_filters.count + _levels.length + _difficulties.length} 项',
                            style: TextStyle(color: context.cardMuted),
                          ),
                        ],
                      ),
                    ),
                    // 行条（あ〜ん / 版本跳转）原本随「曲名／角色／版本」排序出现，
                    // 那几种排序已下线，行条一并移除。
                    const AppSectionTitle('难度'),
                    Wrap(spacing: 6, children: [
                      for (var i = 0; i < 5; i++)
                        FilterChip(
                            label: Text(difficultyNames[i]),
                            selected: _difficulties.contains(i),
                            onSelected: (yes) => _changed(() => yes
                                ? _difficulties.add(i)
                                : _difficulties.remove(i)))
                    ]),
                    _filterGroup('分类', genres, _filters.genres,
                        (v) => _filters = _filters.copyWith(genres: v)),
                    _filterGroup('版本', releases, _filters.releaseTags,
                        (v) => _filters = _filters.copyWith(releaseTags: v)),
                    const AppSectionTitle('等级'),
                    Wrap(spacing: 6, children: [
                      for (final level in [
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '7+',
                        '8',
                        '8+',
                        '9',
                        '9+',
                        '10',
                        '10+',
                        '11',
                        '11+',
                        '12',
                        '12+',
                        '13',
                        '13+',
                        '14',
                        '14+',
                        '15'
                      ])
                        FilterChip(
                            label: Text(level),
                            selected: _levels.contains(level),
                            onSelected: (yes) => _changed(() => yes
                                ? _levels.add(level)
                                : _levels.remove(level)))
                    ]),
                    _characterFilterGroup(
                        [for (final e in homeCharacters) e.key],
                        otherCharacters,
                        _filters.characters,
                        (v) => _filters = _filters.copyWith(characters: v)),
                  ]));
            })));
    _refreshSearch = null;
  }

  Widget _filterGroup(String title, List<String> values, Set<String> selected,
          ValueChanged<Set<String>> update) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppSectionTitle(title),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final v in values)
            FilterChip(
                label: Text(v),
                selected: selected.contains(v),
                onSelected: (yes) => _changed(() {
                      final next = {...selected};
                      yes ? next.add(v) : next.remove(v);
                      update(next);
                    }))
        ]),
      ]);

  /// 角色筛选：本家与非本家分两段，中间留一行空隙。
  Widget _characterFilterGroup(List<String> home, List<String> other,
      Set<String> selected, ValueChanged<Set<String>> update) {
    Widget chips(List<String> values) =>
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final v in values)
            FilterChip(
                label: Text(v),
                selected: selected.contains(v),
                onSelected: (yes) => _changed(() {
                      final next = {...selected};
                      yes ? next.add(v) : next.remove(v);
                      update(next);
                    }))
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const AppSectionTitle('角色'),
      if (home.isNotEmpty) chips(home),
      if (home.isNotEmpty && other.isNotEmpty) const SizedBox(height: 18),
      if (other.isNotEmpty) chips(other),
    ]);
  }

  /// 结果为空时的文案。三种「空」不是一回事，之前一律写「曲库是空的」——
  /// 于是选了分类 + 角色、交集为空的时候，界面在说图书馆没书。
  String _emptyLabel(Dataset? dataset) {
    if (_query.trim().isNotEmpty) return '没有匹配的曲目';
    if (dataset == null || dataset.songs.isEmpty) return '曲库是空的';
    if (_filters.count > 0 || _levels.isNotEmpty || _difficulties.isNotEmpty) {
      return '没有符合筛选条件的曲目';
    }
    return '曲库是空的';
  }

  Widget _buildResults(Dataset? dataset, List<SongGroup> groups) {
    final results = [for (final group in groups) ...group.songs];
    if (dataset == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.library_music_outlined,
                size: 48,
                color: AppPalette.magenta,
              ),
              const SizedBox(height: 14),
              Text(widget.status, textAlign: TextAlign.center),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: AppPalette.danger),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: widget.busy ? null : widget.onUpdate,
                child: Text(widget.busy ? '正在下载…' : '下载曲库'),
              ),
            ],
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          _emptyLabel(dataset),
          style: TextStyle(color: context.inkFaint),
        ),
      );
    }
    final reasons = _query.isEmpty
        ? const <String, String>{}
        : {
            for (final hit in _engine!.search(_query))
              hit.song.id: hit.reason ?? '',
          };
    final extent = rowExtentOf(context);
    // 首屏：前 6 张直接排队。queue 按文件名去重，所以重复构建不会重复请求，
    // 而已被可见卡片在取的图会命中缓存管理器的 in-flight 合并，不会多打一次。
    // 判重用 O(1) 的 contains —— `seen` 是 O(n) 拷贝，滚过一千首后每次 build
    // 都会白复制一个千元素集合。
    if (!_jackets.contains(results.first.artwork)) {
      _prefetchAhead(results, 0, extent);
    }
    // 组头和卡片拍平到同一个 ListView：分组标题跟着列表一起滚，不单独吸顶。
    final items = <Object>[];
    for (final group in groups) {
      if (group.label.isNotEmpty) {
        items.add((label: group.label, count: group.songs.length));
      }
      items.addAll(group.songs);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 滚动中只做预取；底栏的玻璃由库自己管，不需要在这里切换降级模式。
        if (notification is ScrollUpdateNotification) {
          _prefetchAhead(results, notification.metrics.pixels, extent);
        }
        return false;
      },
      child: ListView.builder(
        key: const PageStorageKey("song-list"),
        controller: _listController,
        itemCount: items.length,
        // **1.5 屏**而不是 3 屏。这张卡的构建成本不低（IntrinsicHeight 一次
        // 预测量 + 两个 WordSafeText 各自跑 TextPainter + 平铺电路纹理），
        // 单张实测 3.5~4.3ms。3 屏 = 每侧多养 2 张，滚动一屏要构建 6~9 张，
        // UI 线程直接超帧。1.5 屏够防白屏，每帧只构建 3~5 张。
        scrollCacheExtent: ScrollCacheExtent.pixels(extent * 1.5),
        padding: EdgeInsets.fromLTRB(
            15,
            24,
            15,
            // 底栏高度 + 底边距 + 16dp 呼吸位。以前这里借的是旧圆钮的
            // `BottomControls.bottom`，换成导航栏后两者不再相关：顶部留白
            // 由 SafeArea 保证，这里只需固定一份让首屏不贴边。
            LiquidGlassBar.clearance(context)),
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is ({String label, int count})) {
            return _GroupHeader(
              key: ValueKey('group-${item.label}'),
              label: item.label,
              count: item.count,
            );
          }
          final song = item as Song;
          return SongCardView(
            song: song,
            reason: reasons[song.id]?.isEmpty == true ? null : reasons[song.id],
            onTap: () => Navigator.of(
              context,
            ).push(AppRoute(builder: (_) => DetailScreen(song: song))),
          );
        },
      ),
    );
  }

  void _openSettings() => Navigator.of(context).push(
        AppRoute(
          builder: (_) => SettingsScreen(
              scheme: widget.scheme,
              onChange: widget.onScheme,
              themeMode: widget.themeMode,
              onThemeMode: widget.onThemeMode),
        ),
      );
  void _openAbout() => Navigator.of(context).push(
        AppRoute(
          // 放在 ValueListenableBuilder 里，而不是直接构造 —— 否则这页会一直
          // 显示入栈那一刻的曲库统计（删库之后仍然写着 1112 首、按钮还能点）。
          builder: (_) => ValueListenableBuilder<int>(
            valueListenable: _libraryTick,
            builder: (_, tick, __) => AboutScreen(
              dataset: widget.dataset,
              status: widget.status,
              error: widget.error,
              busy: widget.busy,
              revision: tick,
              loadBytes: widget.loadLocalBytes,
              loadLicense: loadFontLicenseText,
              onUpdate: widget.onUpdate,
              onClear: widget.onClear,
            ),
          ),
        ),
      );
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: AppTokens.controlHeight),
        decoration: BoxDecoration(
          color: context.controlSurface,
          border: Border.all(color: context.outline, width: 1.5),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '曲名／读音／别名／ID',
                  // 默认 hint 单行：320 宽 + 2.0 字号下会截成「曲名／读音／别…」。
                  // 放宽到两行，整句提示都能看到。
                  hintMaxLines: 2,
                  hintStyle: TextStyle(
                      fontSize: AppTokens.controlFontSize,
                      color: context.cardMuted),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                style: TextStyle(
                    fontSize: 14,
                    color: context.cardInk,
                    fontWeight: FontWeight.bold),
              ),
            ),
            if (controller.text.isEmpty)
              Container(
                  width: 40,
                  height: 46,
                  color: context.isDark ? AppPalette.cardActive : Colors.white,
                  child: Icon(Icons.search, size: 20, color: context.ink)),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: onClear,
                tooltip: '清除搜索',
                icon: Icon(Icons.close, size: 20, color: context.cardInk),
              ),
          ],
        ),
      );
}

class SongCardView extends StatelessWidget {
  const SongCardView(
      {super.key,
      required this.song,
      this.reason,
      required this.onTap,
      this.height});
  final Song song;
  final String? reason;
  final VoidCallback onTap;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 350;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // 封面对读曲名没有帮助，2.0 字号下把它收小一点：320 宽时文字列只有
    // 162dp，「ＧＯ！ＧＯ！」这种 6 个全角字符要 204dp，标题要么被断词、要么
    // 缩到 26.7 —— 和作者名（26）一样大，标题层级就没了。让出 24dp 之后
    // 标题能停在 31，读起来还是「标题」。更宽的屏幕上文字列本来就够，不动。
    final image = narrow ? (scale >= 1.8 ? 64.0 : 88.0) : 104.0;
    // 卡片宽度 = 屏宽 − 列表左右各 15；文字列再让开卡片内边距 12×2、封面、
    // 间距和右侧 6dp 的留白。宽度得在这里算好传给 WordSafeText —— 卡片内部
    // 套着 IntrinsicHeight，里面再放 LayoutBuilder 会抛 intrinsic 断言。
    final textWidth = MediaQuery.sizeOf(context).width -
        30 -
        24 -
        image -
        (narrow ? 10 : 12) -
        6;
    final fonts = FontRoles.of(context);
    final fallback =
        fonts.content == 'Official' ? const ['MPLUS1p', 'MiSans'] : null;
    final minimum = height ?? (narrow ? 215.0 : 231.6875);
    // 作者名不截断（11-02 定的规矩），但长名单会把卡片撑到接近整屏：
    // 320@1.6 下 131 字符那首高 735dp，屏高才 844。按数据集分布只对长串
    // 降一档字号 —— 1112 首歌的 artist 长度 p50=16、p95=55、max=131，
    // 取 55 作阈值，95% 的卡片视觉完全不变。
    final artistName = song.artist ?? '—';
    final longArtist = artistName.length > 55;
    // 「LEVEL」标签宽度必须跟着字号长：原来 scale > 1.2 时固定 76dp，
    // 2.0 字号下 12px 变 24px，「LEVEL」放不进 76dp，被硬断成「LEVE / L」。
    // 46 × 字号 是量的实际宽度（1.6 → 73.6，2.0 → 92），下限 76 保持原样。
    final levelLabelWidth =
        scale > 1.2 ? math.max(76.0, 46 * scale) : (narrow ? 46.0 : 54.0);
    final charts = {for (final c in song.playableCharts) c.difficulty: c};
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressScale(
        // 整行宽的卡片不能用 .94 那种幅度：360dp 会缩掉 22dp，看着像跳了一下。
        // .985 只动 5dp，刚好够「按到了」。
        scale: .985,
        // RepaintBoundary 把卡片内容隔成独立 layer。ListView 自带的边界在
        // PressScale **外面**，所以缩放一动就要重画整卡（平铺电路纹理 + 白字
        // + 4 个难度环）。而**每次开始滚动都会触发一次按压动画**
        // （onPointerDown 立刻 down，位移超 8dp 才取消）—— 等于一滑就把一张卡
        // 拖进 240ms 的重绘区，这是「起手那一下顿」的直接来源。
        // 隔开后缩放只更新 layer 的 transform，内容不再重画。
        child: RepaintBoundary(
          child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ClipPath(
              clipper: const _SongCardClipper(18),
              child: CustomPaint(
                foregroundPainter: ChamferOutlinePainter(
                  18,
                  context.outline,
                  1,
                ),
                child: Container(
                  key: ValueKey('card-${song.id}'),
                  constraints: BoxConstraints(minHeight: minimum),
                  decoration: BoxDecoration(
                      color: context.card, image: context.cardCircuit),
                  child: IntrinsicHeight(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Expanded(
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                          key: ValueKey('jacket-${song.id}'),
                                          width: image,
                                          height: image,
                                          decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: Colors.black,
                                                  width: 3)),
                                          child: _Jacket(
                                              artwork: song.artwork,
                                              size: image - 6)),
                                      SizedBox(width: narrow ? 10 : 12),
                                      Expanded(
                                          child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6),
                                              child: Column(
                                                  key: ValueKey(
                                                      'info-${song.id}'),
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(song.genre ?? '',
                                                        style: TextStyle(
                                                            color: Color(
                                                                genreColors[song
                                                                        .genreId] ??
                                                                    AppPalette
                                                                        .magenta
                                                                        .toARGB32()),
                                                            fontSize: 12,
                                                            height: 1.4,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                    if (song.isNew)
                                                      Text('NEW',
                                                          style: TextStyle(
                                                              color: context
                                                                  .cardInk,
                                                              fontSize: 9)),
                                                    if (reason != null)
                                                      Text(reason!,
                                                          style: TextStyle(
                                                              color: context
                                                                  .cardMuted,
                                                              fontSize: 10)),
                                                    Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                top: 4,
                                                                bottom: 6),
                                                        child: WordSafeText(
                                                            song.title,
                                                            // 2.0 字号 + 320 宽下「GO!GO!」比文字列
                                                            // 还宽，原来被硬断成「GO!G / O!」。
                                                            minScale: .72,
                                                            maxWidth: textWidth,
                                                            style: TextStyle(
                                                                fontFamily: fonts
                                                                    .content,
                                                                fontFamilyFallback:
                                                                    fallback,
                                                                color: context
                                                                    .cardInk,
                                                                fontSize: narrow
                                                                    ? 17
                                                                    : 18,
                                                                height: 1.35,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold))),
                                                    WordSafeText(
                                                        'ARTIST: $artistName',
                                                        // 长串同样不能拦腰断：`7EVENDAYS⇔HOLIDAYS`
                                                        // 18 个字符，320@2.0 实测断成
                                                        // 「HOLIDA / YS」。作者名是次要信息，
                                                        // 下限放到 .62 也还看得清。
                                                        minScale: .62,
                                                        maxWidth: textWidth,
                                                        style: TextStyle(
                                                            fontFamily:
                                                                fonts.content,
                                                            fontFamilyFallback:
                                                                fallback,
                                                            fontSize: longArtist
                                                                ? 11.5
                                                                : 13,
                                                            height: longArtist
                                                                ? 1.35
                                                                : 1.5,
                                                            color: context
                                                                .cardMuted,
                                                            fontWeight:
                                                                context.isDark
                                                                    ? FontWeight
                                                                        .w500
                                                                    : FontWeight
                                                                        .w600)),
                                                  ]))),
                                    ]))),
                        Container(
                            key: ValueKey('levels-${song.id}'),
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border(
                                    top: BorderSide(color: context.outline))),
                            child: Row(children: [
                              SizedBox(
                                  width: levelLabelWidth,
                                  child: Text('LEVEL',
                                      style: TextStyle(
                                          fontFamily: fonts.numeric,
                                          fontSize: 12,
                                          color: context.cardMuted))),
                              Expanded(child: Builder(builder: (context) {
                                final available =
                                    MediaQuery.sizeOf(context).width -
                                        30 -
                                        24 -
                                        levelLabelWidth;
                                final items = charts.values.toList();
                                final columns = math.max(1, items.length);
                                final cell =
                                    (available - (columns - 1) * 5) / columns;
                                return Wrap(
                                    spacing: 5,
                                    runSpacing: 6,
                                    children: [
                                      for (final chart in items)
                                        SizedBox(
                                            width: cell,
                                            child: Center(
                                                child: DifficultyRing(
                                                    chart: chart,
                                                    label: song
                                                        .displayLevel(chart))))
                                    ]);
                              })),
                            ])),
                        Container(
                            key: ValueKey('character-${song.id}'),
                            constraints: const BoxConstraints(minHeight: 34),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(
                                    color: context.outline, width: 3)),
                            // 2.0 字号下一行塞不下标签和角色名：Row 只能把
                            // 「Character : 」压成两行，冒号独占一行很难看。
                            // 大字号时改成分行排（标签一行、角色名一行），
                            // 1.0/1.6 仍走原来的单行 Row，视觉不变。
                            child: scale >= 1.8
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        Text('Character : ',
                                            style: TextStyle(
                                                fontSize: 13,
                                                height: 1.25,
                                                color: context.characterMuted)),
                                        Text(song.character ?? '—',
                                            style: TextStyle(
                                                fontSize: 13,
                                                height: 1.25,
                                                color: context.characterInk,
                                                fontWeight: FontWeight.bold)),
                                      ])
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        Flexible(
                                            child: Text('Character : ',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.25,
                                                    color: context
                                                        .characterMuted))),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(song.character ?? '—',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.25,
                                                    color: context.characterInk,
                                                    fontWeight:
                                                        FontWeight.bold))),
                                      ])),
                      ])),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _SongCardClipper extends CustomClipper<Path> {
  const _SongCardClipper(this.size);
  final double size;
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width - size, 0)
    ..lineTo(s.width, size)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(covariant _SongCardClipper oldClipper) =>
      oldClipper.size != size;
}

class DifficultyRing extends StatelessWidget {
  const DifficultyRing({super.key, required this.chart, required this.label});
  final Chart chart;
  final String label;
  @override
  Widget build(BuildContext context) {
    final color =
        difficultyTones[chart.difficulty.clamp(0, difficultyTones.length - 1)];
    return CustomPaint(
        painter: _DifficultyRingPainter(color),
        child: Container(
          width: MediaQuery.textScalerOf(context).scale(1) > 1.2 ? 42 : 34,
          height: MediaQuery.textScalerOf(context).scale(1) > 1.2 ? 42 : 34,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(label,
                  style: TextStyle(
                    fontFamily: FontRoles.of(context).numeric,
                    fontSize: 15,
                    color: context.cardInk,
                    fontWeight: FontWeight.bold,
                  )),
            ),
          ),
        ));
  }
}

class _DifficultyRingPainter extends CustomPainter {
  const _DifficultyRingPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF787878);
    canvas.drawOval(rect, paint);
    canvas.drawArc(
        rect, -math.pi / 2, math.pi / 2, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_DifficultyRingPainter old) => old.color != color;
}

class _Jacket extends StatefulWidget {
  const _Jacket({required this.artwork, required this.size});
  final String? artwork;
  final double size;
  @override
  State<_Jacket> createState() => _JacketState();
}

class _JacketState extends State<_Jacket> {
  int _attempt = 0;
  Timer? _timer;
  @override
  void didUpdateWidget(covariant _Jacket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork != widget.artwork) {
      _timer?.cancel();
      _timer = null;
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artwork = widget.artwork;
    if (artwork == null) return _placeholder();
    final url = '${jacketBases[_attempt]}$artwork';
    // **按显示尺寸解码，不要按原图**。曲绘源图普遍 512² 甚至更大，而卡片上
    // 只显示 88/104dp；按原尺寸解码 = 每张多解 4~30 倍像素、多占 1~4MB，
    // 滚动时不断有新图进出内存缓存 → 解码 + 纹理上传 + GC 抖动全砸在滚动帧上。
    // `memCacheWidth` 只影响**内存里解码后的位图**，磁盘缓存仍是原文件，
    // 所以与预取（`DefaultCacheManager.downloadFile` 按 cacheKey 取）互不干扰。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (widget.size * dpr).round();
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CachedNetworkImage(
        key: ValueKey('$artwork@$_attempt'),
        imageUrl: url,
        // 缓存键必须与镜像无关：默认键就是 URL，换镜像等于换一条缓存记录，
        // A 线路挂掉改用 B 取到的图，等 A 恢复后又要重下一遍。
        cacheKey: artwork,
        memCacheWidth: px,
        memCacheHeight: px,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) {
          if (_attempt < jacketBases.length - 1 && _timer == null) {
            _timer = Timer(Duration(seconds: _attempt == 0 ? 2 : 5), () {
              if (mounted) setState(() => _attempt++);
              _timer = null;
            });
          }
          return _placeholder();
        },
      ),
    );
  }

  Widget _placeholder() => Container(
        width: widget.size,
        height: widget.size,
        color: const Color(0xFF353535),
        child: const Icon(
          Icons.music_note,
          color: AppPalette.onCardFaint,
          size: 20,
        ),
      );
}

/// 列表里的分组标题（分类 / 角色 / 版本 / 等级 / 五十音行 …）。
///
/// 跟着列表一起滚，不吸顶：吸顶要套 SliverPersistentHeader，而这里的组头
/// 只在「分类」这类分组下出现，吸顶反而会让第一张卡片被压掉一截。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({super.key, required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: AppPalette.magenta,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cardInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(color: context.cardMuted, fontSize: 12),
            ),
          ],
        ),
      );
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.song});
  final Song song;
  @override
  Widget build(BuildContext context) {
    final charts = song.playableCharts;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final textScale = scale.clamp(1.0, 2.0);
    final narrow = MediaQuery.sizeOf(context).width <= 350;
    // 但大字号下横排会把文字区挤到只剩百来 dp，「GO!GO!ラブリズム♥」被切成
    // 「GO! G / O! ラブリ / ズム」，比改动前更碎。这类字号改用上下堆叠：
    // 封面在上（可以真正放大），曲名在下占满整行宽度。
    final stackedHeader = textScale > 1.3;
    // 沿用主页的窄屏与字号规则，详情封面放大 20%。
    final jacketSize = (narrow ? (scale >= 1.8 ? 64.0 : 88.0) : 104.0) * 1.2;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
              child: OfficialBackground(child: SizedBox.expand())),
          SafeArea(
            child: ListView(
              // 详情页没有底部控件（左下角不该出现菜单钮），所以不再给
              // `BottomControls.clearance` 那 90dp 的避让位——那是给固定底栏
              // 留的，按钮撤掉之后只会变成一截看不见内容的死区。底部安全区
              // 由外层 SafeArea 负责，这里只留一点收尾留白。
              padding: const EdgeInsets.fromLTRB(16, 74, 16, 18),
              children: [
                if (stackedHeader)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Jacket(artwork: song.artwork, size: jacketSize),
                      const SizedBox(height: 12),
                      _titleBlock(context, fitTitle: true),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Jacket(artwork: song.artwork, size: jacketSize),
                      const SizedBox(width: 12),
                      Expanded(child: _titleBlock(context)),
                    ],
                  ),
                const SizedBox(height: 16),
                Chamfer(
                  fill: AppPalette.card,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      AppInfoRow('版本', song.releaseTag ?? '—'),
                      AppInfoRow('BPM', song.bpm?.toString() ?? '—'),
                      AppInfoRow('分类', song.genre ?? '—'),
                    ],
                  ),
                ),
                const _Section(title: 'CHARTS', name: '难度'),
                if (charts.isEmpty)
                  const Text('当前数据集中没有可用谱面。')
                else
                  for (final chart in charts)
                    _ChartDetail(chart: chart, label: song.displayLevel(chart)),
                if (song.aliases.isNotEmpty) ...[
                  const _Section(title: 'ALIASES', name: '别名'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final alias in song.aliases)
                        Chamfer(
                          fill: AppPalette.card,
                          padding: const EdgeInsets.all(9),
                          child: Text(
                            alias,
                            style: TextStyle(color: context.cardInk),
                          ),
                        ),
                    ],
                  ),
                ],
                // 所有字段都可能为空（例如只有 id 与曲名的残缺条目）。
                // 原来无条件渲染整节，结果是一张没有内容的黑色薄片 ——
                // minimal 用例在 390@1.0 下就是一条突兀的空缝。整节跟着内容走。
                if (song.chapter != null ||
                    song.character != null ||
                    song.enemyLevel != null ||
                    song.enemyType != null ||
                    song.dateAdded != null ||
                    song.isNew ||
                    song.isBonus ||
                    song.copyright != null) ...[
                  const _Section(title: 'INFO', name: '信息'),
                  Chamfer(
                    fill: AppPalette.card,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        if (song.chapter != null)
                          AppInfoRow('章节', song.chapter!),
                        if (song.character != null ||
                            song.enemyLevel != null ||
                            song.enemyType != null)
                          AppInfoRow(
                            '对战角色',
                            [
                              if (song.character != null) song.character!,
                              if (song.enemyLevel != null)
                                'Lv ${song.enemyLevel}',
                              if (song.enemyType != null) song.enemyType!,
                            ].join(' ／ '),
                          ),
                        if (song.dateAdded != null)
                          AppInfoRow('更新日期', song.dateAdded!),
                        if (song.isNew || song.isBonus)
                          AppInfoRow(
                            '标记',
                            [
                              if (song.isNew) '新曲',
                              if (song.isBonus) 'ボーナストラック',
                            ].join(' / '),
                          ),
                        if (song.copyright != null)
                          AppInfoRow('版权', song.copyright!),
                      ],
                    ),
                  ),
                ],
                if (song.wikiUrl != null ||
                    charts.any((chart) => chart.chartLink != null)) ...[
                  const _Section(title: 'LINKS', name: '外部链接'),
                  if (song.wikiUrl != null)
                    _LinkRow(label: '攻略 wiki', url: song.wikiUrl!),
                  for (final chart in charts)
                    if (chart.chartLink != null)
                      _LinkRow(
                        label: '${difficultyNames[chart.difficulty]} 谱面预览',
                        url: 'https://sdvx.in/ongeki/${chart.chartLink}.htm',
                      ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 15,
            left: 12,
            child: SafeArea(
                child: Semantics(
              button: true,
              label: '返回',
              // 网页端 `.fabback:active` 是 .94，同一个返回钮两边手感一致。
              child: PressScale(
                scale: .94,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Chamfer(
                    size: 7,
                    fill: AppPalette.card,
                    padding: const EdgeInsets.all(14),
                    child: Icon(Icons.arrow_back,
                        color: context.cardInk, size: 20),
                  ),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  /// 曲名 / 读音 / 作者三行：横排时挤在封面右侧，大字号堆叠时占满整行。
  ///
  /// `fitTitle` 用于堆叠布局：曲名占满整行后仍可能差几个像素放不下，
  /// 「GO!GO!ラブリズム♥」会把结尾的 ♥ 挤到单独一行（实测 390@1.6 就是这样）。
  /// 单行 + scaleDown 比让装饰符号掉行好，也避免在拉丁词中间断成「GO! G / O!」。
  Widget _titleBlock(BuildContext context, {bool fitTitle = false}) {
    final fonts = FontRoles.of(context);
    final titleStyle = TextStyle(
      fontFamily: fonts.content,
      fontSize: 19,
      color: context.isDark ? context.ink : context.cardInk,
      fontWeight: FontWeight.bold,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fitTitle)
          LayoutBuilder(builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: song.title, style: titleStyle),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final ratio =
                painter.width <= 0 ? 1.0 : constraints.maxWidth / painter.width;
            painter.dispose();
            // 缩一点点就能放下 → 单行缩放，避免 ♥ 之类被挤到第二行。
            // 但需要缩到 70% 以下说明曲名太长（数据集里最长 52 字符），
            // 硬缩会让标题比正文还小，标题层级倒挂；这种情况宁可排两行。
            if (ratio >= .7) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(song.title, style: titleStyle),
              );
            }
            // 缩太多就放弃单行，改为完整换行 —— 曲名同样不 ellipsis。
            return WordSafeText(
              song.title,
              style: titleStyle,
              maxWidth: constraints.maxWidth,
            );
          })
        else
          WordSafeText(song.title, style: titleStyle),
        if (song.titleKana != null)
          Text(
            song.titleKana!,
            style: TextStyle(
              color: context.isDark ? context.inkMuted : context.cardMuted,
              fontFamily: fonts.content,
            ),
          ),
        // 作者名一律完整显示，不截断 —— 和列表卡片同一规矩（11-02 定）。
        // 数据集里最长一条 131 字符（曲：…／歌：…[CV：…]），320@1.6 会占掉
        // 大半屏、把谱面区挤出首屏；这是完整换来的代价，已确认接受。
        // 空串仍不渲染，省掉一个空行。
        if ((song.artist ?? '').trim().isNotEmpty)
          WordSafeText(
            song.artist!.trim(),
            minScale: .62,
            style: TextStyle(
                color: context.isDark ? context.inkFaint : context.cardFaint),
          ),
      ],
    );
  }
}

class _ChartDetail extends StatelessWidget {
  const _ChartDetail({required this.chart, required this.label});
  final Chart chart;
  final String label;
  @override
  Widget build(BuildContext context) {
    final designer = (chart.designer ?? '').trim();
    final counts = [
      if (chart.noteCount != null) '物量 ${chart.noteCount}',
      if (chart.bells != null) '铃铛 ${chart.bells}',
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final attributeStyle = TextStyle(
      color: context.cardMuted,
      fontSize: AppTokens.captionFontSize,
      height: 1.7,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Chamfer(
        fill: AppPalette.card,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 42,
              color: difficultyTones[chart.difficulty.clamp(0, 4)],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    difficultyNames[chart.difficulty.clamp(0, 4)],
                    style: TextStyle(
                      color: context.cardInk,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (designer.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '谱师 $designer',
                          maxLines: 1,
                          softWrap: false,
                          style: attributeStyle,
                        ),
                      ),
                    ),
                  if (counts.isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        for (final count in counts)
                          WordSafeText(count, style: attributeStyle),
                      ],
                    ),
                  if (designer.isEmpty && counts.isEmpty)
                    Text('暂无谱面信息', style: attributeStyle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 等级文字宽度随内容变（「3」与「11.8」差 28dp），会把左侧副信息的
            // 可用宽度也带着变，于是四张卡片的换行位置各不相同 —— 320 宽截图里
            // BASIC/ADVANCED 一行放得下、EXPERT 的「物量 685」却被 8+ 挤断。
            // 固定一列宽度（随字号缩放），四张卡片的文字区就对齐了。
            SizedBox(
              width: 46 * textScale,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: context.cardInk,
                  fontFamily: FontRoles.of(context).numeric,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.name});
  final String title, name;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: AppPalette.magenta,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          Text(name, style: TextStyle(fontSize: 11, color: context.inkMuted)),
        ]),
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});
  final String label, url;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: const Icon(Icons.open_in_new, size: 16),
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      );
}
