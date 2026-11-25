import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/theme.dart';

// 文字可见性修复不得变换原品牌色板。
void main() {
  test('品牌洋红保留原值', () {
    expect(AppPalette.magenta, const Color(0xFFE84A92));
  });

  for (final brightness in Brightness.values) {
    test('主题 $brightness 使用原洋红与既有标签色', () {
      final theme = buildTheme('official', brightness: brightness);
      const expected = Color(0xFFE84A92);
      expect(theme.colorScheme.primary, expected);
      expect(theme.chipTheme.selectedColor, expected);
      expect(
          theme.chipTheme.labelStyle!.color,
          brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF111111));
      expect(theme.chipTheme.labelStyle, isNot(isA<WidgetStateTextStyle>()));
      expect(theme.chipTheme.secondaryLabelStyle!.color, Colors.white);
      expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve({}), expected);
      expect(theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          expected);
      expect(theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
          Colors.white);
    });

    testWidgets('标题 $brightness 保留原洋红', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme('official', brightness: brightness),
        home: const Scaffold(body: AppSectionTitle('分类')),
      ));
      expect(tester.widget<Text>(find.text('分类')).style!.color,
          const Color(0xFFE84A92));
    });
  }
}
