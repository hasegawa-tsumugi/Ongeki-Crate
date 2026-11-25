import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/app.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/theme.dart';

// 分类文字直接使用原色板，不随主题压暗或变换。
void main() {
  const original = {
    '01': 0xFFFF0066,
    '02': 0xFFFFD822,
    '03': 0xFFCF3EFF,
    '04': 0xFF00C312,
    '05': 0xFF42B6FF,
    '06': 0xFFFF7DAB,
  };

  test('分类色板保留全部原值', () {
    expect(genreColors, original);
  });

  for (final brightness in Brightness.values) {
    testWidgets('卡片 $brightness 分类文字保持原值及洋红回退', (tester) async {
      for (final entry in {...original, 'unknown': 0xFFE84A92}.entries) {
        final song = Song.fromJson({
          'id': 'palette-${entry.key}',
          'title': '测试曲目',
          'genre': '分类-${entry.key}',
          'genreId': entry.key,
          'charts': <dynamic>[],
        });
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme('system', brightness: brightness),
          home: Scaffold(
              body: SingleChildScrollView(
            child: SongCardView(song: song, onTap: () {}),
          )),
        ));
        expect(tester.widget<Text>(find.text(song.genre!)).style!.color,
            Color(entry.value),
            reason: '分类 ${entry.key} 不应被变换');
      }
    });
  }
}
