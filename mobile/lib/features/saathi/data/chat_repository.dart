import 'package:uuid/uuid.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class CreateChatCommand {
  const CreateChatCommand({
    required this.scope,
    this.farmId,
    this.plotId,
    this.diagnosisCaseId,
  });

  final String scope;
  final String? farmId;
  final String? plotId;
  final String? diagnosisCaseId;
}

class ChatRepository {
  const ChatRepository(this._api);

  final KrishiApi _api;

  Future<List<ChatThreadModel>> loadChats() async {
    final payload = await _api.listChats();
    return _list(
      payload,
      contract: 'chats',
    ).map(_thread).toList(growable: false);
  }

  Future<ChatThreadModel> createChat(CreateChatCommand command) async {
    final payload = await _api.createChat({
      'scope_type': command.scope,
      if (command.farmId != null) 'farm_id': command.farmId,
      if (command.plotId != null) 'plot_id': command.plotId,
      if (command.diagnosisCaseId != null)
        'diagnosis_case_id': command.diagnosisCaseId,
    });
    return _thread(_map(payload, contract: 'chat'));
  }

  Future<ChatThreadModel> loadChat(String id) async {
    final payload = await _api.getChat(id);
    final row = _map(payload, contract: 'chat');
    final messages = switch (row['messages']) {
      final List<dynamic> values =>
        values
            .whereType<Map<String, dynamic>>()
            .map(_message)
            .toList(growable: false),
      _ => const <ChatMessageModel>[],
    };
    return _thread(row).copyWith(messages: messages);
  }

  Future<List<ChatMessageModel>> sendMessage(String id, String content) async {
    final payload = await _api.sendChatMessage(id, {
      'content': content.trim(),
    }, idempotencyKey: const Uuid().v4());
    final row = _map(payload, contract: 'chat message');
    return [
      _message(_map(row['user_message'], contract: 'user message')),
      _message(_map(row['assistant_message'], contract: 'assistant message')),
    ];
  }

  Future<ChatThreadModel> updateChat(
    ChatThreadModel chat, {
    String? title,
    bool? archived,
  }) async {
    final payload = await _api.updateChat(chat.id, {
      'title': ?title?.trim(),
      'archived': ?archived,
    });
    return _thread(_map(payload, contract: 'chat'))
        .copyWith(messages: chat.messages);
  }

  Future<void> deleteChat(String id) => _api.deleteChat(id);

  Future<void> connectMemory({
    required String chatId,
    required String targetType,
    required String targetId,
  }) async {
    await _api.connectChatMemory(chatId, {
      'target_type': targetType,
      if (targetType == 'farm') 'farm_id': targetId,
      if (targetType == 'plot') 'plot_id': targetId,
    });
  }

  Future<void> disconnectMemory(String chatId) =>
      _api.disconnectChatMemory(chatId);

  ChatThreadModel _thread(Map<String, dynamic> row) {
    return ChatThreadModel(
      id: _requiredString(row, 'id'),
      title: _requiredString(row, 'title'),
      scope: _requiredString(row, 'scope_type'),
      farmId: row['farm_id'] as String?,
      plotId: row['plot_id'] as String?,
      diagnosisCaseId: row['diagnosis_case_id'] as String?,
      archived: row['archived_at'] != null,
      messages: const [],
    );
  }

  ChatMessageModel _message(Map<String, dynamic> row) {
    final role = _requiredString(row, 'role');
    return ChatMessageModel(
      id: _requiredString(row, 'id'),
      author: switch (role) {
        'user' => ChatAuthor.farmer,
        'assistant' => ChatAuthor.assistant,
        _ => ChatAuthor.system,
      },
      text: _requiredString(row, 'content'),
      sentAt: _requiredDateTime(row, 'created_at'),
    );
  }
}

Map<String, dynamic> _map(Object? value, {required String contract}) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

List<Map<String, dynamic>> _list(Object? value, {required String contract}) {
  if (value is List<dynamic>) {
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The response is missing $key',
  );
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final raw = row[key];
  final value = raw is String ? DateTime.tryParse(raw) : null;
  if (value != null) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The response is missing $key',
  );
}
