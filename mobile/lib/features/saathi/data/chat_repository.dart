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

  Future<List<ChatThreadModel>> loadChats({bool includeArchived = true}) async {
    final payload = await _api.listChats(
      filters: {'include_archived': '$includeArchived', 'limit': '100'},
    );
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

  Future<ChatMessagePageModel> loadMessagesPage(
    String id, {
    int limit = 50,
    int? beforeSequence,
  }) async {
    final payload = await _api.listChatMessages(
      id,
      paging: {
        'limit': '$limit',
        if (beforeSequence != null) 'before_sequence': '$beforeSequence',
      },
    );
    final row = _map(payload, contract: 'chat message page');
    final items = switch (row['items']) {
      final List<dynamic> values =>
        values
            .whereType<Map<String, dynamic>>()
            .map(_message)
            .toList(growable: false),
      _ => throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The chat message page is missing items',
      ),
    };
    return ChatMessagePageModel(
      items: items,
      nextBeforeSequence: (row['next_before_sequence'] as num?)?.toInt(),
    );
  }

  Future<ChatTurnModel> enqueueMessage(
    String id,
    String content, {
    required String idempotencyKey,
  }) async {
    final payload = await _api.sendChatMessage(id, {
      'content': content.trim(),
    }, idempotencyKey: idempotencyKey);
    return _turn(_map(payload, contract: 'chat turn'));
  }

  Future<List<ChatTurnModel>> recentTurns(String id) async {
    final payload = await _api.listChatTurns(id, activeOnly: false);
    return _list(
      payload,
      contract: 'chat turns',
    ).map(_turn).toList(growable: false);
  }

  Future<ChatTurnModel> getTurn(String chatId, String turnId) async {
    final payload = await _api.getChatTurn(chatId, turnId);
    return _turn(_map(payload, contract: 'chat turn'));
  }

  Future<ChatTurnModel> retryTurn(String chatId, String turnId) async {
    final payload = await _api.retryChatTurn(chatId, turnId);
    return _turn(_map(payload, contract: 'chat turn'));
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
      effectiveFarmId: row['effective_farm_id'] as String?,
      effectivePlotId: row['effective_plot_id'] as String?,
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
      structuredReply: switch (row['structured_content']) {
        final Map<String, dynamic> value => _structuredReply(value),
        _ => null,
      },
      sequence: (row['sequence'] as num?)?.toInt(),
    );
  }

  ChatTurnModel _turn(Map<String, dynamic> row) {
    final result = row['result'];
    final messages = <ChatMessageModel>[];
    if (result is Map<String, dynamic>) {
      if (result['user_message'] case final Map<String, dynamic> message) {
        messages.add(_message(message));
      }
      if (result['assistant_message'] case final Map<String, dynamic> message) {
        messages.add(_message(message));
      }
    }
    return ChatTurnModel(
      id: _requiredString(row, 'id'),
      chatId: _requiredString(row, 'chat_id'),
      idempotencyKey: _requiredString(row, 'idempotency_key'),
      content: _requiredString(row, 'content'),
      status: _requiredString(row, 'status'),
      createdAt: _requiredDateTime(row, 'created_at'),
      queuePosition: (row['queue_position'] as num?)?.toInt(),
      errorCode: row['error_code'] as String?,
      messages: messages,
      reminderProposal: result is Map<String, dynamic>
          ? switch (result['reminder_proposal']) {
              final Map<String, dynamic> value => _proposal(value),
              _ => null,
            }
          : null,
    );
  }

  ReminderProposalModel _proposal(Map<String, dynamic> row) {
    return ReminderProposalModel(
      id: _requiredString(row, 'id'),
      title: _requiredString(row, 'title'),
      dueAt: _requiredDateTime(row, 'due_at'),
      status: _requiredString(row, 'status'),
      chatId: row['chat_id'] as String?,
      plotId: row['plot_id'] as String?,
      recurrenceDays: (row['recurrence_days'] as num?)?.toInt(),
    );
  }

  ChatAssistantReplyModel _structuredReply(Map<String, dynamic> row) {
    return ChatAssistantReplyModel(
      shortAnswer: _requiredString(row, 'short_answer'),
      disposition: _requiredString(row, 'disposition'),
      certainty: _requiredString(row, 'certainty'),
      answerSections: _maps(row['answer_sections'])
          .map(
            (item) => ChatAnswerSectionModel(
              title: _requiredString(item, 'title'),
              body: _requiredString(item, 'body'),
            ),
          )
          .toList(growable: false),
      explanationPoints: _strings(row['explanation_points']),
      nextSteps: _strings(row['next_steps']),
      followUpQuestions: _strings(row['follow_up_questions']),
      generalPrecautions: _strings(row['general_precautions']),
      consultLocalExpert: row['consult_local_expert'] == true,
      details: row['details'] as String?,
      retakeAdvice: switch (row['retake_advice']) {
        final Map<String, dynamic> value => ChatRetakeAdviceModel(
          reasonCodes: _strings(value['reason_codes']),
          instructions: _strings(value['instructions']),
        ),
        _ => null,
      },
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

List<Map<String, dynamic>> _maps(Object? value) => switch (value) {
  final List<dynamic> items => items.whereType<Map<String, dynamic>>().toList(),
  _ => const [],
};

List<String> _strings(Object? value) => switch (value) {
  final List<dynamic> items => items.whereType<String>().toList(),
  _ => const [],
};

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
