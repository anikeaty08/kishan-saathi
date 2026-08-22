import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/features/saathi/data/chat_repository.dart';

void main() {
  test('loads archived chats explicitly and preserves archive state', () async {
    final api = _FakeKrishiApi()
      ..chatsPayload = [_chat('chat-1', archivedAt: '2026-08-13T10:00:00Z')];
    final repository = ChatRepository(api);

    final chats = await repository.loadChats();

    expect(api.lastChatFilters?['include_archived'], 'true');
    expect(api.lastChatFilters?['limit'], '100');
    expect(chats.single.archived, isTrue);
  });

  test('parses paged messages and their stable sequence cursor', () async {
    final api = _FakeKrishiApi()
      ..messagesPayload = {
        'items': [_message('message-1', sequence: 12)],
        'next_before_sequence': 12,
      };
    final repository = ChatRepository(api);

    final page = await repository.loadMessagesPage(
      'chat-1',
      beforeSequence: 20,
    );

    expect(api.lastMessagePaging?['before_sequence'], '20');
    expect(page.items.single.sequence, 12);
    expect(page.nextBeforeSequence, 12);
  });

  test('streams deltas and returns the persisted direct-send result', () async {
    final api = _FakeKrishiApi()
      ..streamLines = [
        jsonEncode({'event': 'routing', 'status': 'Thinking...'}),
        jsonEncode({'event': 'token', 'data': 'Inspect '}),
        jsonEncode({'event': 'token', 'data': 'the leaves.'}),
        jsonEncode({
          'event': 'done',
          'result': {
            'user_message': _message('message-1', sequence: 1),
            'assistant_message': _message(
              'message-2',
              sequence: 2,
              role: 'assistant',
            ),
            'reminder_proposal': {
              'id': 'proposal-1',
              'chat_id': 'chat-1',
              'plot_id': 'plot-1',
              'title': 'Inspect leaves',
              'due_at': '2026-08-14T10:00:00Z',
              'status': 'pending',
              'recurrence_days': null,
            },
          },
        }),
      ];
    final repository = ChatRepository(api);
    final deltas = <String>[];

    final result = await repository.streamMessage(
      'chat-1',
      'Remind me tomorrow',
      idempotencyKey: 'request-123',
      onDelta: deltas.add,
    );

    expect(deltas.join(), 'Inspect the leaves.');
    expect(result.userMessage.id, 'message-1');
    expect(result.assistantMessage.id, 'message-2');
    expect(result.reminderProposal?.id, 'proposal-1');
    expect(api.lastIdempotencyKey, 'request-123');
  });
}

Map<String, Object?> _chat(String id, {String? archivedAt}) => {
  'id': id,
  'title': 'Crop question',
  'scope_type': 'general',
  'farm_id': null,
  'plot_id': null,
  'diagnosis_case_id': null,
  'archived_at': archivedAt,
};

Map<String, Object?> _message(
  String id, {
  required int sequence,
  String role = 'user',
}) => {
  'id': id,
  'sequence': sequence,
  'role': role,
  'content': role == 'user' ? 'Farmer message' : 'Assistant response',
  'created_at': '2026-08-13T10:00:00Z',
  'structured_content': null,
};

class _FakeKrishiApi extends KrishiApi {
  _FakeKrishiApi()
    : super(
        ApiClient(
          baseUri: Uri.parse('https://example.test'),
          tokenStore: SecureTokenStore(),
        ),
      );

  Object? chatsPayload;
  Object? messagesPayload;
  List<String> streamLines = const [];
  Map<String, String>? lastChatFilters;
  Map<String, String>? lastMessagePaging;
  String? lastIdempotencyKey;

  @override
  Future<Object?> listChats({Map<String, String>? filters}) async {
    lastChatFilters = filters;
    return chatsPayload;
  }

  @override
  Future<Object?> listChatMessages(
    String id, {
    Map<String, String>? paging,
  }) async {
    lastMessagePaging = paging;
    return messagesPayload;
  }

  @override
  Future<Stream<String>> streamChatMessage(
    String id,
    Map<String, Object?> body, {
    required String idempotencyKey,
  }) async {
    lastIdempotencyKey = idempotencyKey;
    return Stream.fromIterable(streamLines);
  }
}
