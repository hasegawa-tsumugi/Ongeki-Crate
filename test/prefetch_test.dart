import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songquery_flutter/src/prefetch.dart';

void main() {
  group('PrefetchQueue', () {
    test('never runs more than maxConcurrent loads at once', () async {
      var active = 0;
      var peak = 0;
      final gate = Completer<void>();
      final queue = PrefetchQueue(
        maxConcurrent: 2,
        retryDelay: Duration.zero,
        load: (_) async {
          active++;
          if (active > peak) peak = active;
          await gate.future;
          active--;
        },
      );

      queue.prefetch(['a', 'b', 'c', 'd', 'e', 'f']);
      // 只起了 2 个，剩下 4 个在排队 —— 这条就是当初真机炸掉的护栏。
      expect(queue.active, 2);
      expect(queue.pending, 4);

      gate.complete();
      await pumpEventQueue();
      expect(peak, 2);
      expect(queue.active, 0);
      expect(queue.pending, 0);
    });

    test('dedupes by artwork, including across separate calls', () async {
      final loaded = <String>[];
      final queue = PrefetchQueue(
        maxConcurrent: 4,
        retryDelay: Duration.zero,
        load: (artwork) async => loaded.add(artwork),
      );

      queue.prefetch(['a', 'b', 'a']);
      await pumpEventQueue();
      queue.prefetch(['b', 'c']);
      await pumpEventQueue();

      expect(loaded, ['a', 'b', 'c']);
      expect(queue.seen, {'a', 'b', 'c'});
    });

    test('skips null and empty artwork', () async {
      final loaded = <String>[];
      final queue = PrefetchQueue(
        retryDelay: Duration.zero,
        load: (artwork) async => loaded.add(artwork),
      );

      queue.prefetch([null, '', 'x']);
      await pumpEventQueue();
      expect(loaded, ['x']);
      expect(queue.seen, {'x'});
    });

    test('retries maxAttempts times then swallows the failure', () async {
      var attempts = 0;
      final queue = PrefetchQueue(
        maxAttempts: 2,
        retryDelay: Duration.zero,
        load: (_) async {
          attempts++;
          throw StateError('boom');
        },
      );

      queue.prefetch(['a']);
      await pumpEventQueue();
      // 预取是纯优化：失败不外抛，但要按次数重试。
      expect(attempts, 2);
      expect(queue.active, 0);
    });

    test('recovers when a later attempt succeeds', () async {
      var attempts = 0;
      final queue = PrefetchQueue(
        maxAttempts: 3,
        maxConcurrent: 1,
        retryDelay: Duration.zero,
        load: (_) async {
          attempts++;
          if (attempts < 3) throw StateError('flaky');
        },
      );

      queue.prefetch(['a', 'b']);
      await pumpEventQueue();
      // a 试了 3 次，b 一次过。
      expect(attempts, 4);
    });

    test('dispose stops the queue from starting more work', () async {
      final started = <String>[];
      final gate = Completer<void>();
      final queue = PrefetchQueue(
        maxConcurrent: 1,
        retryDelay: Duration.zero,
        load: (artwork) async {
          started.add(artwork);
          await gate.future;
        },
      );

      queue.prefetch(['a', 'b', 'c']);
      expect(started, ['a']);
      queue.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(started, ['a']);
      expect(queue.pending, 0);
    });

    test('ignores prefetch after dispose', () async {
      final loaded = <String>[];
      final queue = PrefetchQueue(
        retryDelay: Duration.zero,
        load: (artwork) async => loaded.add(artwork),
      );

      queue.dispose();
      queue.prefetch(['a']);
      await pumpEventQueue();
      expect(loaded, isEmpty);
    });

    test('waits retryDelay between attempts when it is non-zero', () {
      // 以前每条用例都用 Duration.zero，`retryDelay > Duration.zero` 那条等待
      // 从没真正等到过 —— 真机上重试间隔是 1500ms，不是「立刻再试」。
      var attempts = 0;
      fakeAsync((async) {
        final queue = PrefetchQueue(
          maxAttempts: 2,
          retryDelay: const Duration(milliseconds: 1500),
          load: (_) async {
            attempts++;
            throw StateError('boom');
          },
        );
        queue.prefetch(['a']);
        async.flushMicrotasks();
        // 第一次失败后卡在等待里，还没开始第二次。
        expect(attempts, 1);
        async.elapse(const Duration(milliseconds: 1499));
        expect(attempts, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(attempts, 2);
        async.flushMicrotasks();
        expect(queue.active, 0);
      });
    });
  });
}
