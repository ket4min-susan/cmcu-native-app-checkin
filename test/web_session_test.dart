import 'dart:async';

import 'package:cmc_checkin/core/web_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _WebSessionPlatform extends InAppWebViewPlatform {
  final calls = <String>[];
  Completer<void>? cookiesCleared;
  bool cacheFails = false;
  Set<WebsiteDataType>? dataTypes;
  DateTime? since;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params, this);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Cache(this);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => _Storage(params, this);
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.owner) : super.implementation();
  final _WebSessionPlatform owner;

  @override
  Future<bool> deleteAllCookies() async {
    owner.calls.add('cookies');
    await owner.cookiesCleared?.future;
    return false; // Android báo false khi cookie store đã rỗng.
  }
}

class _Cache extends PlatformInAppWebViewController {
  _Cache(this.owner)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'static'),
      );
  final _WebSessionPlatform owner;

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {
    owner.calls.add('cache');
    if (owner.cacheFails) throw StateError('synthetic cache failure');
  }

  @override
  Future<String> getDefaultUserAgent() async => 'default-test-user-agent';
}

class _Storage extends PlatformWebStorageManager {
  _Storage(super.params, this.owner) : super.implementation();
  final _WebSessionPlatform owner;

  @override
  Future<void> deleteAllData() async => owner.calls.add('android-storage');

  @override
  Future<void> removeDataModifiedSince({
    required Set<WebsiteDataType> dataTypes,
    required DateTime date,
  }) async {
    owner.calls.add('apple-storage');
    owner.dataTypes = dataTypes;
    owner.since = date;
  }
}

void main() {
  final platform = _WebSessionPlatform();
  setUp(() {
    InAppWebViewPlatform.instance = platform;
    platform.calls.clear();
    platform.cookiesCleared = null;
    platform.cacheFails = false;
    platform.dataTypes = null;
    platform.since = null;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final target in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    test(
      'Clears cookies, cache and correct website storage on ${target.name}',
      () async {
        debugDefaultTargetPlatformOverride = target;
        await WebSession.clearAll();
        final apple = target != TargetPlatform.android;
        expect(
          platform.calls,
          containsAll([
            'cookies',
            'cache',
            apple ? 'apple-storage' : 'android-storage',
          ]),
        );
        expect(
          platform.calls,
          isNot(contains(apple ? 'android-storage' : 'apple-storage')),
        );
        if (apple) {
          expect(platform.dataTypes, WebsiteDataType.ALL);
          expect(platform.since, DateTime.fromMillisecondsSinceEpoch(0));
        }
      },
    );
  }

  test('Waits for cookie removal before completing reset', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform.cookiesCleared = Completer<void>();
    var finished = false;
    final reset = WebSession.clearAll().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    platform.cookiesCleared!.complete();
    await reset;
    expect(finished, isTrue);
  });

  test(
    'Does not suppress cache failure and still removes cookie/storage',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform.cacheFails = true;
      await expectLater(WebSession.clearAll(), throwsStateError);
      expect(
        platform.calls,
        containsAll(['cookies', 'cache', 'apple-storage']),
      );
    },
  );

  test(
    'Uses captured page UA and forgets it when session is cleared',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await WebSession.rememberUserAgent('captured-test-user-agent');
      expect(await WebSession.userAgent(), 'captured-test-user-agent');
      await WebSession.rememberUserAgent('');
      expect(await WebSession.userAgent(), 'captured-test-user-agent');
      await WebSession.clearAll();
      expect(await WebSession.userAgent(), 'default-test-user-agent');
    },
  );
}
