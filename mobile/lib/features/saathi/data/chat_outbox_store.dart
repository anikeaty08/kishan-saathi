import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingChatEnvelope {
  const PendingChatEnvelope({
    required this.localId,
    required this.chatId,
    required this.content,
    required this.idempotencyKey,
    required this.createdAt,
    this.turnId,
  });

  final String localId;
  final String chatId;
  final String content;
  final String idempotencyKey;
  final DateTime createdAt;
  final String? turnId;

  PendingChatEnvelope copyWith({String? turnId}) => PendingChatEnvelope(
    localId: localId,
    chatId: chatId,
    content: content,
    idempotencyKey: idempotencyKey,
    createdAt: createdAt,
    turnId: turnId ?? this.turnId,
  );

  Map<String, Object?> toJson() => {
    'local_id': localId,
    'chat_id': chatId,
    'content': content,
    'idempotency_key': idempotencyKey,
    'created_at': createdAt.toUtc().toIso8601String(),
    'turn_id': turnId,
  };

  static PendingChatEnvelope? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
    final localId = value['local_id'];
    final chatId = value['chat_id'];
    final content = value['content'];
    final idempotencyKey = value['idempotency_key'];
    if (createdAt == null ||
        localId is! String ||
        chatId is! String ||
        content is! String ||
        idempotencyKey is! String) {
      return null;
    }
    return PendingChatEnvelope(
      localId: localId,
      chatId: chatId,
      content: content,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt.toLocal(),
      turnId: value['turn_id'] as String?,
    );
  }
}

abstract interface class ChatOutboxStore {
  Future<List<PendingChatEnvelope>> readAll();
  Future<void> upsert(PendingChatEnvelope value);
  Future<void> remove(String localId);
}

class SecureChatOutboxStore implements ChatOutboxStore {
  SecureChatOutboxStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _key = 'krishisathi_chat_outbox_v1';
  final FlutterSecureStorage _storage;
  Future<void> _tail = Future.value();

  @override
  Future<List<PendingChatEnvelope>> readAll() => _serialized(_readAll);

  Future<List<PendingChatEnvelope>> _readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const [];
      return decoded
          .map(PendingChatEnvelope.fromJson)
          .whereType<PendingChatEnvelope>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> upsert(PendingChatEnvelope value) => _serialized(() async {
    final values = await _readAll();
    await _write([
      for (final item in values)
        if (item.localId != value.localId) item,
      value,
    ]);
  });

  @override
  Future<void> remove(String localId) => _serialized(() async {
    if (localId.isEmpty) return;
    final values = await _readAll();
    await _write(
      values.where((item) => item.localId != localId).toList(growable: false),
    );
  });

  Future<void> _write(List<PendingChatEnvelope> values) => _storage.write(
    key: _key,
    value: jsonEncode(values.map((item) => item.toJson()).toList()),
  );

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}

class InMemoryChatOutboxStore implements ChatOutboxStore {
  final Map<String, PendingChatEnvelope> _values = {};

  @override
  Future<List<PendingChatEnvelope>> readAll() async => _values.values.toList();

  @override
  Future<void> upsert(PendingChatEnvelope value) async {
    _values[value.localId] = value;
  }

  @override
  Future<void> remove(String localId) async {
    _values.remove(localId);
  }
}
