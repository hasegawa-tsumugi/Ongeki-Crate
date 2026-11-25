import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/domain.dart';

Song song(String id, {double level = 0, int rank = 3, int? enemy}) => Song(
      id: id,
      title: 'Song $id',
      charts: [
        Chart(
          difficulty: rank,
          level: level.floor(),
          levelDecimal: 0,
          levelValue: level,
          enabled: true,
        ),
      ],
      enemyLevel: enemy,
    );

List<String> ids(SongEngine engine, List<DifficultySort> sorts,
        {SortDirection direction = SortDirection.desc}) =>
    engine
        .list(
          sort: SortKey.difficulty,
          direction: direction,
          difficultySorts: sorts,
        )
        .map((s) => s.id)
        .toList();

void main() {
  test('不传条件时退回「档位 › 谱面等级」', () {
    final engine = SongEngine([
      song('a', rank: 3, level: 15),
      song('b', rank: 4, level: 12),
      song('c', rank: 4, level: 13),
    ]);
    // 档位优先：MASTER 15 排在 LUNATIC 12/13 之后，且与「默认排序」不同序。
    expect(ids(engine, const []), ['c', 'b', 'a']);
  });

  test('档位 + 等级叠加：先比档位，同档位再比等级', () {
    final engine = SongEngine([
      song('a', rank: 3, level: 13),
      song('b', rank: 4, level: 14),
      song('c', rank: 4, level: 15),
    ]);
    expect(
      ids(engine, const [DifficultySort.rank, DifficultySort.level]),
      ['c', 'b', 'a'],
    );
  });

  test('等级 + 对手等级叠加：等级相同才比对手等级', () {
    final engine = SongEngine([
      song('a', level: 13, enemy: 40),
      song('b', level: 13, enemy: 55),
      song('c', level: 12, enemy: 60),
    ]);
    expect(
      ids(engine, const [DifficultySort.level, DifficultySort.enemyLevel]),
      ['b', 'a', 'c'],
    );
  });

  test('对手等级缺失按最低值处理，降序时排最后', () {
    final engine = SongEngine([
      song('a', level: 12),
      song('b', level: 12, enemy: 30),
    ]);
    expect(
      ids(engine, const [DifficultySort.enemyLevel]),
      ['b', 'a'],
    );
  });

  test('三种条件全部叠加时逐级比较', () {
    final engine = SongEngine([
      song('a', rank: 4, level: 14, enemy: 50),
      song('b', rank: 4, level: 14, enemy: 60),
      song('c', rank: 4, level: 13, enemy: 99),
      song('d', rank: 5, level: 15, enemy: 10),
    ]);
    expect(
      ids(engine, const [
        DifficultySort.rank,
        DifficultySort.level,
        DifficultySort.enemyLevel,
      ]),
      ['d', 'b', 'a', 'c'],
    );
  });
}
