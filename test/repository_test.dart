import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songquery_flutter/src/domain.dart';
import 'package:songquery_flutter/src/repository.dart';

/// 造一份「够大」的本地曲库（_decodeStored 要求 ≥500 首）。
Dataset localDataset({int count = 600, String prefix = 'LOCAL'}) => Dataset(
      [
        for (var i = 0; i < count; i++)
          Song(
            id: '${100000 + i}',
            title: '$prefix-$i',
            charts: const [],
          ),
      ],
    );

/// 造一份上游格式（music-ex.json 形状）的数据。
List<Map<String, dynamic>> upstreamRows({
  int count = 600,
  String prefix = 'UP',
}) =>
    [
      for (var i = 0; i < count; i++)
        {
          'id': '${200000 + i}',
          'title': '$prefix-$i',
          'title_sort': '$prefix-$i',
          'lev_bas': '1',
          'lev_bas_i': 10,
        },
    ];

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('songquery-repo-');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  SongRepository repo(http.Client client) =>
      SongRepository(client: client, documentsDir: () async => tmp);

  File target() => File('${tmp.path}/dataset/songs.json');
  File backup() => File('${tmp.path}/dataset/songs.json.bak');
  File staging() => File('${tmp.path}/dataset/songs.json.tmp');
  File etagFile() => File('${tmp.path}/dataset/songs.json.etag');

  Future<void> seedLocal(Dataset ds) async {
    await Directory('${tmp.path}/dataset').create(recursive: true);
    await target().writeAsString(jsonEncode(ds.toJson()));
  }

  /// 直接落一段 JSON —— 用来造「旧版本写下的文件」（没有 `schema` 戳）。
  Future<void> seedLocalRaw(String json) async {
    await Directory('${tmp.path}/dataset').create(recursive: true);
    await target().writeAsString(json);
  }

  http.Client serving(Object body, {int status = 200}) => MockClient(
        (_) async => http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

  /// 记录请求方法，并按 HEAD / GET 分别作答。
  http.Client withEtag(
    List<String> methods, {
    String? headEtag,
    int headStatus = 200,
    String? getEtag,
  }) =>
      MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'HEAD') {
          return http.Response(
            '',
            headStatus,
            headers: headEtag == null ? {} : {'etag': headEtag},
          );
        }
        return http.Response(
          jsonEncode(upstreamRows()),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            if (getEtag != null) 'etag': getEtag,
          },
        );
      });

  /// 侧车文件现在是两行：产出 ETag 的线路 + ETag 本身。旧格式只有一行。
  Future<(String url, String etag)> probe() async {
    final lines = await etagFile().readAsLines();
    return lines.length >= 2
        ? (lines.first, lines.last)
        : (dataBases.first, lines.first);
  }

  /// 只在指定线路上应答，其余线路 404 —— 用来验证 HEAD / GET 打的是哪一条。
  http.Client etagOnHost(
    List<String> methods, {
    required String host,
    required String etag,
  }) =>
      MockClient((request) async {
        methods.add(request.method);
        // HEAD 和 GET 都要拦：只拦 HEAD 的话下载仍会砸在第一条线路上，
        // 「存的是哪条线路」就测不出来（第一版就这么写错了）。
        if (request.url.toString() != host) {
          return http.Response('', 404);
        }
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: {'etag': etag});
        }
        return http.Response(
          jsonEncode(upstreamRows()),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'etag': etag,
          },
        );
      });

  group('etag negotiation', () {
    test('skips the download when the upstream etag is unchanged', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        withEtag(methods, headEtag: '"v1"'),
      ).fetchAndInstall();

      // 只有一次 HEAD，没有 GET —— 这就是省掉的 1.6MB。
      expect(methods, ['HEAD']);
      expect(ds.songs.first.title, 'KEEP-0');
      expect((await probe()).$2, '"v1"');
    });

    test('downloads and rewrites the marker when the etag moved', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        withEtag(methods, headEtag: '"v2"', getEtag: '"v2"'),
      ).fetchAndInstall();

      expect(methods, ['HEAD', 'GET']);
      expect(ds.songs.first.title, 'UP-0');
      expect((await probe()).$2, '"v2"');
    });

    test('fetches without probing when nothing was recorded yet', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      final methods = <String>[];

      await repo(withEtag(methods, getEtag: '"v1"')).fetchAndInstall();

      expect(methods, ['GET']);
      expect((await probe()).$2, '"v1"');
    });

    test('records which mirror produced the etag', () async {
      // 各家 ETag 口径不同：jsDelivr 发弱 ETag，raw.githubusercontent 发强哈希。
      // 存下来的时候必须连线路一起记，否则下次 HEAD 拿第一条线路去比，永远对不上。
      final methods = <String>[];
      await repo(etagOnHost(methods, host: dataBases[1], etag: '"g1"'))
          .fetchAndInstall();

      final saved = await probe();
      expect(saved.$1, dataBases[1]);
      expect(saved.$2, '"g1"');
    });

    test('probes the mirror that produced the etag, not the first one', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      // 上次是回退线路装成功的。
      await etagFile().writeAsString('${dataBases[1]}\n"g1"');
      final methods = <String>[];

      final ds = await repo(
        etagOnHost(methods, host: dataBases[1], etag: '"g1"'),
      ).fetchAndInstall();

      // 如果去 HEAD 第一条线路会拿到 404，于是白下一次 —— 这条断言就是防这个。
      expect(methods, ['HEAD']);
      expect(ds.songs.first.title, 'KEEP-0');
    });

    test('downloads when the recorded mirror is gone', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('${dataBases[1]}\n"g1"');
      final methods = <String>[];

      // 只有第一条线路在应答，被记录的那条 404。
      final ds = await repo(
        etagOnHost(methods, host: dataBases.first, etag: '"g1"'),
      ).fetchAndInstall();

      expect(methods, ['HEAD', 'GET']);
      expect(ds.songs.first.title, 'UP-0');
    });

    test('a legacy single-line marker still probes the first mirror', () async {
      // 老版本只写了 ETag 一行，升级后不能因为解析不出来就每次重下。
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        etagOnHost(methods, host: dataBases.first, etag: '"v1"'),
      ).fetchAndInstall();

      expect(methods, ['HEAD']);
      expect(ds.songs.first.title, 'KEEP-0');
    });

    test('falls back to a download when the probe fails', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        withEtag(methods, headEtag: '"v1"', headStatus: 503),
      ).fetchAndInstall();

      // HEAD 挂了不能当成「没变」，否则永远收不到新曲库。
      expect(methods, ['HEAD', 'GET']);
      expect(ds.songs.first.title, 'UP-0');
    });

    test('ignores an upstream that sends no etag at all', () async {
      await seedLocal(localDataset(prefix: 'KEEP'));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      await repo(withEtag(methods, headEtag: null)).fetchAndInstall();

      expect(methods, ['HEAD', 'GET']);
    });

    test('downloads when the etag matches but the local copy is gone',
        () async {
      await Directory('${tmp.path}/dataset').create(recursive: true);
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        withEtag(methods, headEtag: '"v1"', getEtag: '"v1"'),
      ).fetchAndInstall();

      expect(methods, ['HEAD', 'GET']);
      expect(ds.songs.first.title, 'UP-0');
    });

    test('clear removes the marker along with the data', () async {
      await seedLocal(localDataset());
      await etagFile().writeAsString('"v1"');

      await repo(serving('')).clear();
      expect(await etagFile().exists(), isFalse);
    });
  });

  group('install', () {
    test('rejects a stored dataset with no schema stamp', () async {
      // 旧版本写下的文件结构合法、条数也够，只是某些值算错了。
      // 没有版本戳 → 一律当不可用，宁可重下一次。
      final stale = localDataset().toJson();
      (stale['meta'] as Map<String, dynamic>).remove('schema');
      await seedLocalRaw(jsonEncode(stale));

      expect(await repo(serving('')).loadLocal(), isNull);
    });

    test('repairs a stale local dataset even when the etag says unchanged',
        () async {
      // **这条是「坏数据能不能自愈」的护栏**：旧版本装下的定数是错的（1.1 而不是
      // 11.8），但文件本身挑不出毛病。而 ETag 协商在「上游没变」时会直接返回本地
      // 数据 —— 不按版本戳拒绝它，这份坏数据就永远不会被修好。
      final stale = localDataset(prefix: 'STALE').toJson();
      (stale['meta'] as Map<String, dynamic>).remove('schema');
      await seedLocalRaw(jsonEncode(stale));
      await etagFile().writeAsString('"v1"');
      final methods = <String>[];

      final ds = await repo(
        withEtag(methods, headEtag: '"v1"', getEtag: '"v1"'),
      ).fetchAndInstall();

      expect(methods, ['HEAD', 'GET'], reason: '版本不符必须重下，不能信 ETag');
      expect(ds.songs.first.title, 'UP-0');
      // 重装后文件也带上新版本戳，下次不会再被判为过期。
      final stored = jsonDecode(await target().readAsString());
      expect((stored['meta'] as Map)['schema'], datasetSchemaVersion);
    });

    test('promotes the downloaded snapshot and drops the backup', () async {
      await seedLocal(localDataset());
      final progress = <int>[];
      final ds = await repo(serving(upstreamRows())).fetchAndInstall(
        onProgress: (done, total, _) => progress.add(done),
      );

      expect(ds.songs.length, 600);
      expect(
          jsonDecode(await target().readAsString())['songs'], hasLength(600));
      expect(
          (jsonDecode(await target().readAsString())['songs'][0]
              as Map)['title'],
          'UP-0');
      // 备份和暂存都不该残留，否则下次 _recoverInterruptedInstall 会误判。
      expect(await backup().exists(), isFalse);
      expect(await staging().exists(), isFalse);
      // 进度必须是单调递增的，UI 的进度条直接吃这个数。
      expect(progress, isNotEmpty);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('keeps the local snapshot when every mirror fails', () async {
      final before = localDataset();
      await seedLocal(before);
      final r = repo(serving('', status: 503));

      await expectLater(r.fetchAndInstall(), throwsA(isA<Exception>()));
      // 关键：失败不能动本地文件。
      final after = jsonDecode(await target().readAsString());
      expect((after['songs'] as List), hasLength(600));
      expect((after['songs'][0] as Map)['title'], 'LOCAL-0');
      expect(await backup().exists(), isFalse);
      expect(await staging().exists(), isFalse);
    });

    test('falls through the mirror list in order until one answers', () async {
      await seedLocal(localDataset());
      final hits = <String>[];
      final client = MockClient((request) async {
        hits.add(request.url.toString());
        // 前两条线路挂掉，第三条才给数据。
        if (hits.length < 3) return http.Response('', 500);
        return http.Response(
          jsonEncode(upstreamRows()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await repo(client).fetchAndInstall();
      expect(hits, hasLength(3));
      expect(hits[0], contains('fastly'));
      expect(hits[1], contains('cdn.jsdelivr'));
      expect(hits[2], contains('gcore'));
    });

    test('refuses a snapshot with too few songs and keeps the old data',
        () async {
      await seedLocal(localDataset());
      await expectLater(
        repo(serving(upstreamRows(count: 10))).fetchAndInstall(),
        throwsA(isA<Exception>()),
      );
      final after = jsonDecode(await target().readAsString());
      expect((after['songs'] as List), hasLength(600));
      expect((after['songs'][0] as Map)['title'], 'LOCAL-0');
    });

    test('does not retry other mirrors when the payload is malformed', () async {
      // 字段改名是**数据本身**坏了，换条线路下的还是同一份文件。继续试剩下三条
      // 只会白下 4.8MB，而且末尾那句「所有曲库线路均失败」会把真实原因埋掉。
      await seedLocal(localDataset());
      final hits = <String>[];
      final client = MockClient((request) async {
        hits.add(request.url.toString());
        final rows = upstreamRows()
          ..forEach((r) => r['lev_basic'] = r.remove('lev_bas'));
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await expectLater(
        repo(client).fetchAndInstall(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('已保留本地曲库'),
          ),
        ),
      );
      expect(hits, hasLength(1), reason: '格式错误不该换线路重试');
      final after = jsonDecode(await target().readAsString());
      expect((after['songs'] as List), hasLength(600));
      expect(await staging().exists(), isFalse);
    });

    test('retries the next mirror when the body is truncated json', () async {
      // 截断是**传输**问题，换条线路可能就好了 —— 不能和「字段改名」一起判死。
      await seedLocal(localDataset());
      final hits = <String>[];
      final client = MockClient((request) async {
        hits.add(request.url.toString());
        if (hits.length == 1) {
          return http.Response('{"songs": [{"id": "1", "tit', 200);
        }
        return http.Response(
          jsonEncode(upstreamRows()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final ds = await repo(client).fetchAndInstall();
      expect(hits, hasLength(2));
      expect(ds.songs.first.title, 'UP-0');
    });

    test('aborts cleanly when the response stream breaks mid-flight', () async {
      await seedLocal(localDataset());
      final client = MockClient.streaming((request, _) async {
        final controller = StreamController<List<int>>();
        controller
            .add(utf8.encode(jsonEncode(upstreamRows()).substring(0, 900)));
        // 模拟断流：既不 close 也不 done，直接抛。
        scheduleMicrotask(() => controller.addError(
              const SocketException('connection reset'),
            ));
        return http.StreamedResponse(controller.stream, 200);
      });

      await expectLater(
        repo(client).fetchAndInstall(),
        throwsA(isA<Exception>()),
      );
      final after = jsonDecode(await target().readAsString());
      expect((after['songs'][0] as Map)['title'], 'LOCAL-0');
      expect(await staging().exists(), isFalse);
    });

    test('does not touch the local file when there is none yet', () async {
      final ds = await repo(serving(upstreamRows())).fetchAndInstall();
      expect(ds.songs.length, 600);
      expect(await target().exists(), isTrue);
    });
  });

  group('interrupted install recovery', () {
    test('restores the backup when the target vanished', () async {
      await seedLocal(localDataset(prefix: 'BAK'));
      await target().rename(backup().path); // 只剩备份：rename 到一半断电
      expect(await target().exists(), isFalse);

      final loaded = await repo(serving('')).loadLocal();
      expect(loaded, isNotNull);
      expect(loaded!.songs.first.title, 'BAK-0');
      expect(await target().exists(), isTrue);
      expect(await backup().exists(), isFalse);
    });

    test('keeps a valid target and discards the stale backup', () async {
      await seedLocal(localDataset(prefix: 'GOOD'));
      await backup().writeAsString(
        jsonEncode(localDataset(prefix: 'STALE').toJson()),
      );

      final loaded = await repo(serving('')).loadLocal();
      expect(loaded!.songs.first.title, 'GOOD-0');
      expect(await backup().exists(), isFalse);
    });

    test('rolls back to the backup when the target is corrupt', () async {
      await seedLocal(localDataset(prefix: 'BAK'));
      await backup().writeAsString(
        jsonEncode(localDataset(prefix: 'BAK').toJson()),
      );
      await target().writeAsString('{"songs": "not a list"}');

      final loaded = await repo(serving('')).loadLocal();
      expect(loaded, isNotNull);
      expect(loaded!.songs.first.title, 'BAK-0');
      expect(await target().exists(), isTrue);
    });

    test('rejects a target with too few songs and rolls back', () async {
      await Directory('${tmp.path}/dataset').create(recursive: true);
      await backup().writeAsString(
        jsonEncode(localDataset(prefix: 'BAK').toJson()),
      );
      await target().writeAsString(
        jsonEncode(localDataset(count: 3, prefix: 'TINY').toJson()),
      );

      final loaded = await repo(serving('')).loadLocal();
      expect(loaded!.songs.first.title, 'BAK-0');
    });

    test('returns null when neither target nor backup exists', () async {
      expect(await repo(serving('')).loadLocal(), isNull);
    });
  });

  group('misc', () {
    test('clear removes target, backup and staging', () async {
      await seedLocal(localDataset());
      await backup().writeAsString('{}');
      await staging().writeAsString('{}');

      await repo(serving('')).clear();
      expect(await target().exists(), isFalse);
      expect(await backup().exists(), isFalse);
      expect(await staging().exists(), isFalse);
    });

    test('localBytes and etag degrade to 0 and empty when absent', () async {
      final r = repo(serving(''));
      expect(await r.localBytes(), 0);
      expect(await r.etag(), '');
    });

    test('etag is the sha256 of the stored file', () async {
      await seedLocal(localDataset());
      final expected = await target().readAsBytes();
      final hash = await repo(serving('')).etag();
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash.length, 64);
      expect(expected.length, greaterThan(0));
    });
  });
}
