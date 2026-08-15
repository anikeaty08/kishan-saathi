import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image_codec;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/private_local_store.dart';
import 'queued_scan_cipher.dart';

class ScanQueueRepository {
  ScanQueueRepository(
    this._preferences, {
    required PrivateLocalStore privateLocalStore,
  }) : _cipher = QueuedScanCipher(privateLocalStore);

  static const _key = 'durable_scan_queue_v1';

  final SharedPreferences _preferences;
  final QueuedScanCipher _cipher;
  final _uuid = const Uuid();

  Future<List<QueuedScanModel>> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw);
      if (values is! List<dynamic>) return const [];
      final scans = values
          .whereType<Map<String, dynamic>>()
          .map(_decode)
          .where(
            (scan) => scan.imagePaths.every(
              (path) => path.endsWith('.ksq') && File(path).existsSync(),
            ),
          )
          .toList(growable: false);
      await _persist(scans);
      return scans;
    } on FormatException catch (_) {
      await _preferences.remove(_key);
      return const [];
    } on TypeError catch (_) {
      await _preferences.remove(_key);
      return const [];
    }
  }

  Future<QueuedScanModel> enqueue({
    required List<String> sourcePaths,
    String? cropName,
    String? plotId,
  }) async {
    if (sourcePaths.isEmpty) {
      throw const ApiException(
        code: 'SCAN_IMAGES_REQUIRED',
        message: 'Add at least one leaf image',
      );
    }
    final root = await getApplicationSupportDirectory();
    final id = _uuid.v4();
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}queued_scans${Platform.pathSeparator}$id',
    );
    await folder.create(recursive: true);
    final saved = <String>[];
    try {
      for (var index = 0; index < sourcePaths.length; index++) {
        final source = File(sourcePaths[index]);
        if (!await source.exists()) {
          throw const ApiException(
            code: 'SCAN_IMAGE_MISSING',
            message: 'One selected image is no longer available',
          );
        }
        final target = File(
          '${folder.path}${Platform.pathSeparator}leaf_${index + 1}.ksq',
        );
        final sourceLength = await source.length();
        if (sourceLength > 25 * 1024 * 1024) {
          throw const ApiException(
            code: 'SCAN_IMAGE_TOO_LARGE',
            message: 'One selected photo is too large',
          );
        }
        final decoded = image_codec.decodeImage(await source.readAsBytes());
        if (decoded == null) {
          throw const ApiException(
            code: 'SCAN_IMAGE_INVALID',
            message: 'One selected file is not a readable image',
          );
        }
        var sanitized = image_codec.bakeOrientation(decoded);
        if (sanitized.width > 2048 || sanitized.height > 2048) {
          sanitized = image_codec.copyResize(
            sanitized,
            width: sanitized.width >= sanitized.height ? 2048 : null,
            height: sanitized.height > sanitized.width ? 2048 : null,
            interpolation: image_codec.Interpolation.average,
          );
        }
        // Re-encoding removes EXIF/GPS and normalizes the queued file.
        final sanitizedBytes = image_codec.encodeJpg(sanitized, quality: 90);
        await target.writeAsBytes(
          await _cipher.encrypt(sanitizedBytes),
          flush: true,
        );
        saved.add(target.path);
      }
      final scan = QueuedScanModel(
        id: id,
        imagePaths: saved,
        cropName: _text(cropName),
        plotId: plotId,
        createdAt: DateTime.now(),
      );
      final current = await load();
      await _persist([scan, ...current]);
      return scan;
    } on ApiException {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    } on FileSystemException {
      if (await folder.exists()) await folder.delete(recursive: true);
      throw const ApiException(
        code: 'SCAN_QUEUE_WRITE_FAILED',
        message: 'The photos could not be saved on this phone',
      );
    }
  }

  Future<void> remove(String id) async {
    final current = await load();
    final target = current.cast<QueuedScanModel?>().firstWhere(
      (scan) => scan?.id == id,
      orElse: () => null,
    );
    try {
      if (target != null && target.imagePaths.isNotEmpty) {
        final folder = File(target.imagePaths.first).parent;
        if (await folder.exists()) await folder.delete(recursive: true);
      }
    } on FileSystemException {
      throw const ApiException(
        code: 'SCAN_QUEUE_DELETE_FAILED',
        message: 'The saved scan could not be removed from this phone',
      );
    }
    await _persist(current.where((scan) => scan.id != id).toList());
  }

  Future<PreparedQueuedScanImages> prepareForUpload(
    QueuedScanModel scan,
  ) async {
    final temporaryRoot = await getTemporaryDirectory();
    final folder = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}krishisathi_upload_${scan.id}',
    );
    await folder.create(recursive: true);
    final paths = <String>[];
    try {
      for (var index = 0; index < scan.imagePaths.length; index++) {
        final encryptedFile = File(scan.imagePaths[index]);
        if (!await encryptedFile.exists()) {
          throw const ApiException(
            code: 'SCAN_IMAGE_MISSING',
            message: 'One saved image is no longer available',
          );
        }
        final clearBytes = await _cipher.decrypt(
          await encryptedFile.readAsBytes(),
        );
        final target = File(
          '${folder.path}${Platform.pathSeparator}leaf_${index + 1}.jpg',
        );
        await target.writeAsBytes(clearBytes, flush: true);
        paths.add(target.path);
      }
      return PreparedQueuedScanImages(
        paths: paths,
        temporaryDirectory: folder.path,
      );
    } on ApiException {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    } on FileSystemException {
      if (await folder.exists()) await folder.delete(recursive: true);
      throw const ApiException(
        code: 'SCAN_QUEUE_READ_FAILED',
        message: 'A saved scan could not be opened from this phone',
      );
    }
  }

  Future<void> disposePrepared(PreparedQueuedScanImages prepared) async {
    final folder = Directory(prepared.temporaryDirectory);
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// Deletes every queued scan and its copied images.
  ///
  /// Sign-out calls this before another farmer can use the device, preventing
  /// account A's private images from being submitted under account B.
  Future<void> clearAll() async {
    Object? deletionFailure;
    try {
      final root = await getApplicationSupportDirectory();
      final folder = Directory(
        '${root.path}${Platform.pathSeparator}queued_scans',
      );
      if (await folder.exists()) await folder.delete(recursive: true);
    } on FileSystemException catch (error) {
      deletionFailure = error;
    } finally {
      // Even if the OS temporarily refuses file deletion, remove queue
      // metadata so no later account can discover or upload those files.
      await _preferences.remove(_key);
    }
    if (deletionFailure != null) {
      throw const ApiException(
        code: 'SCAN_QUEUE_DELETE_FAILED',
        message: 'Saved scans could not be removed from this phone',
      );
    }
  }

  Future<void> _persist(List<QueuedScanModel> scans) =>
      _preferences.setString(_key, jsonEncode(scans.map(_encode).toList()));
}

QueuedScanModel _decode(Map<String, dynamic> row) => QueuedScanModel(
  id: row['id'] as String,
  imagePaths: (row['image_paths'] as List<dynamic>)
      .whereType<String>()
      .toList(),
  createdAt:
      DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
  cropName: row['crop_name'] as String?,
  plotId: row['plot_id'] as String?,
);

Map<String, Object?> _encode(QueuedScanModel scan) => {
  'id': scan.id,
  'image_paths': scan.imagePaths,
  'created_at': scan.createdAt.toIso8601String(),
  'crop_name': scan.cropName,
  'plot_id': scan.plotId,
};

String? _text(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
