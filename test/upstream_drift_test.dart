import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

/// 造一条上游行，形状与 `music-ex.json` 一致：**所有取值都是字符串**。
///
/// 这是刻意的 —— 线上 `lev_mas_i` 是 `'11.8'` 这种小数形态的字符串，
/// 而不是「定数×10」的整数。用整数造样本会把精度 bug 盖住。
Map<String, dynamic> upstreamRow(
  String id, {
  String title = 'Song',
  String levBas = '3',
  String levMas = '11+',
  String levMasI = '11.8',
  String bpm = '176',
  String dateAdded = '20180726',
}) =>
    {
      'id': id,
      'title': title,
      'title_sort': title,
      'artist': 'Artist',
      'category': 'チュウマイ',
      'category_id': '05',
      'chapter': 'Chapter',
      'chap_id': '01001',
      'character': '星咲 あかり',
      'chara_id': '0001',
      'enemy_lv': '5',
      'enemy_type': 'FIRE',
      'bpm': bpm,
      'version': 'ONGEKI',
      'new': '',
      'bonus': '',
      'copyright1': '-',
      'date_added': dateAdded,
      'wikiwiki_url': 'https://wikiwiki.jp/gameongeki/$id',
      'image_url': '$id.png',
      'lev_bas': levBas,
      'lev_adv': '6',
      'lev_exc': '8+',
      'lev_mas': levMas,
      'lev_lnt': '',
      'lev_bas_i': '',
      'lev_exc_i': '',
      'lev_mas_i': levMasI,
      'lev_bas_notes': '302',
      'lev_bas_bells': '87',
    };

List<Map<String, dynamic>> many(
  int count,
  Map<String, dynamic> Function(int index) build,
) =>
    [for (var i = 0; i < count; i++) build(i)];

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // 独立预言机：fixture 里的上游行 → 转换器 → 必须与随包快照逐字段一致。
  //
  // 随包快照是 RN 管线的产物，不是这份 Dart 代码生的。所以它是一份真正
  // 独立的期望值：转换器抄错一处就会在这里红，而不是等到用户在线更新完
  // 发现每首歌的定数都变成 1.x。
  //
  // fixture 只收录了「当前上游仍与快照一致」的行，避免上游后来改定数造成的
  // 假红。生成脚本见 tool/_gen_upstream_fixture.py（跑完可删，产物要提交）。
  // ───────────────────────────────────────────────────────────────────────
  group('转换器的独立预言机', () {
    test('上游样本转换后与随包快照逐字段一致', () async {
      final raw = jsonDecode(
        await File('test/fixtures/upstream_sample.json').readAsString(),
      ) as List;
      final bundled = Dataset.fromJson(
        jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()),
      );
      final byId = {for (final s in bundled.songs) s.id: s};

      expect(raw, hasLength(greaterThanOrEqualTo(20)));
      final converted = Dataset.fromUpstream(raw);
      expect(converted.songs, hasLength(raw.length));

      for (final song in converted.songs) {
        final ref = byId[song.id];
        expect(ref, isNotNull, reason: '${song.id} 不在随包快照里');
        final where = '${song.id}「${song.title}」';
        expect(song.title, ref!.title, reason: '$where title');
        expect(song.titleKana, ref.titleKana, reason: '$where titleKana');
        expect(song.artist, ref.artist, reason: '$where artist');
        expect(song.genre, ref.genre, reason: '$where genre');
        expect(song.genreId, ref.genreId, reason: '$where genreId');
        expect(song.bpm, ref.bpm, reason: '$where bpm');
        expect(song.releaseTag, ref.releaseTag, reason: '$where releaseTag');
        expect(song.chapter, ref.chapter, reason: '$where chapter');
        expect(song.chapterId, ref.chapterId, reason: '$where chapterId');
        expect(song.character, ref.character, reason: '$where character');
        expect(song.characterId, ref.characterId, reason: '$where characterId');
        expect(song.enemyLevel, ref.enemyLevel, reason: '$where enemyLevel');
        expect(song.enemyType, ref.enemyType, reason: '$where enemyType');
        expect(song.dateAdded, ref.dateAdded, reason: '$where dateAdded');
        expect(song.wikiUrl, ref.wikiUrl, reason: '$where wikiUrl');
        expect(song.artwork, ref.artwork, reason: '$where artwork');

        expect(song.charts, hasLength(ref.charts.length),
            reason: '$where 谱面数');
        for (var i = 0; i < song.charts.length; i++) {
          final c = song.charts[i];
          final r = ref.charts[i];
          final at = '$where chart[$i]';
          expect(c.difficulty, r.difficulty, reason: '$at difficulty');
          expect(c.level, r.level, reason: '$at level');
          expect(c.levelDecimal, r.levelDecimal, reason: '$at levelDecimal');
          expect(c.levelValue, r.levelValue, reason: '$at levelValue');
          expect(c.levelLabel, r.levelLabel, reason: '$at levelLabel');
          expect(c.noteCount, r.noteCount, reason: '$at noteCount');
          expect(c.bells, r.bells, reason: '$at bells');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 字段漂移：上游静默改名是本项目最大的外部风险。
  // 单看条数抓不到 —— 改掉 lev_mas_i 后 1112 首还是 1112 首。
  // ───────────────────────────────────────────────────────────────────────
  group('上游字段漂移', () {
    test('整列 title 改名时拒绝转换，而不是装一份空标题曲库', () {
      final rows = many(60, (i) {
        final r = upstreamRow('${1000 + i}');
        r['name'] = r.remove('title');
        return r;
      });
      expect(
        () => Dataset.fromUpstream(rows),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('title'),
          ),
        ),
      );
    });

    test('整列 lev_bas 改名时报错并点名难度字段', () {
      final rows = many(60, (i) {
        final r = upstreamRow('${1000 + i}');
        r['lev_basic'] = r.remove('lev_bas');
        return r;
      });
      expect(
        () => Dataset.fromUpstream(rows),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('lev_bas'),
          ),
        ),
      );
    });

    test('一半曲目丢了 lev_bas 也拒绝，不是「少了就少了」', () {
      final rows = many(60, (i) {
        final r = upstreamRow('${1000 + i}');
        if (i.isEven) r['lev_basic'] = r.remove('lev_bas');
        return r;
      });
      expect(() => Dataset.fromUpstream(rows), throwsFormatException);
    });

    test('lev_mas_i 改名时报错，而不是让全库定数静默变 0', () {
      // 这是最阴的一条：条数不变、往返校验能过，只是每首歌的
      // topLevel 都变 0（顶栏显示 —、默认排序退化成按曲名）。
      final rows = many(60, (i) {
        final r = upstreamRow('${1000 + i}');
        r['lev_mas_lv'] = r.remove('lev_mas_i');
        return r;
      });
      expect(
        () => Dataset.fromUpstream(rows),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('lev_'),
          ),
        ),
      );
    });

    test('少数脏行只丢该行，不整体拒绝', () {
      final rows = many(60, (i) {
        final r = upstreamRow('${1000 + i}');
        if (i == 7) r.remove('title');
        return r;
      });
      final ds = Dataset.fromUpstream(rows);
      expect(ds.songs, hasLength(59));
      expect(ds.songs.any((s) => s.title.isEmpty), isFalse);
    });

    test('非 Map 行被跳过而不是抛异常', () {
      final rows = <dynamic>[
        ...many(20, (i) => upstreamRow('${1000 + i}')),
        'junk',
        42,
        null,
      ];
      expect(Dataset.fromUpstream(rows).songs, hasLength(20));
    });

    test('空输入与错误形状一律拒绝', () {
      for (final bad in <dynamic>[
        null,
        <dynamic>[],
        {'songs': 'not a list'},
        {'songs': <dynamic>[]},
        {'something': 1},
      ]) {
        expect(() => Dataset.fromUpstream(bad), throwsFormatException,
            reason: '应拒绝：$bad');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 单字段形态变化：能降级就降级，不要因为一个字段炸掉整次更新。
  // ───────────────────────────────────────────────────────────────────────
  group('单字段容错', () {
    test('lev_*_i 是 "13.7" 时拆成 13 + 0.7', () {
      final ds = Dataset.fromUpstream([
        upstreamRow('1', levMas: '13+', levMasI: '13.7'),
      ]);
      // 样本行同时带 adv/exc，所以按难度取 MASTER（difficulty 3）。
      final chart = ds.songs.single.charts
          .firstWhere((c) => c.difficulty == 3);
      expect(chart.level, 13);
      expect(chart.levelDecimal, 7);
      expect(chart.levelValue, 13.7);
      expect(ds.songs.single.displayTopLevel, '13.7');
    });

    test('lev_*_i 缺失时仍按标签给出整数档，定数留 0', () {
      final ds = Dataset.fromUpstream([
        upstreamRow('1', levMas: '11+', levMasI: ''),
        upstreamRow('2', levMasI: '12.4'),
      ]);
      final noValue = ds.songs.first.charts
          .firstWhere((c) => c.difficulty == 3);
      expect(noValue.level, 11);
      expect(noValue.levelValue, 0);
      expect(noValue.levelLabel, '11+');
      // 界面看到 0 会显示标签，不假装知道定数。
      expect(ds.songs.first.displayTopLevel, '—');
      expect(ds.songs.first.displayLevel(noValue), '11+');
    });

    test('bpm 写成 "176 BPM" 时降级为 null，不抛异常', () {
      final ds = Dataset.fromUpstream([
        upstreamRow('1', bpm: '176 BPM'),
        upstreamRow('2', bpm: ''),
      ]);
      expect(ds.songs.map((s) => s.bpm), [null, null]);
    });

    test('bpm 是数字字符串时正常读成 double', () {
      final ds = Dataset.fromUpstream([upstreamRow('1', bpm: '176.5')]);
      expect(ds.songs.single.bpm, 176.5);
    });

    test('date_added 认不出的形态原样保留', () {
      final ds = Dataset.fromUpstream([
        upstreamRow('1', dateAdded: '20180726'),
        upstreamRow('2', dateAdded: '2018-07-26'),
        upstreamRow('3', dateAdded: ''),
      ]);
      expect(ds.songs[0].dateAdded, '2018-07-26');
      expect(ds.songs[1].dateAdded, '2018-07-26');
      expect(ds.songs[2].dateAdded, isNull);
    });

    test('"-" 占位符不进模型', () {
      final ds = Dataset.fromUpstream([upstreamRow('1')]);
      expect(ds.songs.single.copyright, isNull);
      expect(ds.songs.single.isNew, isFalse);
      expect(ds.songs.single.isBonus, isFalse);
    });

    test('所有难度标签都为空时该曲没有谱面，曲目仍保留', () {
      final rows = [
        () {
          final r = upstreamRow('1', levBas: '');
          for (final s in ['bas', 'adv', 'exc', 'mas', 'lnt']) {
            r['lev_$s'] = '';
          }
          return r;
        }(),
        ...many(9, (i) => upstreamRow('${10 + i}')),
      ];
      final ds = Dataset.fromUpstream(rows);
      expect(ds.songs, hasLength(10));
      expect(ds.songs.first.charts, isEmpty);
      expect(ds.songs.first.displayTopLevel, '—');
    });
  });
}
