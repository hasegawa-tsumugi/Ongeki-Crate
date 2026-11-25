import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

/// 分组 + 段内排序的领域层验收。
///
/// 界面测试只验「三栏存在、选项数对、灰项不可选」，真正决定列表长什么样的是
/// `SongEngine.listGrouped`。这里用最小数据集把每种分组 / 每种排序的**顺序**
/// 钉死，避免以后改比较器时「看起来没坏、其实组和序都变了」。
Song mk(
  String id, {
  required String title,
  String? kana,
  String? genre,
  String? character,
  String? characterId,
  String? releaseTag,
  int rank = 3,
  double level = 10,
  int? enemyLevel,
  String? chapterId,
  String? dateAdded,
  bool hasCharts = true,
}) =>
    Song(
      id: id,
      title: title,
      titleKana: kana ?? title,
      artist: 'Artist',
      genre: genre,
      genreId: '01',
      bpm: 120,
      releaseTag: releaseTag,
      character: character,
      characterId: characterId,
      chapterId: chapterId,
      dateAdded: dateAdded,
      enemyLevel: enemyLevel,
      charts: hasCharts
          ? [
              Chart(
                difficulty: rank,
                level: level.floor(),
                levelDecimal: ((level - level.floor()) * 10).round(),
                levelValue: level,
                enabled: true,
              ),
            ]
          : const [],
    );

List<String> labels(List<SongGroup> groups) =>
    groups.map((g) => g.label).toList();

List<String> titles(SongGroup g) => g.songs.map((s) => s.title).toList();

void main() {
  group('分类分段', () {
    test('按 genreOrder 排，未收录的分类垫底', () {
      final engine = SongEngine([
        mk('1', title: 'a', genre: 'niconico'),
        mk('2', title: 'b', genre: 'POPS＆ANIME'),
        mk('3', title: 'c', genre: '未收录'),
        mk('4', title: 'd', genre: 'POPS＆ANIME'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.genre);
      expect(labels(groups), ['POPS＆ANIME', 'niconico', '未收录']);
      expect(groups[0].songs.length, 2);
    });

    test('全曲只有一段且不带组头', () {
      final engine = SongEngine([
        mk('1', title: 'a', genre: 'niconico'),
        mk('2', title: 'b', genre: 'POPS＆ANIME'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all);
      expect(groups.length, 1);
      expect(groups.single.label, '');
      expect(groups.single.songs.length, 2);
    });

    test('角色按 characterId 数字升序，缺 id 的排最后', () {
      final engine = SongEngine([
        mk('1', title: 'a', character: 'B', characterId: '0002'),
        mk('2', title: 'b', character: 'A', characterId: '0001'),
        mk('3', title: 'c', character: '无', characterId: null),
      ]);
      expect(labels(engine.listGrouped(group: TabGroup.character)), ['A', 'B', '无']);
    });

    test('版本按 releaseOrder 排', () {
      final engine = SongEngine([
        mk('1', title: 'a', releaseTag: 'RED'),
        mk('2', title: 'b', releaseTag: 'ONGEKI'),
        mk('3', title: 'c', releaseTag: 'SUMMER'),
      ]);
      expect(labels(engine.listGrouped(group: TabGroup.release)),
          ['ONGEKI', 'SUMMER', 'RED']);
    });

    test('谱面等级段是高级在前，无谱面的归到「—」', () {
      final engine = SongEngine([
        mk('1', title: 'a', level: 10.0),
        mk('2', title: 'b', level: 14.7),
        mk('3', title: 'c', level: 12.0),
        mk('4', title: 'd', hasCharts: false),
      ]);
      expect(labels(engine.listGrouped(group: TabGroup.level)),
          ['14', '12', '10', '—']);
    });

    test('曲名按五十音行分段，拉丁归到 A~G', () {
      final engine = SongEngine([
        mk('1', title: 'あさ', kana: 'アサ'),
        mk('2', title: 'かさ', kana: 'カサ'),
        mk('3', title: 'Apple', kana: 'Apple'),
      ]);
      expect(labels(engine.listGrouped(group: TabGroup.title)),
          ['あ行', 'か行', 'A~G']);
    });
  });

  group('段内排序', () {
    test('推荐顺序＝档位降序 → 等级降序 → 曲名升序', () {
      final engine = SongEngine([
        mk('1', title: 'b', rank: 3, level: 12.0),
        mk('2', title: 'a', rank: 4, level: 9.0),
        mk('3', title: 'c', rank: 3, level: 13.5),
        mk('4', title: 'a2', rank: 4, level: 9.0),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all, sort: TabSort.recommended);
      expect(titles(groups.single), ['a', 'a2', 'c', 'b']);
    });

    test('对手等级降序，缺值垫底', () {
      final engine = SongEngine([
        mk('1', title: 'a', enemyLevel: 5),
        mk('2', title: 'b', enemyLevel: 12),
        mk('3', title: 'c'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all, sort: TabSort.enemyLevel);
      expect(titles(groups.single), ['b', 'a', 'c']);
    });

    test('追加日期是新→旧', () {
      final engine = SongEngine([
        mk('1', title: 'old', dateAdded: '2018-07-26'),
        mk('2', title: 'new', dateAdded: '2026-10-15'),
        mk('3', title: 'mid', dateAdded: '2021-01-01'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all, sort: TabSort.dateAdded);
      expect(titles(groups.single), ['new', 'mid', 'old']);
    });

    test('章节按 chapterId 升序', () {
      final engine = SongEngine([
        mk('1', title: 'c', chapterId: '01003'),
        mk('2', title: 'a', chapterId: '01001'),
        mk('3', title: 'b', chapterId: '01002'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all, sort: TabSort.chapter);
      expect(titles(groups.single), ['a', 'b', 'c']);
    });

    test('曲名排序走五十音，而不是码位顺序', () {
      final engine = SongEngine([
        mk('1', title: 'か', kana: 'カ'),
        mk('2', title: 'あ', kana: 'ア'),
      ]);
      final groups = engine.listGrouped(group: TabGroup.all, sort: TabSort.title);
      expect(titles(groups.single), ['あ', 'か']);
    });

    test('分组与排序互不干扰：换排序不会改变分段顺序', () {
      final engine = SongEngine([
        mk('1', title: 'a', genre: 'niconico', dateAdded: '2020-01-01'),
        mk('2', title: 'b', genre: 'POPS＆ANIME', dateAdded: '2019-01-01'),
        mk('3', title: 'c', genre: 'niconico', dateAdded: '2026-01-01'),
      ]);
      final byName = engine.listGrouped(group: TabGroup.genre, sort: TabSort.title);
      final byDate = engine.listGrouped(group: TabGroup.genre, sort: TabSort.dateAdded);
      expect(labels(byName), labels(byDate), reason: '分段顺序只由分组键决定');
      // genreOrder 里 POPS＆ANIME 在 niconico 前面，按标签取段更稳。
      final nameNico = byName.firstWhere((g) => g.label == 'niconico');
      final dateNico = byDate.firstWhere((g) => g.label == 'niconico');
      expect(titles(nameNico), ['a', 'c']);
      expect(titles(dateNico), ['c', 'a'], reason: '段内顺序才跟着排序键走');
    });
  });

  group('缺数据的项', () {
    test('属性没有数据：传进来时退回分类分组', () {
      final engine = SongEngine([
        mk('1', title: 'a', genre: 'niconico'),
        mk('2', title: 'b', genre: 'POPS＆ANIME'),
      ]);
      expect(labels(engine.listGrouped(group: TabGroup.attribute)),
          labels(engine.listGrouped(group: TabGroup.genre)));
    });

    test('三种分数排序没有数据：退回推荐顺序', () {
      final engine = SongEngine([
        mk('1', title: 'a', rank: 3, level: 12.0),
        mk('2', title: 'b', rank: 4, level: 9.0),
      ]);
      final fallback = titles(
          engine.listGrouped(group: TabGroup.all, sort: TabSort.recommended).single);
      for (final scoreSort in [
        TabSort.battleScore,
        TabSort.technicalScore,
        TabSort.platinumScore
      ]) {
        expect(
          titles(engine.listGrouped(group: TabGroup.all, sort: scoreSort).single),
          fallback,
          reason: '$scoreSort 没有数据，必须和推荐顺序一致',
        );
      }
    });

    test('available 标记与表格三组一致', () {
      expect(TabGroup.values.where((v) => v.available).length, 6);
      expect(TabGroup.attribute.available, isFalse);
      expect(TabSort.values.where((v) => v.available).length, 5);
      expect(RivalScore.values.any((v) => v.available), isFalse);
    });
  });

  test('额外过滤在分组之前生效，不留空组头', () {
    final engine = SongEngine([
      mk('1', title: 'a', genre: 'POPS＆ANIME', level: 14.0),
      mk('2', title: 'b', genre: 'niconico', level: 9.0),
      mk('3', title: 'c', genre: 'niconico', level: 8.0),
    ]);
    final groups = engine.listGrouped(
      group: TabGroup.genre,
      predicate: (s) => s.topLevel >= 10,
    );
    expect(labels(groups), ['POPS＆ANIME']);
    expect(groups.single.songs.length, 1);
  });

  test('所有分组都把曲目刚好分完，不丢不重', () {
    final songs = [
      for (var i = 0; i < 12; i++)
        mk('$i',
            title: 'Song $i',
            genre: i.isEven ? 'POPS＆ANIME' : 'niconico',
            character: 'C${i % 3}',
            characterId: '000${i % 3}',
            releaseTag: ['ONGEKI', 'RED', 'SUMMER'][i % 3],
            level: 8 + (i % 6).toDouble(),
            chapterId: '0100${i % 4}',
            dateAdded: '2020-01-${(i + 1).toString().padLeft(2, '0')}',
            enemyLevel: i % 5),
    ];
    final engine = SongEngine(songs);
    for (final g in TabGroup.values) {
      for (final s in TabSort.values) {
        final groups = engine.listGrouped(group: g, sort: s);
        final flat = [for (final x in groups) ...x.songs];
        expect(flat.length, songs.length, reason: '$g / $s 丢了或重了曲目');
        expect(flat.map((e) => e.id).toSet().length, songs.length);
      }
    }
  });

  test('比较器里不许重算组标签（性能护栏）', () {
    // 组标签要么走 `kanaRow`（遍历假名行表），要么走 `topLevel`
    // （每次访问都重建并排序 `playableCharts`）。曾经这两者写在比较函数里，
    // 于是「谱面等级」「曲名」分组要跑 O(n log n) 次重建，实测 18ms/次，
    // 而「分类」分组只要 5ms —— 功能测试全绿，只有真机翻页会顿。
    //
    // 修法是先算一张 `labels` 表再排序。这条源码级护栏防的是「以后为了少写
    // 几行又把 groupLabelOf(a) 塞回比较器」：那种回归排序结果一模一样，
    // 任何断言都不会红，只有手感变差。
    final src = File('lib/src/domain.dart').readAsStringSync();
    expect(
      RegExp(r'groupLabelOf\(\s*[ab]\s*\)').hasMatch(src),
      isFalse,
      reason: '比较器里不该现算组标签，请查 labels[a.id] / labels[b.id]',
    );
    expect(
      RegExp(r'groupRankOf\(\s*[ab]\s*\)').hasMatch(src),
      isFalse,
      reason: '组序号只该在预计算循环里按 s 算一次',
    );
    expect(
      src,
      contains('for (final s in rows) s.id: groupLabelOf(s),'),
      reason: 'grouped 排序前必须先建 labels 表',
    );
  });
}
