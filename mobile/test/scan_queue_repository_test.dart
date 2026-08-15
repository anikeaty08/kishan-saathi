import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:krishisathi/features/scan/data/scan_queue_repository.dart';
import 'package:krishisathi/core/storage/private_local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'krishisathi-scan-queue-',
    );
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temporaryDirectory.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('queued images are re-encoded without source metadata', () async {
    final source = File('${temporaryDirectory.path}/source.jpg');
    final image = image_codec.Image(width: 8, height: 8)
      ..setPixelRgb(2, 2, 30, 140, 60);
    final sourceBytes = <int>[
      ...image_codec.encodeJpg(image),
      ...'GPSLatitude=12.9716'.codeUnits,
    ];
    await source.writeAsBytes(sourceBytes);
    final repository = ScanQueueRepository(
      await SharedPreferences.getInstance(),
      privateLocalStore: InMemoryPrivateLocalStore(),
    );

    final queued = await repository.enqueue(sourcePaths: [source.path]);
    final savedBytes = await File(queued.imagePaths.single).readAsBytes();

    expect(savedBytes.take(2), isNot(equals(const [0xFF, 0xD8])));
    expect(String.fromCharCodes(savedBytes), isNot(contains('GPSLatitude')));
    final prepared = await repository.prepareForUpload(queued);
    addTearDown(() => repository.disposePrepared(prepared));
    expect(
      image_codec.decodeJpg(await File(prepared.paths.single).readAsBytes()),
      isNotNull,
    );
  });

  test('clearAll removes queue metadata and every copied image', () async {
    final source = File('${temporaryDirectory.path}/source.jpg');
    await source.writeAsBytes(
      image_codec.encodeJpg(image_codec.Image(width: 4, height: 4)),
    );
    final repository = ScanQueueRepository(
      await SharedPreferences.getInstance(),
      privateLocalStore: InMemoryPrivateLocalStore(),
    );
    final queued = await repository.enqueue(sourcePaths: [source.path]);
    final queuedFile = File(queued.imagePaths.single);
    expect(await queuedFile.exists(), isTrue);

    await repository.clearAll();

    expect(await queuedFile.exists(), isFalse);
    expect(await repository.load(), isEmpty);
  });
}
