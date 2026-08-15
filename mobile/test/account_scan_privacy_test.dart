import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:krishisathi/core/network/token_store.dart';

import 'support/test_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sign-out purges queued images before another account can use them',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'krishisathi-account-queue-',
      );
      addTearDown(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temporaryDirectory.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );
      final source = File('${temporaryDirectory.path}/leaf.jpg');
      await source.writeAsBytes(
        image_codec.encodeJpg(image_codec.Image(width: 4, height: 4)),
      );
      final controller = await createTestController(
        tokenStore: _MemoryTokenStore(),
      );
      addTearDown(controller.dispose);

      await controller.queueScan([source.path]);
      final savedPath = controller.queuedScans.single.imagePaths.single;
      expect(await File(savedPath).exists(), isTrue);

      await controller.signOut();

      expect(controller.queuedScans, isEmpty);
      expect(await File(savedPath).exists(), isFalse);
      expect(controller.isAuthenticated, isFalse);
    },
  );
}

class _MemoryTokenStore extends SecureTokenStore {
  @override
  Future<AuthTokens?> read() async => null;

  @override
  Future<void> write(AuthTokens tokens) async {}

  @override
  Future<void> clear() async {}
}
