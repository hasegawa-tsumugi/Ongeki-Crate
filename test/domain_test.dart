import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/collation_han.dart';
import 'package:songquery_flutter/src/domain.dart';

Song song(
  String id, {
  String? titleKana,
  double? bpm,
  String? releaseTag,
  String? characterId,
  double level = 0,
  String? genre,
  String? character,
}) =>
    Song(
      id: id,
      title: 'Song $id',
      titleKana: titleKana,
      artist: 'Artist',
      genre: genre,
      genreId: '01',
      bpm: bpm,
      releaseTag: releaseTag,
      character: character,
      characterId: characterId,
      charts: [
        Chart(
          difficulty: 3,
          level: level.floor(),
          levelDecimal: ((level - level.floor()) * 10).round(),
          levelValue: level,
          enabled: true,
        ),
      ],
    );

void main() {
  group('JSON / dataset', () {
    test(
      'loads the actual bundled dataset and preserves song metadata',
      () async {
        final json = jsonDecode(
          await File('assets/songs-2026.10.15.json').readAsString(),
        );
        final data = Dataset.fromJson(json);
        expect(data.songs.length, greaterThan(1000));
        expect(data.songs.first.id, '520100');
        expect(data.songs.first.charts.length, greaterThan(0));
      },
    );
    test('round-trips songs and keeps unknown chart levels distinct', () {
      final original = song('1', level: 13.7);
      final round = Song.fromJson(original.toJson());
      expect(round.topLevel, 13.7);
      expect(round.playableCharts.length, 1);
    });
    test('rejects a malformed dataset', () {
      expect(() => Dataset.fromJson({'songs': 'wrong'}), throwsFormatException);
    });
    test('stored json carries the schema version', () {
      // 仓储靠这个戳判断「旧文件还能不能用」，漏写就等于让坏数据永远修不好。
      final json = Dataset([song('1')]).toJson();
      expect((json['meta'] as Map)['schema'], datasetSchemaVersion);
      expect(datasetSchemaVersion, greaterThan(1));
    });
    test('round-trip keeps the schema stamp readable from meta', () {
      final json = Dataset([song('1')]).toJson();
      final back = Dataset.fromJson(jsonDecode(jsonEncode(json)));
      expect(back.meta['schema'], datasetSchemaVersion);
      expect(back.songs.single.id, '1');
    });
  });
  group('sorting', () {
    final input = [
      song('1', bpm: 180),
      song('2', bpm: 90),
      song('3'),
      song('4', bpm: 0),
      song('5', bpm: -20),
      song('6', bpm: double.nan),
    ];
    test('BPM ascending and missing values always last', () {
      expect(
        SongEngine(input).list(sort: SortKey.bpm).map((s) => s.id).toList(),
        ['2', '1', '3', '4', '5', '6'],
      );
    });
    test('BPM descending and missing values always last', () {
      expect(
        SongEngine(input)
            .list(sort: SortKey.bpm, direction: SortDirection.desc)
            .map((s) => s.id)
            .toList(),
        ['1', '2', '3', '4', '5', '6'],
      );
    });
    test(
      'missing release and character values stay last in both directions',
      () {
        final xs = [
          song('1', releaseTag: 'RED', characterId: '0002'),
          song('2', releaseTag: null, characterId: null),
          song('3', releaseTag: 'ONGEKI', characterId: '0001'),
        ];
        for (final direction in SortDirection.values) {
          expect(
            SongEngine(xs)
                .list(sort: SortKey.release, direction: direction)
                .last
                .id,
            '2',
          );
          expect(
            SongEngine(xs)
                .list(sort: SortKey.character, direction: direction)
                .last
                .id,
            '2',
          );
        }
      },
    );
    test('default orders by enabled top chart level descending', () {
      final xs = [
        song('1', level: 9),
        song('2', level: 13),
        song('3', level: 11),
      ];
      expect(SongEngine(xs).list().map((s) => s.id), ['2', '3', '1']);
    });
    test('release ordering uses curated release order', () {
      final xs = [
        song('1', releaseTag: 'RED'),
        song('2', releaseTag: 'ONGEKI'),
        song('3', releaseTag: 'bright MEMORY Act.1'),
      ];
      expect(
        SongEngine(xs).list(sort: SortKey.release).map((s) => s.releaseTag),
        ['ONGEKI', 'RED', 'bright MEMORY Act.1'],
      );
    });
    test('character ordering uses character id', () {
      final xs = [
        song('1', characterId: '0004'),
        song('2', characterId: '0001'),
      ];
      expect(SongEngine(xs).list(sort: SortKey.character).map((s) => s.id), [
        '2',
        '1',
      ]);
    });
    test('tie break is deterministic', () {
      final xs = [song('2', bpm: 100), song('1', bpm: 100)];
      expect(SongEngine(xs).list(sort: SortKey.bpm).map((s) => s.id), [
        '1',
        '2',
      ]);
    });
    test('same character id falls back to title order', () {
      final xs = [
        song('2', characterId: '0001'),
        song('1', characterId: '0001'),
      ];
      expect(
        SongEngine(xs).list(sort: SortKey.character).map((s) => s.id),
        ['1', '2'],
      );
    });
    test('same release tag falls back to title order', () {
      final xs = [
        song('2', releaseTag: 'ONGEKI'),
        song('1', releaseTag: 'ONGEKI'),
      ];
      expect(
        SongEngine(xs).list(sort: SortKey.release).map((s) => s.id),
        ['1', '2'],
      );
    });
    test('both missing character id falls back to title order', () {
      // 两首都无 characterId 时 hasA == hasB == false，走 `if (!hasA) return byTitle`。
      // 与「一方缺失」不同（那条走 hasA != hasB 提前返回），是另一条分支。
      final xs = [song('2'), song('1')];
      expect(
        SongEngine(xs).list(sort: SortKey.character).map((s) => s.id),
        ['1', '2'],
      );
    });
    test('both missing release tag falls back to title order', () {
      final xs = [song('2'), song('1')];
      expect(
        SongEngine(xs).list(sort: SortKey.release).map((s) => s.id),
        ['1', '2'],
      );
    });
  });
  group('japanese collation', () {
    Song titled(String id, String title) =>
        Song(id: id, title: title, charts: const []);

    test('folds hiragana onto katakana so both share a primary weight', () {
      expect(compareSortKeys(titleSortKey('あいう'), titleSortKey('アイウ')), 0);
      expect(compareSortKeys(titleSortKey('が'), titleSortKey('ガ')), 0);
    });
    test('latin compares case-insensitively at the primary level', () {
      expect(compareSortKeys(titleSortKey('AbC'), titleSortKey('abc')), 0);
    });
    test('dakuten is a secondary weight, not a different primary', () {
      // 清音 < 浊音 < 半浊音，且都排在下一行假名之前。
      final sorted = ['パ', 'キ', 'ガ', 'カ']
        ..sort((a, b) => compareSortKeys(titleSortKey(a), titleSortKey(b)));
      expect(sorted, ['カ', 'ガ', 'キ', 'パ']);
    });
    test('small kana sorts before its base kana', () {
      final sorted = ['ア', 'ァ', 'イ', 'ィ']
        ..sort((a, b) => compareSortKeys(titleSortKey(a), titleSortKey(b)));
      expect(sorted, ['ァ', 'ア', 'ィ', 'イ']);
    });
    test('collation table orders symbols the way ICU ja does', () {
      // ICU ja：`・` < `!` < `ー` < 数字 < 假名（表外字符）。
      final order = ['ん', '9', 'ー', '!', '・'];
      final sorted = [...order]
        ..sort((a, b) => compareSortKeys(titleSortKey(a), titleSortKey(b)));
      expect(sorted, ['・', '!', 'ー', '9', 'ん']);
    });
    test('hiragana and katakana titles interleave instead of blocking', () {
      // 纯码位比较会把「いーある…」(U+3044) 排在所有片假名标题(U+30A1+)之前，
      // 而 ICU ja 里 あ / ア 同级，比较落在 あ<い 上。
      final engine = SongEngine([
        titled('1', 'いーあるふぁんくらぶ'),
        titled('2', 'アイドライフライト'),
      ]);
      expect(engine.list(sort: SortKey.title).map((s) => s.id), ['2', '1']);
    });
    test('latin sorts before kana and kanji after it', () {
      final engine = SongEngine([
        titled('1', '漢字'),
        titled('2', 'かな'),
        titled('3', 'Kana'),
      ]);
      expect(
          engine.list(sort: SortKey.title).map((s) => s.id), ['3', '2', '1']);
    });
    test('kanji follows ICU reading order, not codepoint order', () {
      // 期望值取自 V8/ICU：localeCompare(a, b, 'ja') 的完整顺序。
      // 码位序是「一上亜光夜夢宇川影心愛日星春月朝東永海火空花西雨風鳥」，
      // 两者大量互逆（ICU 亜<一、日>月、火<月），所以这条断言对码位实现必红。
      const input = '亜一日月上東西夢愛花鳥雨宇影永火川空心光風海星夜朝春';
      const expected = '亜愛一宇雨影永火花海空月光春上心星西川朝鳥東日風夢夜';
      final sorted = input.runes.map(String.fromCharCode).toList()
        ..sort((a, b) => compareSortKeys(titleSortKey(a), titleSortKey(b)));
      expect(sorted.join(), expected);
    });
    test('kanji titles reorder where codepoint order gets it backwards', () {
      // 码位序：月(U+6708) < 火(U+706B)，ICU 序反过来。
      final engine = SongEngine([
        titled('1', '月光'),
        titled('2', '火花'),
      ]);
      expect(engine.list(sort: SortKey.title).map((s) => s.id), ['2', '1']);
    });
    test('kanji outside the shipped table falls back to codepoint, last', () {
      // 曲库快照里没出现过「驫」，查不到权重 → 退回码位（1000+rune），
      // 排在表内所有汉字之后，也排在假名之后。
      expect(
          compareSortKeys(titleSortKey('亜'), titleSortKey('驫')), lessThan(0));
      expect(
          compareSortKeys(titleSortKey('ん'), titleSortKey('驫')), lessThan(0));
    });
    test('kanji table covers every CJK char in the shipped snapshot', () async {
      // 护栏：曲库换新快照、引入新汉字时这条会红，提醒重跑
      // tool/gen_collation_table.mjs。
      final json = jsonDecode(
        await File('assets/songs-2026.10.15.json').readAsString(),
      );
      final missing = <String>{};
      for (final song in Dataset.fromJson(json).songs) {
        for (final rune in song.title.runes) {
          if (rune >= 0x4E00 &&
              rune <= 0x9FFF &&
              hanCollationRanks[rune] == null) {
            missing.add(String.fromCharCode(rune));
          }
        }
      }
      expect(missing, isEmpty, reason: '重跑 tool/gen_collation_table.mjs');
    });
    test('fullwidth forms collapse onto ASCII like ICU does', () {
      // ICU：localeCompare('Ｇ','G','ja') === 0，！/？/： 同理。
      expect(
          compareSortKeys(titleSortKey('ＧＯ！ＧＯ！'), titleSortKey('GO!GO!')), 0);
      expect(compareSortKeys(titleSortKey('Ⅲ'), titleSortKey('III')), 0);
      expect(compareSortKeys(titleSortKey('⑨'), titleSortKey('9')), 0);
    });
    test('accented latin folds to its base letter at the primary level', () {
      // 主权重相同，变音符只体现在第二层：A < Ä。
      expect(compareSortKeys(titleSortKey('Ä'), titleSortKey('A')),
          greaterThan(0));
      final sorted = ['Ä', 'A', 'B']
        ..sort((a, b) => compareSortKeys(titleSortKey(a), titleSortKey(b)));
      expect(sorted, ['A', 'Ä', 'B']);
      // 折到 ASCII 后不能掉进 1000+rune 兜底（那样会排到所有汉字后面）。
      expect(compareSortKeys(titleSortKey('Löschen'), titleSortKey('愛')),
          lessThan(0));
    });
    test('long vowel mark inherits the preceding kana vowel', () {
      // JIS X 4061：`ー` 不占独立符号权重，而是继承前一个假名的元音
      // （カー≈カア、コー≈コオ）。ICU 实测：カー<カア、コウ<コー、シア<シー。
      expect(
          compareSortKeys(titleSortKey('カー'), titleSortKey('カア')), lessThan(0));
      expect(
          compareSortKeys(titleSortKey('コウ'), titleSortKey('コー')), lessThan(0));
      expect(
          compareSortKeys(titleSortKey('シア'), titleSortKey('シー')), lessThan(0));
      // 落到标题级别：シークレット 不该排到 シアワセ 前面。
      final engine = SongEngine([
        titled('1', 'シークレット・シーカー'),
        titled('2', 'シアワセうさぎ'),
      ]);
      expect(engine.list(sort: SortKey.title).map((s) => s.id), ['2', '1']);
    });
    test('letter scripts sort after kanji, symbols before', () {
      // ICU：∀ < 亜 < α < Я。
      expect(
          compareSortKeys(titleSortKey('∀'), titleSortKey('亜')), lessThan(0));
      expect(compareSortKeys(titleSortKey('Λ'), titleSortKey('亜')),
          greaterThan(0));
      expect(
          compareSortKeys(titleSortKey('α'), titleSortKey('Λ')), lessThan(0));
      // 大写希腊字母要先转小写再查表，查不到就会掉进码位兜底。
      expect(compareSortKeys(titleSortKey('Λlteration'), titleSortKey('μ3')),
          lessThan(0));
    });
  });
  group('normalization and search', () {
    test('katakana and hiragana normalize to same key', () {
      expect(normalize('ビビデバ'), normalize('びびでば'));
    });
    test('punctuation and fullwidth characters are ignored', () {
      expect(normalize('ＧＯ！ＧＯ！'), normalize('gogo'));
      expect(normalize('１２３４'), '1234');
      expect(SongEngine([song('001234')]).search('１２３４'), isNotEmpty);
    });
    test('transposition is one edit', () {
      expect(editDistance('abcd', 'abdc'), 1);
    });
    test('halfwidth katakana folds onto fullwidth, including voiced marks', () {
      expect(normalize('ｷﾞﾀｰ'), normalize('ギター'));
      expect(normalize('ｶﾞ'), normalize('ガ'));
      expect(normalize('ﾊﾟ'), normalize('パ'));
      expect(normalize('ｶﾞ'), isNot(normalize('カ')));
      expect(
          SongEngine([song('1', titleKana: 'ギター')]).search('ｷﾞﾀｰ'), isNotEmpty);
    });
    test('circled digits and roman numerals fold to ASCII', () {
      expect(normalize('①'), '1');
      expect(normalize('⑳'), '20');
      expect(normalize('Ⅻ'), 'xii');
      // Ⅲ -> "III" -> 小写 "iii" -> 3 个连续重复压成 2 个
      expect(normalize('Ⅲ'), 'ii');
    });
    test('repeated characters squash to two instead of leaking a backref', () {
      expect(normalize('ああああ'), 'ああ');
      expect(normalize('!!!!'), '');
      expect(normalize('aeeeee'), 'aee');
      expect(normalize('abcabc'), 'abcabc');
    });
    test('search supports title, reading and ID', () {
      final songs = [song('001234', titleKana: 'ビビデバ')];
      final engine = SongEngine(songs);
      expect(engine.search('1234').first.song.id, '001234');
      expect(engine.search('ビビデバ'), isNotEmpty);
      expect(engine.search('Song'), isNotEmpty);
    });
    test('query stages prioritize exact matches over title prefixes', () {
      const exact = Song(
        id: '2',
        title: 'Other Title',
        aliases: ['Beat'],
        charts: [],
      );
      final prefix = song('1', titleKana: 'Beat Saber');
      final hits = SongEngine([prefix, exact]).search('Beat');
      expect(hits.first.song.id, '2');
    });
    test('folded kana recovers ordering-key readings', () {
      final hit = SongEngine([song('1', titleKana: 'コチソウ')]).search('ごちそう');
      expect(hit.map((value) => value.song.id), ['1']);
    });
    test('short query does not trigger fuzzy matching', () {
      expect(SongEngine([song('1')]).search('sox'), isEmpty);
    });

    test('collect scores a reading hit through the non-title branch', () {
      // 「そう」是读音 key「こちそう」的 contains 命中（stage 2），field 是「读音」
      // 既非「别名」也非「曲名」—— 走 170 分那条 else，顺带盖掉 stage 2 的打分。
      final hit = SongEngine([song('1', titleKana: 'コチソウ')]).search('そう');
      expect(hit.single.song.id, '1');
      expect(hit.single.reason, contains('读音'));
    });

    test('folded kana fallback matches by prefix when collect finds nothing', () {
      // 「ごちそ」（带浊点）在 collect 里既不等同也不前缀于平假名 key「こちそう」，
      // 只有剥掉浊点后的「こちそ」才前缀命中 —— 这条岔路以前从没被跑过。
      final hit = SongEngine([song('1', titleKana: 'コチソウ')]).search('ごちそ');
      expect(hit.map((value) => value.song.id), ['1']);
      expect(hit.single.reason, contains('读音'));
    });

    test('folded kana fallback also matches by containment', () {
      // 「ぢぞ」剥成「ちそ」—— 是 key「こちそう」的**中间**子串，不是前缀，
      // 所以 stage 1 的 startsWith 不中、要落到 stage 2 的 contains。
      // 注意查询必须带浊点（否则 foldKana 不改写、fallback 块整段跳过），
      // 且剥完不能是前缀（否则 stage 1 先命中就 return，轮不到 stage 2）。
      final hit = SongEngine([song('1', titleKana: 'コチソウ')]).search('ぢぞ');
      expect(hit.map((value) => value.song.id), ['1']);
      expect(hit.single.reason, contains('读音'));
    });

    test('fuzzy matching kicks in when every exact stage misses', () {
      // 「xyzz」不是任何 key 的等同/前缀/包含，所以 collect 三阶段全空、
      // 落到编辑距离兜底。xyzabc 差 2、xyzb 差 1 —— 更近的 xyzb 会把先前
      // 按距离 2 累积的 xyzabc 清掉（fuzzy.clear()），只留距离 1 那一档。
      final engine = SongEngine([
        song('1', titleKana: 'xyzabc'),
        song('2', titleKana: 'xyzb'),
      ]);
      final hits = engine.search('xyzz');
      expect(hits.map((h) => h.song.id), ['2']);
      expect(hits.single.reason, contains('模糊匹配'));
    });
  });
  group('kana row and filters', () {
    test('groups kana and Latin', () {
      expect(kanaRow('あいう'), 'あ行');
      expect(kanaRow('GOGO'), 'A~G');
      expect(kanaRow('うた'), 'あ行');
    });
    test('filter by genre and character and reading row', () {
      final xs = [
        song(
          '1',
          genre: 'A',
          character: '星咲 あかり',
          characterId: '0001',
          titleKana: 'あいう',
        ),
        song(
          '2',
          genre: 'B',
          character: '高瀬 梨緒',
          characterId: '0004',
          titleKana: 'GOGO',
        ),
      ];
      final e = SongEngine(xs);
      expect(
        e.list(filter: const SongFilters(genres: {'A'})).map((s) => s.id),
        ['1'],
      );
      expect(
        e
            .list(
              sort: SortKey.title,
              filter: const SongFilters(rows: {'A~G'}),
            )
            .map((s) => s.id),
        ['2'],
      );
      expect(characterReading('星咲 あかり'), 'ほしざき');
    });
  });

  group('filter matching (shared by browse and search)', () {
    // 两首曲的四个维度全都不同，任何一条判断写错都会让下面某个断言变红。
    final xs = [
      song(
        '1',
        genre: 'A',
        character: '星咲 あかり',
        characterId: '0001',
        releaseTag: 'RED',
        titleKana: 'あいう',
      ),
      song(
        '2',
        genre: 'B',
        character: '高瀬 梨緒',
        characterId: '0004',
        releaseTag: 'SUMMER',
        titleKana: 'GOGO',
      ),
    ];
    final a = xs[0];
    final b = xs[1];

    test('分类 / 角色 / 版本各自独立生效', () {
      expect(const SongFilters().matches(a, SortKey.title), isTrue);
      expect(const SongFilters(genres: {'A'}).matches(a, SortKey.title), isTrue);
      expect(const SongFilters(genres: {'A'}).matches(b, SortKey.title), isFalse);
      expect(
        const SongFilters(characters: {'高瀬 梨緒'}).matches(b, SortKey.title),
        isTrue,
      );
      expect(
        const SongFilters(characters: {'高瀬 梨緒'}).matches(a, SortKey.title),
        isFalse,
      );
      expect(
        const SongFilters(releaseTags: {'RED'}).matches(a, SortKey.title),
        isTrue,
      );
      expect(
        const SongFilters(releaseTags: {'RED'}).matches(b, SortKey.title),
        isFalse,
      );
    });

    test('多个条件同时满足才算通过（AND 不是 OR）', () {
      const both = SongFilters(genres: {'A'}, releaseTags: {'SUMMER'});
      expect(both.matches(a, SortKey.title), isFalse);
      expect(both.matches(b, SortKey.title), isFalse);
      const ok = SongFilters(genres: {'A'}, releaseTags: {'RED'});
      expect(ok.matches(a, SortKey.title), isTrue);
    });

    test('rows 按排序取字段：角色排序读角色读音，其余读曲名读音', () {
      // 曲名读音分组：'1' 是 あ行、'2' 是 A~G。
      expect(const SongFilters(rows: {'A~G'}).matches(b, SortKey.title), isTrue);
      expect(const SongFilters(rows: {'A~G'}).matches(a, SortKey.title), isFalse);
      // 角色读音分组：星咲 あかり → ほしざき（は行）、高瀬 梨緒 → たかせ（た行）。
      expect(
        const SongFilters(rows: {'た行'}).matches(b, SortKey.character),
        isTrue,
      );
      expect(
        const SongFilters(rows: {'た行'}).matches(a, SortKey.character),
        isFalse,
      );
      // 同一个「あ行」在两种排序下指向不同字段：曲名读音命中 '1'，
      // 角色读音里没有 あ 行，所以角色排序下两首都不该命中。
      expect(const SongFilters(rows: {'あ行'}).matches(a, SortKey.title), isTrue);
      expect(
        const SongFilters(rows: {'あ行'}).matches(a, SortKey.character),
        isFalse,
      );
    });

    test('浏览列表与搜索结果用的是同一份判断', () {
      final engine = SongEngine(xs);
      for (final filter in const [
        SongFilters(genres: {'A'}),
        SongFilters(releaseTags: {'SUMMER'}),
        SongFilters(characters: {'星咲 あかり'}),
        SongFilters(rows: {'A~G'}),
        SongFilters(rows: {'た行'}),
      ]) {
        for (final sort in SortKey.values) {
          final browse = engine
              .list(sort: sort, filter: filter)
              .map((s) => s.id)
              .toSet();
          // 搜索路径是「先全量搜、再按同一份判断过滤」，不能把筛掉的捞回来。
          final search = engine
              .search('Song')
              .map((h) => h.song)
              .where((s) => filter.matches(s, sort))
              .map((s) => s.id)
              .toSet();
          expect(
            search,
            browse,
            reason: 'filter=$filter sort=$sort 下搜索与浏览结果不一致',
          );
        }
      }
    });
  });

  group('isHomeCharacterId', () {
    test('0001–0017 判为本家', () {
      expect(isHomeCharacterId('0001'), isTrue);
      expect(isHomeCharacterId('0016'), isTrue);
      expect(isHomeCharacterId('0017'), isTrue);
    });
    test('联动角色与异常值不算本家', () {
      expect(isHomeCharacterId('0018'), isFalse);
      expect(isHomeCharacterId('0052'), isFalse);
      expect(isHomeCharacterId('9002'), isFalse);
      expect(isHomeCharacterId(''), isFalse);
      expect(isHomeCharacterId(null), isFalse);
    });
  });
}
