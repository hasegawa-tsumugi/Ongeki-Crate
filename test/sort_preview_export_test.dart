import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

void main() {
  test('导出离线预览使用的真实排序与搜索真值', () async {
    final data = Dataset.fromJson(jsonDecode(await File('assets/songs-2026.10.15.json').readAsString()));
    final engine = SongEngine(data.songs);
    final orders = <String, dynamic>{};
    for (final sort in SortKey.values) {
      for (final direction in SortDirection.values) {
        final ids = engine.list(sort: sort, direction: direction).map((s) => s.id).toList();
        expect(ids.toSet().length, data.songs.length);
        orders['${sort.name}_${direction.name}'] = ids;
      }
    }
    final queries = ['GO', 'love', 'あ', '520100', 'ＧＯ', 'ｶﾞ', '驫', 'sugar', 'ongkei', '①', 'Ⅲ', 'zzzzzz'];
    final payload = {
      'songs': data.songs.map((s) => {...s.toJson(), 'topLevel': s.topLevel, 'titleRow': kanaRow(s.titleKana ?? s.title), 'characterRow': kanaRow(characterReading(s.character)), 'terms': [
        {'text': s.title, 'key': normalize(s.title), 'folded': foldKana(normalize(s.title)), 'field': '曲名', 'weight': 1},
        if (s.titleKana != null) {'text': s.titleKana, 'key': normalize(s.titleKana!), 'folded': foldKana(normalize(s.titleKana!)), 'field': '读音', 'weight': .9},
        for (final alias in s.aliases) {'text': alias, 'key': normalize(alias), 'folded': foldKana(normalize(alias)), 'field': '别名', 'weight': 1},
      ]}).toList(),
      'orders': orders,
      'releaseOrder': releaseOrder,
      'rows': [...kanaRows.keys, 'A~G', 'H~N', 'O~U', 'V~Z', 'その他'],
      'searchFixtures': {for (final q in queries) q: engine.search(q).map((h) => h.song.id).toList()},
    };
    await File('D:/WorkBuddy space/outputs/songquery-sort-data.json').writeAsString(jsonEncode(payload));
    expect(data.songs.length, 1112);
  });
}
