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

  test('parses a typed reminder proposal from a completed turn', () async {
    final api = _FakeKrishiApi()
      ..turnsPayload = [
        {
          'id': 'turn-1',
          'chat_id': 'chat-1',
          'idempotency_key': 'request-123',
          'content': 'Remind me tomorrow',
          'status': 'completed',
          'created_at': '2026-08-13T10:00:00Z',
          'queue_position': null,
          'error_code': null,
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
        },
      ];
    final repository = ChatRepository(api);

    final turn = (await repository.recentTurns('chat-1')).single;

    expect(turn.reminderProposal?.id, 'proposal-1');
    expect(turn.reminderProposal?.chatId, 'chat-1');
    expect(turn.reminderProposal?.plotId, 'plot-1');
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
  Object? turnsPayload;
  Map<String, String>? lastChatFilters;
  Map<String, String>? lastMessagePaging;

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
  Future<Object?> listChatTurns(String id, {bool activeOnly = true}) async {
    return turnsPayload;
  }
}
