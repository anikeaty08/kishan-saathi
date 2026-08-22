import 'dart:convert';

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

class ChatSendResult {
  const ChatSendResult({
    required this.userMessage,
    required this.assistantMessage,
    required this.followUpQuestions,
    this.reminderProposal,
  });

  final ChatMessageModel userMessage;
  final ChatMessageModel assistantMessage;
  final List<String> followUpQuestions;
  final ReminderProposalModel? reminderProposal;
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

  Future<ChatSendResult> sendMessage(
    String id,
    String content, {
    required String idempotencyKey,
  }) async {
    final payload = await _api.sendChatMessage(id, {
      'content': content.trim(),
    }, idempotencyKey: idempotencyKey);
    return _sendResult(_map(payload, contract: 'chat send'));
  }

  Future<ChatSendResult> streamMessage(
    String id,
    String content, {
    required String idempotencyKey,
    required void Function(String delta) onDelta,
  }) async {
    final lines = await _api.streamChatMessage(id, {
      'content': content.trim(),
    }, idempotencyKey: idempotencyKey);
    ChatSendResult? completed;
    try {
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = _map(jsonDecode(line), contract: 'chat stream event');
        switch (event['event']) {
          case 'token':
            final delta = event['data'];
            if (delta is String && delta.isNotEmpty) onDelta(delta);
          case 'done':
            completed = _sendResult(
              _map(event['result'], contract: 'completed chat stream'),
            );
          case 'error':
            final code = event['error_code'] as String? ?? 'CHAT_STREAM_FAILED';
            throw ApiException(code: code, message: _streamErrorMessage(code));
        }
      }
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The chat response stream could not be read',
      );
    } on TypeError {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The chat response stream was malformed',
      );
    }
    if (completed == null) {
      throw const ApiException(
        code: 'CHAT_STREAM_INCOMPLETE',
        message: 'The response ended before the message was saved',
      );
    }
    return completed;
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

  ChatSendResult _sendResult(Map<String, dynamic> row) {
    return ChatSendResult(
      userMessage: _message(
        _map(row['user_message'], contract: 'sent user message'),
      ),
      assistantMessage: _message(
        _map(row['assistant_message'], contract: 'sent assistant message'),
      ),
      followUpQuestions: _strings(row['follow_up_questions']),
      reminderProposal: switch (row['reminder_proposal']) {
        final Map<String, dynamic> value => _proposal(value),
        _ => null,
      },
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

String _streamErrorMessage(String code) => switch (code) {
  'CHAT_ARCHIVED' => 'Restore this conversation before sending a message',
  'IDEMPOTENCY_KEY_REUSED' => 'This message could not be retried safely',
  'LLM_TEMPORARILY_UNAVAILABLE' => 'Saathi is temporarily unavailable',
  'LLM_UNSAFE_OUTPUT_BLOCKED' => 'The response was blocked for safety',
  _ => 'The live response could not be completed',
};

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
