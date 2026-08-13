import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';

class ScanQueueRepository {
  ScanQueueRepository(this._preferences);

  static const _key = 'durable_scan_queue_v1';

  final SharedPreferences _preferences;
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
            (scan) => scan.imagePaths.every((path) => File(path).existsSync()),
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
          '${folder.path}${Platform.pathSeparator}leaf_${index + 1}.jpg',
        );
        await source.copy(target.path);
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
