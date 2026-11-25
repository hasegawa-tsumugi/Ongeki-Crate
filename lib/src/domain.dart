import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'collation_han.dart';

@immutable
class Chart {
  const Chart({
    required this.difficulty,
    required this.level,
    required this.levelDecimal,
    required this.levelValue,
    required this.enabled,
    this.levelLabel,
    this.designer,
    this.noteCount,
    this.bells,
    this.chartLink,
  });
  final int difficulty;
  final int level;
  final int levelDecimal;
  final double levelValue;
  final bool enabled;
  final String? levelLabel, designer, chartLink;
  final int? noteCount, bells;

  factory Chart.fromJson(Map<String, dynamic> j) => Chart(
        difficulty: _int(j['difficulty']),
        level: _int(j['level']),
        levelDecimal: _int(j['levelDecimal']),
        levelValue: _double(j['levelValue']),
        enabled: j['enabled'] == true,
        levelLabel: _str(j['levelLabel']),
        designer: _str(j['designer']),
        noteCount: _intOrNull(j['noteCount']),
        bells: _intOrNull(j['bells']),
        chartLink: _str(j['chartLink']),
      );
  Map<String, dynamic> toJson() => {
        'difficulty': difficulty,
        'level': level,
        'levelDecimal': levelDecimal,
        'levelValue': levelValue,
        'enabled': enabled,
        'levelLabel': levelLabel,
        'designer': designer,
        'noteCount': noteCount,
        'bells': bells,
        'chartLink': chartLink,
      };
}

@immutable
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.charts,
    this.titleKana,
    this.artist,
    this.genre,
    this.genreId,
    this.bpm,
    this.version,
    this.releaseTag,
    this.isNew = false,
    this.chapter,
    this.chapterId,
    this.character,
    this.characterId,
    this.enemyLevel,
    this.enemyType,
    this.dateAdded,
    this.copyright,
    this.wikiUrl,
    this.artwork,
    this.isBonus = false,
    this.aliases = const [],
  });
  final String id, title;
  final String? titleKana,
      artist,
      genre,
      genreId,
      releaseTag,
      chapter,
      chapterId,
      character,
      characterId,
      enemyType,
      dateAdded,
      copyright,
      wikiUrl,
      artwork;
  final double? bpm;
  final int? version, enemyLevel;
  final bool isNew, isBonus;
  final List<Chart> charts;
  final List<String> aliases;

  factory Song.fromJson(Map<String, dynamic> j) {
    final rawCharts = j['charts'];
    return Song(
      id: _str(j['id']) ?? '',
      title: _str(j['title']) ?? '',
      titleKana: _str(j['titleKana']),
      artist: _str(j['artist']),
      genre: _str(j['genre']),
      genreId: _str(j['genreId']),
      bpm: _doubleOrNull(j['bpm']),
      version: _intOrNull(j['version']),
      releaseTag: _str(j['releaseTag']),
      isNew: j['isNew'] == true,
      chapter: _str(j['chapter']),
      chapterId: _str(j['chapterId']),
      character: _str(j['character']),
      characterId: _str(j['characterId']),
      enemyLevel: _intOrNull(j['enemyLevel']),
      enemyType: _str(j['enemyType']),
      dateAdded: _str(j['dateAdded']),
      copyright: _str(j['copyright']),
      wikiUrl: _str(j['wikiUrl']),
      artwork: _str(j['artwork']),
      isBonus: j['isBonus'] == true,
      charts: rawCharts is List
          ? rawCharts
              .whereType<Map>()
              .map((e) => Chart.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      aliases: j['aliases'] is List
          ? (j['aliases'] as List)
              .map((e) => e is Map ? _str(e['text']) : e?.toString())
              .whereType<String>()
              .toList()
          : const [],
    );
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'titleKana': titleKana,
        'artist': artist,
        'genre': genre,
        'genreId': genreId,
        'bpm': bpm,
        'version': version,
        'releaseTag': releaseTag,
        'isNew': isNew,
        'chapter': chapter,
        'chapterId': chapterId,
        'character': character,
        'characterId': characterId,
        'enemyLevel': enemyLevel,
        'enemyType': enemyType,
        'dateAdded': dateAdded,
        'copyright': copyright,
        'wikiUrl': wikiUrl,
        'artwork': artwork,
        'isBonus': isBonus,
        'charts': charts.map((e) => e.toJson()).toList(),
        'aliases': aliases,
      };
  /// 可玩谱面（按难度升序）。
  ///
  /// 每次访问都要 `where().toList()..sort()`，被卡片 build / `topLevel` /
  /// 难度排序键反复调用。本来想用 `late final` 缓存，但这个类是 **const 构造**
  /// （测试里大量 `const Song(...)`），`late final` 与 const 构造互斥，
  /// 改成普通字段又得把 const 拆掉 —— 收益（每次几微秒）不值这个破坏面。
  /// 真要优化请先在排序键处预计算（`listGrouped` 已经是这么做的）。
  List<Chart> get playableCharts => (charts.where((c) => c.enabled).toList()
    ..sort((a, b) => a.difficulty.compareTo(b.difficulty)));
  double get topLevel =>
      playableCharts.fold(0.0, (m, c) => math.max(m, c.levelValue));
  String get displayTopLevel =>
      topLevel > 0 ? topLevel.toStringAsFixed(1) : '—';
  String displayLevel(Chart c) => c.levelValue > 0
      ? c.levelValue.toStringAsFixed(1)
      : (c.levelLabel ?? '—');
}

String? _str(dynamic x) {
  if (x == null) return null;
  final s = x.toString().trim();
  return s.isEmpty || s == '-' ? null : s;
}

/// 本家（オンゲキ 原创）角色：chara_id 0001–0017。
///
/// 0001 星咲あかり … 0017 皇城セツナ；0018 起是东方、初音、VTuber 等联动角色。
/// 角色筛选靠它把两段分开。放在领域层是为了能单测，而不是埋在 UI 里。
bool isHomeCharacterId(String? id) {
  final n = int.tryParse(id ?? '');
  return n != null && n >= 1 && n <= 17;
}

int _int(dynamic x) =>
    int.tryParse(x?.toString() ?? '') ??
    double.tryParse(x?.toString() ?? '')?.toInt() ??
    0;
int? _intOrNull(dynamic x) => x == null ? null : _int(x);
double _double(dynamic x) => double.tryParse(x?.toString() ?? '') ?? 0;
double? _doubleOrNull(dynamic x) {
  final n = double.tryParse(x?.toString() ?? '');
  return n?.isFinite == true ? n : null;
}

/// 上游数值字段的「没有」语义：空串、`-`、非数字、以及 **0** 都表示没有。
///
/// RN 版写的是 `int(x) || undefined` —— `||` 把 0 也一起吞了。照抄这个语义，
/// 否则 `enemy_lv: ''` 会变成 `enemyLevel: 0`，与随包快照（null）不一致。
int? _positiveIntOrNull(dynamic x) {
  final n = _intOrNull(x);
  return n != null && n > 0 ? n : null;
}

double? _positiveDoubleOrNull(dynamic x) {
  final n = _doubleOrNull(x);
  return n != null && n > 0 ? n : null;
}

/// 按比例兜底：上游字段改名**不会抛异常，只会让数据安静地少一块**。
///
/// 单看条数抓不到 —— `lev_mas_i` 换个名字，1112 首照样解析出 1112 首，
/// 只是每首的 `levelValue` 都变成 0，顶栏全显示 `—`、默认排序退化成按曲名。
/// 所以这里查的是「可疑行占比」，超过 [limit] 就当作格式已经变了。
void _requireShare(String what, int count, int total, double limit) {
  // 样本太少时比例没有意义（2 行里坏 1 行就是 50%）。真实上游是 1112 行，
  // 而不足 500 条的负载在仓储层已经被拒了，所以这里放过小样本。
  if (total < 20 || count <= 0) return;
  if (count / total > limit) {
    throw FormatException('上游字段疑似改名：$count/$total 行$what');
  }
}

/// 落盘曲库的格式版本。**只在「旧文件读进来会得到错的数」时才 +1。**
///
/// 2：2026-11-02 修正 `lev_*_i` 的解析（`'11.8'` 曾被当成「×10 的整数」算出 1.1）。
/// 版本 1 的文件里定数全是错的，但条数、结构都合法 —— 光看文件本身无从分辨，
/// 只能靠版本戳拒绝它，让仓储重新下载。
const datasetSchemaVersion = 2;

class Dataset {
  Dataset(this.songs, {this.meta = const {}});
  final List<Song> songs;
  final Map<String, dynamic> meta;
  factory Dataset.fromJson(dynamic json) {
    if (json is! Map || json['songs'] is! List) {
      throw const FormatException('曲库格式不正确');
    }
    return Dataset(
      (json['songs'] as List)
          .whereType<Map>()
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id.isNotEmpty && s.title.isNotEmpty)
          .toList(),
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'])
          : const {},
    );
  }
  factory Dataset.fromUpstream(dynamic input) {
    final rows = input is List
        ? input
        : input is Map && input['songs'] is List
            ? input['songs'] as List
            : null;
    if (rows == null || rows.isEmpty) {
      throw const FormatException('上游数据为空或格式不正确');
    }
    final suffixes = ['bas', 'adv', 'exc', 'mas', 'lnt'];
    final songs = <Song>[];
    final total = rows.length;
    var noLevelField = 0; // 连 lev_bas 都没有：难度字段改名就是整库命中
    var blank = 0; // id / title 为空：fromJson 会把它们丢掉，留着只会让往返校验失败
    var noPositiveLevel = 0; // 所有谱面 levelValue 都是 0：lev_*_i 漂移的指纹
    for (final value in rows) {
      if (value is! Map) continue;
      final raw = Map<String, dynamic>.from(value);
      if (!raw.containsKey('lev_bas')) {
        noLevelField++;
        continue;
      }
      final id = _str(raw['id']) ?? '';
      final title = _str(raw['title']) ?? '';
      if (id.isEmpty || title.isEmpty) {
        blank++;
        continue;
      }
      final charts = <Chart>[];
      for (var i = 0; i < suffixes.length; i++) {
        final s = suffixes[i];
        final label = _str(raw['lev_$s']);
        if (label == null) continue;
        // `lev_*_i` 是**小数形态的字符串**（'11.8'），不是「定数×10」的整数。
        // 实测上游 5560 个取值全是字符串、且每个非空值都带小数点。
        // 用 _int() 读会把 '11.8' 截成 11，再 ~/10 就成了 1.1 —— 整库定数栏
        // 都会变成 1.x（随包快照里是 11.8，所以只有走在线更新才看得出问题）。
        final parsed = _doubleOrNull(raw['lev_${s}_i']);
        final value = (parsed != null && parsed > 0) ? parsed : null;
        charts.add(
          Chart(
            difficulty: i,
            level:
                value?.floor() ?? int.tryParse(label.replaceAll('+', '')) ?? 0,
            levelDecimal:
                value == null ? 0 : ((value - value.floor()) * 10).round(),
            levelValue: value ?? 0,
            enabled: true,
            levelLabel: label,
            designer: _str(raw['lev_${s}_designer']),
            noteCount: _positiveIntOrNull(raw['lev_${s}_notes']),
            bells: _positiveIntOrNull(raw['lev_${s}_bells']),
            chartLink: _str(raw['lev_${s}_chart_link']),
          ),
        );
      }
      final added = _str(raw['date_added']);
      final iso = added != null && RegExp(r'^\d{8}$').hasMatch(added)
          ? '${added.substring(0, 4)}-${added.substring(4, 6)}-${added.substring(6)}'
          : added;
      if (!charts.any((c) => c.levelValue > 0)) noPositiveLevel++;
      songs.add(
        Song(
          id: id,
          title: title,
          titleKana: _str(raw['title_sort']),
          artist: _str(raw['artist']),
          genre: _str(raw['category']),
          genreId: _str(raw['category_id']),
          bpm: _positiveDoubleOrNull(raw['bpm']),
          releaseTag: _str(raw['version']),
          isNew: _str(raw['new']) != null,
          chapter: _str(raw['chapter']),
          chapterId: _str(raw['chap_id']),
          character: _str(raw['character']),
          characterId: _str(raw['chara_id']),
          enemyLevel: _positiveIntOrNull(raw['enemy_lv']),
          enemyType: _str(raw['enemy_type']),
          dateAdded: iso,
          copyright: _str(raw['copyright1']),
          wikiUrl: _str(raw['wikiwiki_url']),
          artwork: _str(raw['image_url']),
          isBonus: _str(raw['bonus']) != null,
          charts: charts,
        ),
      );
    }
    if (songs.isEmpty) {
      final why = noLevelField > 0
          ? '没有难度字段 lev_bas'
          : blank > 0
              ? '缺少 id 或 title'
              : '不是可识别的曲目行';
      throw FormatException('上游 $total 行$why，数据格式可能已变');
    }
    // 阈值取自 2026-11-02 对真实上游的测量（1112 行 / 4208 张谱面）：
    // id|title 空 0%、缺 lev_bas 0%、无正 levelValue 的曲目 19 首（1.71%）。
    // 都留了 10 倍以上余量 —— 真触发时说明是字段改名，不是偶尔的脏行。
    _requireShare('没有难度字段 lev_bas', noLevelField, total, .05);
    _requireShare('缺少 id 或 title', blank, total, .02);
    _requireShare('没有可用的难度值（lev_*_i）', noPositiveLevel, songs.length, .2);
    return Dataset(
      songs,
      meta: {
        'id': 'ongeki-songs',
        'label': '音击曲库',
        'origin': 'otoge-db オンゲキ',
        'version': '在线更新',
        'builtAt': DateTime.now().toIso8601String(),
      },
    );
  }
  Map<String, dynamic> toJson() => {
        // 落盘时一律写入格式版本：仓储靠它判断「这份旧文件还能不能用」。
        'meta': {...meta, 'schema': datasetSchemaVersion},
        'songs': songs.map((e) => e.toJson()).toList(),
      };
}

enum SortKey { recommended, difficulty, title, character, release, bpm }

/// 茶色面板「タブ設定」：列表按哪个字段分段（标签分组）。
///
/// 对应游戏里三组排序设置的第一组，三组互不冲突、可同时生效。
enum TabGroup { genre, all, character, release, level, title, attribute }

/// 绿色面板「タブ内 楽曲ソート」：每个段内部按哪一项排序。
enum TabSort {
  recommended,
  battleScore,
  technicalScore,
  platinumScore,
  enemyLevel,
  title,
  dateAdded,
  chapter,
}

/// 蓝色面板「ライバルスコア」：对手榜显示哪一项分数。
enum RivalScore { technical, battle, platinum }

extension TabGroupInfo on TabGroup {
  // 选项一律用游戏原文（表格「日文原名」列），不翻译：
  // 这三个下拉是在还原游戏里的ソート設定，中文名反而对不上玩家看到的东西。
  // 默认项（ジャンル）不额外加「（標準）」——那是表格里标默认的注记，
  // 和 E 列的 ★ 同一个信息，靠「排在第一位」体现即可。
  String get label => switch (this) {
        TabGroup.genre => 'ジャンル',
        TabGroup.all => '全曲',
        TabGroup.character => 'キャラクター',
        TabGroup.release => 'バージョン',
        TabGroup.level => '譜面レベル',
        TabGroup.title => '曲名',
        TabGroup.attribute => '属性',
      };

  /// 「属性」在 otoge-db 快照里没有对应字段（リズム／ファイブ／マッハ），
  /// 只能灰着 —— 界面上照表格列出来，但选不了。
  bool get available => this != TabGroup.attribute;
}

extension TabSortInfo on TabSort {
  String get label => switch (this) {
        TabSort.recommended => 'オススメ順',
        TabSort.battleScore => 'バトルスコア順',
        TabSort.technicalScore => 'テクニカルスコア順',
        TabSort.platinumScore => 'プラチナスコア順',
        TabSort.enemyLevel => '対戦相手のレベル順',
        TabSort.title => '曲名順',
        TabSort.dateAdded => '追加日順',
        TabSort.chapter => 'チャプター順',
      };

  /// 三种分数排序要玩家自己的成绩；曲库快照只有曲目元数据，没有成绩。
  bool get available => switch (this) {
        TabSort.battleScore ||
        TabSort.technicalScore ||
        TabSort.platinumScore =>
          false,
        _ => true,
      };
}

extension RivalScoreInfo on RivalScore {
  String get label => switch (this) {
        RivalScore.technical => 'テクニカルスコア',
        RivalScore.battle => 'バトルスコア',
        RivalScore.platinum => 'プラチナスコア',
      };

  /// 对手榜分数同样需要账号侧数据，这一整栏在当前快照下都不可选。
  bool get available => false;
}

/// 列表里的一段：分组标题 + 段内曲目。`label` 为空表示不显示组头（全曲）。
class SongGroup {
  const SongGroup(this.label, this.songs);
  final String label;
  final List<Song> songs;
}

/// 「按难度排序」下可同时叠加的三个条件。
///
/// 对应曲库里仅有的三种难度数据：谱面档位（BASIC→LUNATIC）、谱面等级值
/// （如 13.7）、对手等级。勾选多个时按勾选顺序依次比较，前一项相同才看
/// 后一项，互不冲突。
enum DifficultySort { rank, level, enemyLevel }

enum SortDirection { asc, desc }

class SongFilters {
  const SongFilters({
    this.genres = const {},
    this.characters = const {},
    this.releaseTags = const {},
    this.rows = const {},
  });
  final Set<String> genres, characters, releaseTags, rows;
  int get count =>
      genres.length + characters.length + releaseTags.length + rows.length;
  SongFilters copyWith({
    Set<String>? genres,
    Set<String>? characters,
    Set<String>? releaseTags,
    Set<String>? rows,
  }) =>
      SongFilters(
        genres: genres ?? this.genres,
        characters: characters ?? this.characters,
        releaseTags: releaseTags ?? this.releaseTags,
        rows: rows ?? this.rows,
      );

  /// 这条曲目是否通过全部条件。
  ///
  /// 收在这里是因为**有两个调用方**：浏览列表（[SongEngine.list]）和搜索结果
  /// （`HomeScreen` 里再筛一遍）。以前各写一份一模一样的四段判断，改一边忘一边
  /// 就会出现「浏览时筛掉了、搜出来又有」这种鬼现象。
  ///
  /// [sort] 要参与判断：`rows` 这一组按当前排序取不同字段（角色读音 / 曲名读音）。
  bool matches(Song song, SortKey sort) {
    if (genres.isNotEmpty && !genres.contains(song.genre)) return false;
    if (characters.isNotEmpty && !characters.contains(song.character)) {
      return false;
    }
    if (releaseTags.isNotEmpty && !releaseTags.contains(song.releaseTag)) {
      return false;
    }
    if (rows.isNotEmpty) {
      final row = sort == SortKey.character
          ? kanaRow(characterReading(song.character))
          : kanaRow(song.titleKana ?? song.title);
      if (!rows.contains(row)) return false;
    }
    return true;
  }

  static const empty = SongFilters();
}

const genreOrder = [
  'POPS＆ANIME',
  'niconico',
  '東方Project',
  'VARIETY',
  'チュウマイ',
  'オンゲキ',
];
const releaseOrder = [
  'ONGEKI',
  'ONGEKI Plus',
  'SUMMER',
  'SUMMER Plus',
  'RED',
  'RED Plus',
  'Re:Fresh',
  'Re:Fresh Act.2',
  'bright',
  'bright MEMORY Act.1',
  'bright MEMORY Act.2',
  'bright MEMORY Act.3',
];
const genreColors = {
  '01': 0xFFFF0066,
  '02': 0xFFFFD822,
  '03': 0xFFCF3EFF,
  '04': 0xFF00C312,
  '05': 0xFF42B6FF,
  '06': 0xFFFF7DAB,
};
const difficultyColors = [
  0xFF16FF47,
  0xFFFFBA00,
  0xFFFA0667,
  0xFFA810FF,
  0xFFF8FF2F,
];
const difficultyNames = ['BASIC', 'ADVANCED', 'EXPERT', 'MASTER', 'LUNATIC'];
const kanaRows = <String, String>{
  'あ行': 'あいうえおぁぃぅぇぉアイウエオァィゥェォヴ',
  'か行': 'かきくけこがぎぐげごカキクケコガギグゲゴ',
  'さ行': 'さしすせそざじずぜぞサシスセソザジズゼゾ',
  'た行': 'たちつてとだぢづでどっタチツテトダヂヅデドッ',
  'な行': 'なにぬねのナニヌネノ',
  'は行': 'はひふへほばびぶべぼぱぴぷぺぽハヒフヘホバビブベボパピプペポ',
  'ま行': 'まみむめもマミムメモ',
  'や行': 'やゆよゃゅょヤユヨャュョ',
  'ら行': 'らりるれろラリルレロ',
  'わ行': 'わをんゎワヲンヮ',
};
const surnameKana = <String, String>{
  '星咲': 'ほしざき',
  '藤沢': 'ふじさわ',
  '三角': 'みすみ',
  '高瀬': 'たかせ',
  '結城': 'ゆうき',
  '藍原': 'あいはら',
  '桜井': 'さくらい',
  '早乙女': 'さおとめ',
  '井之原': 'いのはら',
  '柏木': 'かしわぎ',
  '九條': 'くじょう',
  '逢坂': 'おうさか',
  '珠洲島': 'すずしま',
  '日向': 'ひなた',
  '東雲': 'しののめ',
  '皇城': 'すめらぎ',
  '草津': 'くさつ',
  '明坂': 'あけさか',
  '式宮': 'しきみや',
  '双挽': 'そうびき',
  '鳳': 'おおとり',
  '千寿': 'せんじゅ',
  '連尺野': 'れんしゃくの',
  '水無月': 'みなづき',
  '日野下': 'ひのした',
  '和泉': 'いずみ',
  '陸八魔': 'りくはちま',
  '聖園': 'みその',
  '鳴瀬': 'なるせ',
  '博麗': 'はくれい',
  '霧雨': 'きりさめ',
  '紅': 'くれない',
  '十六夜': 'いざよい',
  '射命丸': 'しゃめいまる',
  '八雲': 'やくも',
  '魂魄': 'こんぱく',
  '西行寺': 'さいぎょうじ',
  '因幡': 'いなば',
  '八意': 'やち',
  '蓬莱山': 'ほうらいさん',
  '藤原': 'ふじわら',
  '古明地': 'こめいじ',
  '東風谷': 'こちや',
  '洩矢': 'もりや',
  '風見': 'かざみ',
  '涼宮': 'すずみや',
  '長門': 'ながと',
  '朝比奈': 'あさひな',
  '初音ミク': 'はつねみく',
  '鏡音リン': 'かがみねりん',
  '巡音ルカ': 'めぐりねるか',
  '重音テト': 'かさねてと',
  '開かれた窓のセカイの初音ミク': 'ひらかれたまどのせかいのはつねみく',
  '閉ざされた窓のセカイの初音ミク': 'とざされたまどのせかいのはつねみく',
  '光': 'ひかり',
  '橙': 'ちぇん',
  '名取さな': 'なとりさな',
  '鈴仙・優曇華院・イナバ': 'れいせんうどんげいんいなば',
  '周防パトラ': 'すおうぱとら',
  '獅子神レオナ': 'ししがみれおな',
  '長瀬有花': 'ながせゆうか',
  '魔法少女リリカ': 'まほうしょうじょりりか',
  '静香': 'しずか',
  '稀羽すう': 'まれはすう',
  '月紫アリア': 'つきしあんありあ',
  '柑原あさひ': 'かんばらあさひ',
  '足立レイ': 'あだちれい',
  '桜羽エマ': 'さくらばえま',
};
String characterReading(String? name) {
  if (name == null) return '';
  final compact = name.trim();
  if (surnameKana.containsKey(compact)) return surnameKana[compact]!;
  final first = compact.split(' ').first;
  return surnameKana[first] ?? first;
}

String kanaRow(String? value) {
  if (value == null || value.isEmpty) return 'その他';
  final head = value[0];
  for (final e in kanaRows.entries) {
    if (e.value.contains(head)) return e.key;
  }
  final u = head.toUpperCase();
  if (RegExp(r'^[A-G]$').hasMatch(u)) return 'A~G';
  if (RegExp(r'^[H-N]$').hasMatch(u)) return 'H~N';
  if (RegExp(r'^[O-U]$').hasMatch(u)) return 'O~U';
  if (RegExp(r'^[V-Z]$').hasMatch(u)) return 'V~Z';
  return 'その他';
}

int kanaRank(String row) {
  final k = kanaRows.keys.toList();
  final i = k.indexOf(row);
  if (i >= 0) return i;
  final latin = ['A~G', 'H~N', 'O~U', 'V~Z'].indexOf(row);
  return latin >= 0 ? k.length + latin : 999;
}

/// 半角片假名 0xFF71..0xFF9D 与全角 ア..ン 一一对应，共 45 个。
/// 全角块里夹着小書き（ァ=0x30A1、ィ=0x30A3…），不能靠固定偏移换算。
const _halfKanaBlock = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

/// 半角块里顺序特殊的标点与小書き（含长音符 ｰ）。
const _halfKanaSpecials = <int, String>{
  0xFF61: '。',
  0xFF62: '「',
  0xFF63: '」',
  0xFF64: '、',
  0xFF65: '・',
  0xFF66: 'ヲ',
  0xFF67: 'ァ',
  0xFF68: 'ィ',
  0xFF69: 'ゥ',
  0xFF6A: 'ェ',
  0xFF6B: 'ォ',
  0xFF6C: 'ャ',
  0xFF6D: 'ュ',
  0xFF6E: 'ョ',
  0xFF6F: 'ッ',
  0xFF70: 'ー',
};

const _voicedKana = <String, String>{
  'カ': 'ガ',
  'キ': 'ギ',
  'ク': 'グ',
  'ケ': 'ゲ',
  'コ': 'ゴ',
  'サ': 'ザ',
  'シ': 'ジ',
  'ス': 'ズ',
  'セ': 'ゼ',
  'ソ': 'ゾ',
  'タ': 'ダ',
  'チ': 'ヂ',
  'ツ': 'ヅ',
  'テ': 'デ',
  'ト': 'ド',
  'ハ': 'バ',
  'ヒ': 'ビ',
  'フ': 'ブ',
  'ヘ': 'ベ',
  'ホ': 'ボ',
  'ウ': 'ヴ',
};
const _semiVoicedKana = <String, String>{
  'ハ': 'パ',
  'ヒ': 'ピ',
  'フ': 'プ',
  'ヘ': 'ペ',
  'ホ': 'ポ',
};
const _romanNumerals = [
  'I',
  'II',
  'III',
  'IV',
  'V',
  'VI',
  'VII',
  'VIII',
  'IX',
  'X',
  'XI',
  'XII'
];

/// Dart 核心库没有 NFKC，这里补上检索真正会遇到的那部分兼容字符：
/// 全角 ASCII、半角片假名（含浊点合成）、圈号数字、罗马数字。
/// 不做全量 NFKC 表——合字（㍿ 等）与带圈假名在曲名里不会出现。
String _nfkcFold(String input) {
  final out = <String>[];
  for (final rune in input.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.add(String.fromCharCode(rune - 0xFEE0));
      continue;
    }
    if (rune >= 0xFF71 && rune <= 0xFF9D) {
      out.add(_halfKanaBlock[rune - 0xFF71]);
      continue;
    }
    final special = _halfKanaSpecials[rune];
    if (special != null) {
      out.add(special);
      continue;
    }
    // ﾞ/ﾟ 要与前一个假名合成浊音，否则「ｶﾞ」和「ガ」会被当成两个词。
    if ((rune == 0xFF9E || rune == 0xFF9F) && out.isNotEmpty) {
      final prev = out.removeLast();
      final table = rune == 0xFF9E ? _voicedKana : _semiVoicedKana;
      out.add(table[prev] ?? '$prev${rune == 0xFF9E ? '゛' : '゜'}');
      continue;
    }
    if (rune >= 0x2460 && rune <= 0x2473) {
      out.add('${rune - 0x245F}');
      continue;
    }
    if (rune >= 0x2160 && rune <= 0x216B) {
      out.add(_romanNumerals[rune - 0x2160]);
      continue;
    }
    out.add(String.fromCharCode(rune));
  }
  return out.join();
}

String normalize(String input) {
  final s = _nfkcFold(input.trim()).toLowerCase();
  const kata = 0x30A1;
  final b = StringBuffer();
  for (final rune in s.runes) {
    final foldedRune = rune >= kata && rune <= 0x30F6 ? rune - 0x60 : rune;
    final ch = String.fromCharCode(foldedRune);
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch)) b.write(ch);
  }
  // Dart 的 replaceAll 不解析反向引用（`\1` 会被当成字面量写进结果），
  // 只有 replaceAllMapped 才能真的把 3 个以上重复压成 2 个。
  return b.toString().replaceAllMapped(
        RegExp(r'(.)\1{2,}'),
        (match) => '${match[1]}${match[1]}',
      );
}

/// 排在汉字**之前**的字符主权重序：符号、数字、拉丁，以及随包曲库里出现过的
/// 所有「排在汉字之前」的非假名非汉字字符（`、。“”×∀` 等）。越靠前越前。
///
/// **这张表是从 ICU 反推出来的，不是手排的**：用 V8/ICU 对每个字符单独跑
/// `localeCompare(..., 'ja')` 求序，再把结果固化成常量（`tool/gen_collation_table.mjs`
/// 会直接改写这里）。手写权重表实测比码位更差（79.4% vs 81.3%）。
/// 表外字符（假名、汉字等）走后面的分支，落在本表所有字符之后。
const _collationOrder =
    '\u0020\u3000_-\uff0d\u301c\u30fb,\u3001;:\uff1a!\uff01?\uff1f.\u2026\u3002\'\u2019"\u201c\u201d(\uff08)\uff09[]{}\u300a\u300b@\uff20*\uff0a/\\&\uff06#%\u2020`^\u2192\u21d2\u2200+\u00d7<=>|~\uff5e\u221e\u25c6\u2605\u2606\u2661\u2665\u266a\u3005\u30fc\$0123456789\u2468aA\u00c4bBcCdDeE\u00e9\u00c9fFgG\uff27hHiI\u2162jJkKlLmMnNoO\uff2f\u00f6\u00f8pPqQr\uff52RsS\uff33t\uff54TuU\u00fcvVwWxXy\uff59Y\u00fdzZ';

/// 权重表 → 字符主权重序。额外把每个字符的大小写变体也映射到同一序：
/// ICU 的主权重不分大小写（`Λ` 与 `λ` 同级），而 [titleSortKey] 会先做
/// `toLowerCase()` —— 表里只有 `Λ`，查 `λ` 就会落空掉进码位兜底。
final Map<int, int> _collationRanks = {
  for (final (index, rune) in _collationOrder.runes.indexed) ...{
    rune: index,
    String.fromCharCode(rune).toLowerCase().runes.first: index,
    String.fromCharCode(rune).toUpperCase().runes.first: index,
  },
};

/// 排在汉字**之后**的字母表字符（希腊、西里尔等）。
///
/// 实测 ICU：`∀ < 亜 < α < Я` —— 符号在汉字前，但别的字母表脚本在汉字后。
/// 混进 [_collationOrder] 会让 `Λlteration` 排到所有汉字前面。
/// 由 tool/gen_collation_table.mjs 生成，不要手改。
const _collationAfterHan = '\u03b1\u03ac\u03b3\u03b9\u039b\u03bc\u03c9\u042f';

/// [_collationAfterHan] → 主权重序，含大小写变体（ICU 主权重不分大小写）。
final Map<int, int> _afterHanRanks = {
  for (final (index, rune) in _collationAfterHan.runes.indexed) ...{
    rune: index,
    String.fromCharCode(rune).toLowerCase().runes.first: index,
    String.fromCharCode(rune).toUpperCase().runes.first: index,
  },
};

/// 五十音基准序（清音）。浊点、半浊点、小写、平/片假名都折到这一序上。
const _kanaBase = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';

final Map<int, int> _kanaBaseIndex = {
  for (final (index, rune) in _kanaBase.runes.indexed) rune: index,
};

/// 与 [_kanaBase] 逐位对齐的「元音假名」表：ア→ア、カ→ア、シ→イ、ヤ→ア、
/// ユ→ウ、ヨ→オ、ワ→ア、ヲ→オ、ン→ン。
///
/// JIS X 4061 里长音符 `ー` 不占独立权重，而是**继承前一个假名的元音**
/// （`カー` ≈ `カア`、`コー` ≈ `コオ`）。给 `ー` 一个固定符号权重会让
/// `シークレット` 排到 `シアワセ` 前面，实测 1044 个标题里有 3 对因此颠倒。
const _kanaVowels = 'アイウエオアイウエオアイウエオアイウエオアイウエオアイウエオアイウエオ'
    'アウオ'
    'アイウエオ'
    'アオン';

/// [_kanaBase] 的下标 → 元音在基准序里的下标。
final List<int> _kanaVowelIndex = [
  for (final rune in _kanaVowels.runes) _kanaBaseIndex[rune]!,
];

/// 浊点/半浊点假名 → (基准假名, 级别)。级别：0 清音、1 浊音、2 半浊音。
/// 注意与上面按「清音→浊音」折叠半角假名用的 `_voicedKana` 方向相反。
const Map<String, (String, int)> _kanaVoicing = {
  'ガ': ('カ', 1), 'ギ': ('キ', 1), 'グ': ('ク', 1), 'ゲ': ('ケ', 1), 'ゴ': ('コ', 1), //
  'ザ': ('サ', 1), 'ジ': ('シ', 1), 'ズ': ('ス', 1), 'ゼ': ('セ', 1), 'ゾ': ('ソ', 1), //
  'ダ': ('タ', 1), 'ヂ': ('チ', 1), 'ヅ': ('ツ', 1), 'デ': ('テ', 1), 'ド': ('ト', 1), //
  'バ': ('ハ', 1), 'ビ': ('ヒ', 1), 'ブ': ('フ', 1), 'ベ': ('ヘ', 1), 'ボ': ('ホ', 1), //
  'パ': ('ハ', 2), 'ピ': ('ヒ', 2), 'プ': ('フ', 2), 'ペ': ('ヘ', 2), 'ポ': ('ホ', 2), //
  'ヴ': ('ウ', 1), 'ヷ': ('ワ', 1), 'ヸ': ('イ', 1), 'ヹ': ('エ', 1), 'ヺ': ('ヲ', 1), //
};

/// 小写假名 → 基准假名。小写假名排在对应大写字之后（第三层级）。
const Map<String, String> _smallKana = {
  'ァ': 'ア', 'ィ': 'イ', 'ゥ': 'ウ', 'ェ': 'エ', 'ォ': 'オ', //
  'ヵ': 'カ', 'ヶ': 'ケ', 'ッ': 'ツ', 'ャ': 'ヤ', 'ュ': 'ユ', 'ョ': 'ヨ', //
  'ヮ': 'ワ', 'ヰ': 'イ', 'ヱ': 'エ', //
};

/// 拉丁重音字母 → 基字母。ICU 里 `ä` 的主权重等于 `a`，变音符只落在第二层，
/// 所以折到基字母、把 accents 那一层标 1 就够还原次序（`Äventyr` < `Azucar`
/// 靠的是第二层之前的 e<z，不是 Ä 本身）。
///
/// 只收小写：调用方先做 `toLowerCase()`。ð/ø/ł/đ 严格说是「基字母 + 加笔」，
/// ICU 同样按第二层处理，折到基字母与之一致。
const Map<String, String> _latinBases = {
  'a': 'àáâãäåāăąǎȧ',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęěȩ',
  'g': 'ğĝġģ',
  'h': 'ĥħ',
  'i': 'ìíîïīĭįıǐ',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľłŀ',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏőǒȫ',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  't': 'ţťŧț',
  'u': 'ùúûüūŭůűųǔȕ',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final Map<int, int> _latinFold = {
  for (final entry in _latinBases.entries)
    for (final rune in entry.value.runes) rune: entry.key.runes.first,
};

/// 一个字符的三层权重：主权重 / 浊点级别 / 小写级别。
///
/// 主权重分层（互不重叠，保证跨类次序稳定）：
/// * `0–199`   符号 / 数字 / 拉丁（[_collationOrder]，ICU 反推）
/// * `200–245` 假名（五十音基准序，浊点走第二层、小写走第三层）
/// * `400–879` 汉字（[hanCollationOrder]，ICU 反推）
/// * `900–919` 汉字之后的字母表脚本（[_collationAfterHan]，希腊/西里尔等）
/// * `1000+rune` 表外字符，退回码位 —— 落在所有表内字符之后
(int, int, int) _charWeights(int rune) {
  final rank = _collationRanks[rune];
  if (rank != null) return (rank, 0, 0);
  if (rune >= 0x30A1 && rune <= 0x30FF) {
    final ch = String.fromCharCode(rune);
    final voiced = _kanaVoicing[ch];
    var base = voiced?.$1 ?? ch;
    final dakuten = voiced?.$2 ?? 0;
    var small = 1;
    if (voiced == null) {
      final folded = _smallKana[ch];
      if (folded != null) {
        base = folded;
        small = 0;
      }
    }
    final index = _kanaBaseIndex[base.runes.first];
    // 200+ 保证所有假名排在权重表内的符号/数字/拉丁之后、汉字之前。
    return index == null ? (1000 + rune, 0, 0) : (200 + index, dakuten, small);
  }
  // 汉字：ICU 的 ja 主权重来自 CLDR 的 unihan 数据（大致按读音序），
  // 与码位序大量互逆（ICU 亜<一、日>月、火<月）。查表还原 ICU 次序。
  final hanRank = hanCollationRanks[rune];
  if (hanRank != null) return (400 + hanRank, 0, 0);
  // 希腊/西里尔等在 ICU 里排在汉字之后（∀ < 亜 < α < Я）。
  final tailRank = _afterHanRanks[rune];
  if (tailRank != null) return (900 + tailRank, 0, 0);
  return (1000 + rune, 0, 0);
}

/// 日文排序键：三层权重序列，配合 [compareSortKeys] 使用。
///
/// ICU 的排序是**分层比较**的：先比整串主权重，相等再比浊点这一层，最后比小写。
/// 不能把三层压成一个序列按字符比 —— 那样「A」和「ab」的先后就会反过来。
class CollationKey {
  CollationKey(this.primary, this.secondary, this.tertiary);
  final List<int> primary;
  final List<int> secondary;
  final List<int> tertiary;
}

/// 日文排序键。[compareSortKeys] 的比较对象。
///
/// 不能直接拿 `compareTo` 排：ICU 的 `ja` 排序里**平假名与片假名主权重相同**
/// （`あ` 与 `ア` 同级），而 UTF-16 码位把整块平假名（U+3041–3096）排在所有
/// 片假名（U+30A1–30FF）之前 —— 所有全平假名标题会挤到全片假名标题前面。
/// 拉丁字母同理，主权重不分大小写。
///
/// 汉字按 [hanCollationOrder] 还原 ICU 的主权重序（覆盖随包曲库出现过的字，
/// 见表内文档）；表外汉字退回码位比较。
CollationKey titleSortKey(String input) {
  final primary = <int>[];
  final secondary = <int>[];
  final tertiary = <int>[];
  // 上一个假名的元音（基准序下标），-1 表示当前字符不继承（如 ー 出现在句首）。
  var lastVowel = -1;
  // 先做兼容字符折叠：全角 Ａ/！/： 在 ICU 里与半角完全等价
  // （localeCompare('Ｇ','G','ja') === 0），Ⅲ / ⑨ 也折成 III / 9。
  // 不折的话它们会掉进 1000+rune 兜底，排到所有汉字后面。
  for (final rune in _nfkcFold(input).runes) {
    // 平假名 → 片假名：ICU 里两种假名同一主权重。
    final folded = rune >= 0x3041 && rune <= 0x3096 ? rune + 0x60 : rune;
    // 长音符继承前一个假名的元音。secondary 用 -1 让「カー」排在「カア」之前
    // （ICU：localeCompare('カー','カア','ja') < 0）。
    if (folded == 0x30FC && lastVowel >= 0) {
      primary.add(200 + lastVowel);
      secondary.add(-1);
      tertiary.add(0);
      continue;
    }
    var lower = folded;
    var accent = 0;
    if (folded >= 0x41 && folded <= 0x5A) {
      lower = folded + 0x20; // 拉丁转小写：主权重不分大小写
    } else if (folded > 0x7E) {
      final text = String.fromCharCode(folded).toLowerCase();
      if (text.isNotEmpty && text.runes.first != folded) {
        lower = text.runes.first;
      }
    }
    final base = _latinFold[lower];
    if (base != null) {
      lower = base;
      accent = 1;
    }
    final (p, s, t) = _charWeights(lower);
    primary.add(p);
    secondary.add(s != 0 ? s : accent);
    tertiary.add(t);
    // 200–245 是假名带的主权重区间，反查下标供下一个 `ー` 继承元音。
    lastVowel = p >= 200 && p <= 245 ? _kanaVowelIndex[p - 200] : -1;
  }
  return CollationKey(primary, secondary, tertiary);
}

int _compareLevels(List<int> a, List<int> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// 按层级比较（主权重 → 浊点 → 小写），与 ICU 的比较顺序一致。
int compareSortKeys(CollationKey a, CollationKey b) {
  final primary = _compareLevels(a.primary, b.primary);
  if (primary != 0) return primary;
  final secondary = _compareLevels(a.secondary, b.secondary);
  if (secondary != 0) return secondary;
  return _compareLevels(a.tertiary, b.tertiary);
}

String foldKana(String s) {
  const from = 'がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽぁぃぅぇぉゃゅょっゎゔ';
  const to = 'かきくけこさしすせそたちつてとはひふへほはひふへほあいうえおやゆよつわう';
  final out = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    if (ch == 'ー') continue;
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

int editDistance(String a, String b, [int max = 2]) {
  final x = a.runes.toList(), y = b.runes.toList();
  if ((x.length - y.length).abs() > max) return max + 1;
  var prev2 = List<int>.generate(y.length + 1, (i) => i),
      prev = List<int>.generate(y.length + 1, (i) => i),
      cur = List<int>.filled(y.length + 1, 0);
  for (var i = 1; i <= x.length; i++) {
    cur[0] = i;
    var min = cur[0];
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      var v = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 && j > 1 && x[i - 1] == y[j - 2] && x[i - 2] == y[j - 1]) {
        v = math.min(v, prev2[j - 2] + 1);
      }
      cur[j] = v;
      min = math.min(min, v);
    }
    if (min > max) return max + 1;
    final old = prev2;
    prev2 = prev;
    prev = cur;
    cur = old;
  }
  return prev[y.length] > max ? max + 1 : prev[y.length];
}

class SongHit {
  const SongHit(this.song, this.reason, this.score);
  final Song song;
  final String? reason;
  final double score;
}

class _SearchTerm {
  const _SearchTerm(this.song, this.text, this.key, this.field, this.weight);
  final Song song;
  final String text, key, field;
  final double weight;
}

class SongEngine {
  SongEngine(List<Song> songs)
      : songs = songs,
        _terms = [
          for (final song in songs) ...[
            if (normalize(song.title).isNotEmpty)
              _SearchTerm(song, song.title, normalize(song.title), '曲名', 1),
            if (song.titleKana != null && normalize(song.titleKana!).isNotEmpty)
              _SearchTerm(
                song,
                song.titleKana!,
                normalize(song.titleKana!),
                '读音',
                .9,
              ),
            for (final alias in song.aliases)
              if (normalize(alias).isNotEmpty)
                _SearchTerm(song, alias, normalize(alias), '别名', 1),
          ],
        ];
  final List<Song> songs;
  final List<_SearchTerm> _terms;

  List<SongHit> search(String raw, {int limit = 60}) {
    final query = raw.trim();
    if (query.isEmpty || limit <= 0) return const [];
    final numeric = _nfkcFold(query).trim();
    if (RegExp(r'^\d+$').hasMatch(numeric)) {
      final stripped = numeric.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final variants = {numeric, numeric.padLeft(6, '0'), stripped};
      final ids = songs.where((song) => variants.contains(song.id)).toList();
      if (ids.isNotEmpty) {
        return ids
            .map((song) => SongHit(song, 'ID $query', 1000))
            .take(limit)
            .toList();
      }
    }

    final key = normalize(query);
    if (key.isEmpty) return const [];
    List<SongHit> collect(String needle, int stage) {
      final best = <String, SongHit>{};
      for (final term in _terms) {
        final matches = switch (stage) {
          0 => term.key == needle,
          1 => term.key.startsWith(needle),
          2 => term.key.contains(needle),
          _ => false,
        };
        if (!matches) continue;
        final base = switch (stage) {
          0 => (term.field == '别名'
              ? 900.0
              : term.field == '曲名'
                  ? 880.0
                  : 860.0),
          1 => (term.field == '别名'
              ? 500.0
              : term.field == '曲名'
                  ? 480.0
                  : 440.0),
          _ => (term.field == '别名'
              ? 200.0
              : term.field == '曲名'
                  ? 190.0
                  : 170.0),
        };
        final coverage = math
            .min(1.0, needle.length / math.max(1, term.key.length))
            .toDouble();
        final score = stage == 0
            ? base * term.weight
            : base * term.weight * (.7 + .3 * coverage);
        final reason = stage == 0 && term.field == '曲名'
            ? null
            : '${term.field}「${term.text}」';
        final hit = SongHit(term.song, reason, score);
        final old = best[term.song.id];
        if (old == null || hit.score > old.score) best[term.song.id] = hit;
      }
      final result = best.values.toList();
      result.sort(_compareHits);
      return result;
    }

    for (var stage = 0; stage < 3; stage++) {
      final hits = collect(key, stage);
      if (hits.isNotEmpty) return hits.take(limit).toList();
    }

    final folded = foldKana(key);
    if (folded != key) {
      List<SongHit> collectFolded(int stage) {
        final best = <String, SongHit>{};
        for (final term in _terms.where((item) => item.field == '读音')) {
          final termKey = foldKana(term.key);
          final matches = switch (stage) {
            0 => termKey == folded,
            1 => termKey.startsWith(folded),
            2 => termKey.contains(folded),
            _ => false,
          };
          if (!matches) continue;
          final base = switch (stage) {
            0 => 860.0,
            1 => 440.0,
            _ => 170.0,
          };
          final coverage = math
              .min(1.0, folded.length / math.max(1, termKey.length))
              .toDouble();
          final score =
              stage == 0 ? base * .9 : base * .9 * (.7 + .3 * coverage);
          final hit = SongHit(term.song, '读音「${term.text}」', score);
          final old = best[term.song.id];
          if (old == null || hit.score > old.score) best[term.song.id] = hit;
        }
        final result = best.values.toList()..sort(_compareHits);
        return result;
      }

      for (var stage = 0; stage < 3; stage++) {
        final hits = collectFolded(stage);
        if (hits.isNotEmpty) return hits.take(limit).toList();
      }
    }

    if (key.runes.length < 3) return const [];
    var bestDistance = 3;
    final fuzzy = <String, SongHit>{};
    for (final term in _terms) {
      final distance = editDistance(key, term.key, 2);
      if (distance > 2) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        fuzzy.clear();
      }
      if (distance == bestDistance) {
        final coverage =
            math.min(1.0, key.length / math.max(1, term.key.length)).toDouble();
        final hit = SongHit(
          term.song,
          '模糊匹配 · 差 $distance 个字符',
          120 * term.weight * (.7 + .3 * coverage) - distance * 25,
        );
        final old = fuzzy[term.song.id];
        if (old == null || hit.score > old.score) fuzzy[term.song.id] = hit;
      }
    }
    final result = fuzzy.values.toList()..sort(_compareHits);
    return result.take(limit).toList();
  }

  static int _compareHits(SongHit a, SongHit b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final length = a.song.title.length.compareTo(b.song.title.length);
    if (length != 0) return length;
    final version = (b.song.version ?? 0).compareTo(a.song.version ?? 0);
    return version != 0 ? version : a.song.id.compareTo(b.song.id);
  }

  List<Song> list({
    SortKey sort = SortKey.recommended,
    SortDirection direction = SortDirection.asc,
    SongFilters filter = SongFilters.empty,
    List<DifficultySort> difficultySorts = const [],
  }) {
    final rows = songs.where((s) => filter.matches(s, sort)).toList();

    // 排序键先算一遍：`cmp` 里每次比较都重建权重序列会把排序变成 O(n log n) 次
    // 建键，1112 首标题在真机上能感觉到掉帧。
    final titleKeys = <String, CollationKey>{
      for (final s in rows) s.id: titleSortKey(s.title),
    };
    final characterKeys = <String, CollationKey>{
      for (final s in rows) s.id: titleSortKey(s.character ?? ''),
    };

    // 难度排序的两个派生键也预计算：`playableCharts` 每次访问都会重建并排序
    // 列表，放进比较函数里就是 O(n log n) 次重建，1112 首会明显掉帧。
    final rankKeys = <String, int>{};
    final enemyKeys = <String, int>{};
    final levelKeys = <String, double>{};
    if (sort == SortKey.difficulty) {
      for (final s in rows) {
        final charts = s.playableCharts;
        rankKeys[s.id] = charts.isEmpty ? -1 : charts.last.difficulty;
        enemyKeys[s.id] = s.enemyLevel ?? -1;
        levelKeys[s.id] = s.topLevel;
      }
    }

    int byTitle(Song a, Song b) {
      final title = compareSortKeys(titleKeys[a.id]!, titleKeys[b.id]!);
      return title != 0 ? title : a.id.compareTo(b.id);
    }

    int directed(int comparison) =>
        direction == SortDirection.desc ? -comparison : comparison;

    int cmp(Song a, Song b) {
      switch (sort) {
        case SortKey.recommended:
          final level = b.topLevel.compareTo(a.topLevel);
          return level != 0 ? level : byTitle(a, b);
        case SortKey.difficulty:
          // 一个都没勾时退回「档位 › 谱面等级」，和界面默认一致。
          final order = difficultySorts.isEmpty
              ? const <DifficultySort>[
                  DifficultySort.rank,
                  DifficultySort.level,
                ]
              : difficultySorts;
          for (final key in order) {
            final c = switch (key) {
              DifficultySort.rank => rankKeys[a.id]!.compareTo(rankKeys[b.id]!),
              DifficultySort.level =>
                levelKeys[a.id]!.compareTo(levelKeys[b.id]!),
              DifficultySort.enemyLevel =>
                enemyKeys[a.id]!.compareTo(enemyKeys[b.id]!),
            };
            if (c != 0) return directed(c);
          }
          return byTitle(a, b);
        case SortKey.title:
          return directed(byTitle(a, b));
        case SortKey.character:
          final hasA = a.characterId != null && a.characterId!.isNotEmpty;
          final hasB = b.characterId != null && b.characterId!.isNotEmpty;
          if (hasA != hasB) return hasA ? -1 : 1;
          if (!hasA) return byTitle(a, b);
          var c = (int.tryParse(a.characterId!) ?? 999999).compareTo(
            int.tryParse(b.characterId!) ?? 999999,
          );
          if (c == 0) {
            c = compareSortKeys(characterKeys[a.id]!, characterKeys[b.id]!);
          }
          if (c == 0) c = byTitle(a, b);
          return directed(c);
        case SortKey.release:
          final hasA = a.releaseTag != null && a.releaseTag!.isNotEmpty;
          final hasB = b.releaseTag != null && b.releaseTag!.isNotEmpty;
          if (hasA != hasB) return hasA ? -1 : 1;
          if (!hasA) return byTitle(a, b);
          final ai = releaseOrder.indexOf(a.releaseTag!);
          final bi = releaseOrder.indexOf(b.releaseTag!);
          var c = (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
          if (c == 0) c = a.releaseTag!.compareTo(b.releaseTag!);
          if (c == 0) c = byTitle(a, b);
          return directed(c);
        case SortKey.bpm:
          final av = a.bpm;
          final bv = b.bpm;
          final hasA = av != null && av.isFinite && av > 0;
          final hasB = bv != null && bv.isFinite && bv > 0;
          if (hasA != hasB) return hasA ? -1 : 1;
          if (!hasA) return byTitle(a, b);
          final c = av.compareTo(bv!);
          return directed(c != 0 ? c : byTitle(a, b));
      }
    }

    rows.sort(cmp);
    return rows;
  }

  /// 按「标签分组 → 段内排序」出列表，对应游戏里三组设置的前两组。
  ///
  /// 与 [list] 的分工：这里先按 [group] 把曲目切成若干段（列表里画组头），
  /// 每段内部再按 [sort] 排。方向内置不再交给用户：推荐序、对手等级、追加
  /// 日期都是「大/新在前」，曲名、章节按五十音/编号升序。
  ///
  /// [predicate] 是额外的过滤（界面上按等级、难度筛的那一层）；分组要在过滤
  /// 之后做，否则筛掉整段后仍会留下一个空组头。
  List<SongGroup> listGrouped({
    TabGroup group = TabGroup.genre,
    TabSort sort = TabSort.recommended,
    SongFilters filter = SongFilters.empty,
    bool Function(Song)? predicate,
  }) {
    // 灰着的项被传进来时退回默认：宁可排成默认序，也不要出一条乱序空列表。
    if (!group.available) group = TabGroup.genre;
    if (!sort.available) sort = TabSort.recommended;

    final rows = songs.where((s) => filter.matches(s, SortKey.title)).toList();
    if (predicate != null) rows.removeWhere((s) => !predicate(s));

    // 兜底键用**读音**而不是标题原文：网页端 byTitle 一直是 `s.k || s.t`，
    // 这里跟着用 titleKana，两端的「同分谁在前」才对得上。标题里夹着
    // 「・」「Ä」「#」这类符号时，拿原文比会和读音排出完全不同的顺序
    // （アイシング・ドリーム vs 愛して、#狂った民族 vs カ行假名）。
    final titleKeys = <String, CollationKey>{
      for (final s in rows)
        s.id: titleSortKey(
            (s.titleKana != null && s.titleKana!.isNotEmpty)
                ? s.titleKana!
                : s.title),
    };
    // 派生键预计算：`playableCharts` 每次访问都会重建并排序，塞进比较函数
    // 就是 O(n log n) 次重建。
    final rankKeys = <String, int>{};
    final levelKeys = <String, double>{};
    final enemyKeys = <String, int>{};
    if (sort == TabSort.recommended || sort == TabSort.enemyLevel) {
      for (final s in rows) {
        final charts = s.playableCharts;
        rankKeys[s.id] = charts.isEmpty ? -1 : charts.last.difficulty;
        levelKeys[s.id] = s.topLevel;
        enemyKeys[s.id] = s.enemyLevel ?? -1;
      }
    }

    int byTitle(Song a, Song b) {
      final title = compareSortKeys(titleKeys[a.id]!, titleKeys[b.id]!);
      return title != 0 ? title : a.id.compareTo(b.id);
    }

    String groupLabelOf(Song s) => switch (group) {
          TabGroup.genre => s.genre ?? '其他',
          TabGroup.all => '',
          TabGroup.character => s.character ?? '未知',
          TabGroup.release => s.releaseTag ?? '未知',
          TabGroup.level =>
            s.topLevel > 0 ? s.topLevel.floor().toString() : '—',
          TabGroup.title => kanaRow(s.titleKana ?? s.title),
          TabGroup.attribute => '',
        };

    /// 组在列表里的先后。谱面等级要「高级在前」，所以取负值。
    int groupRankOf(Song s) => switch (group) {
          TabGroup.genre => _rankIn(genreOrder, s.genre),
          TabGroup.all => 0,
          TabGroup.character => int.tryParse(s.characterId ?? '') ?? 999999,
          TabGroup.release => _rankIn(releaseOrder, s.releaseTag),
          TabGroup.level => -(s.topLevel * 10).round(),
          TabGroup.title => kanaRank(kanaRow(s.titleKana ?? s.title)),
          TabGroup.attribute => 0,
        };

    int within(Song a, Song b) {
      switch (sort) {
        case TabSort.recommended:
          final rank = rankKeys[b.id]!.compareTo(rankKeys[a.id]!);
          if (rank != 0) return rank;
          final level = levelKeys[b.id]!.compareTo(levelKeys[a.id]!);
          return level != 0 ? level : byTitle(a, b);
        case TabSort.enemyLevel:
          final enemy = enemyKeys[b.id]!.compareTo(enemyKeys[a.id]!);
          return enemy != 0 ? enemy : byTitle(a, b);
        case TabSort.title:
          return byTitle(a, b);
        case TabSort.dateAdded:
          // dateAdded 是 ISO 日期串，字典序即时间序；新的在前。
          final date = (b.dateAdded ?? '').compareTo(a.dateAdded ?? '');
          return date != 0 ? date : byTitle(a, b);
        case TabSort.chapter:
          final chapter = (a.chapterId ?? '').compareTo(b.chapterId ?? '');
          return chapter != 0 ? chapter : byTitle(a, b);
        default:
          // 三种分数排序没有数据，见 [TabSortInfo.available]，这里只是兜底。
          return byTitle(a, b);
      }
    }

    // 组标签预计算：`groupLabelOf` 里 `kanaRow` 要遍历假名行表，`topLevel`
    // 每次访问都会重建 `playableCharts`。塞进比较函数就是 O(n log n) 次重建
    // （谱面等级 / 曲名分组实测 ~18ms，分类分组 ~5ms）。每首只算一次，比较器
    // 纯查表。
    final labels = <String, String>{
      for (final s in rows) s.id: groupLabelOf(s),
    };
    final groupRanks = <String, int>{};
    if (group != TabGroup.all && group != TabGroup.attribute) {
      for (final s in rows) {
        groupRanks.putIfAbsent(labels[s.id]!, () => groupRankOf(s));
      }
    }

    rows.sort((a, b) {
      final la = labels[a.id]!;
      final lb = labels[b.id]!;
      if (la != lb) {
        final ra = groupRanks[la]!;
        final rb = groupRanks[lb]!;
        if (ra != rb) return ra.compareTo(rb);
        // 同序号不同标签（未收录进顺序表的值）：按字面排，保证稳定。
        return la.compareTo(lb);
      }
      return within(a, b);
    });

    final groups = <SongGroup>[];
    for (final s in rows) {
      final label = labels[s.id]!;
      if (groups.isEmpty || groups.last.label != label) {
        groups.add(SongGroup(label, [s]));
      } else {
        groups.last.songs.add(s);
      }
    }
    return groups;
  }

  /// 值在顺序表里的下标；未收录的排到最后。
  static int _rankIn(List<String> order, String? value) {
    final i = value == null ? -1 : order.indexOf(value);
    return i < 0 ? order.length : i;
  }
}
