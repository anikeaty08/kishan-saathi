import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/features/saathi/data/chat_outbox_store.dart';
import 'package:krishisathi/features/saathi/data/chat_repository.dart';

import 'support/test_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live language change rolls back when profile update fails', () async {
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method != 'readAll') return null;
          return {
            'cognito_access_token': 'test-access',
            'cognito_refresh_token': 'test-refresh',
            'cognito_token_expiry': DateTime.now()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });
    final controller = await createTestController(live: true);
    addTearDown(controller.dispose);

    await expectLater(controller.setLocale('hi'), throwsA(isA<ApiException>()));

    expect(controller.locale.languageCode, 'en');
    expect(controller.preferences.getString('preferred_language'), 'en');
  });

  test(
    'failed send remains visible and retryable in its existing chat',
    () async {
      final repository = _FakeChatRepository()
        ..enqueueError = const ApiException(
          code: 'NETWORK_UNAVAILABLE',
          message: 'offline',
        );
      final outbox = InMemoryChatOutboxStore();
      final controller = await createTestController(
        live: true,
        chatRepository: repository,
        chatOutboxStore: outbox,
      );
      addTearDown(controller.dispose);
      controller.chats = [
        const ChatThreadModel(
          id: 'chat-1',
          title: 'New conversation',
          scope: 'general',
          messages: [],
        ),
      ];

      await expectLater(
        controller.sendMessage('chat-1', 'What is wrong with this leaf?'),
        throwsA(isA<ApiException>()),
      );

      expect(controller.chats, hasLength(1));
      expect(controller.chats.single.messages, hasLength(1));
      expect(
        controller.chats.single.messages.single.delivery,
        ChatDelivery.failed,
      );
      expect(await outbox.readAll(), hasLength(1));
    },
  );

  test(
    'reconnect reconciles a completed turn without duplicate messages',
    () async {
      final user = _message('server-user', ChatAuthor.farmer, sequence: 1);
      final assistant = _message(
        'server-assistant',
        ChatAuthor.assistant,
        sequence: 2,
      );
      final proposal = ReminderProposalModel(
        id: 'proposal-1',
        chatId: 'chat-1',
        title: 'Inspect tomorrow',
        dueAt: DateTime.utc(2026, 8, 14, 9),
        status: 'pending',
      );
      final repository = _FakeChatRepository()
        ..loadedChat = ChatThreadModel(
          id: 'chat-1',
          title: 'Leaf advice',
          scope: 'general',
          messages: [user, assistant],
        )
        ..turns = [
          ChatTurnModel(
            id: 'turn-1',
            chatId: 'chat-1',
            idempotencyKey: 'stable-key',
            content: 'Inspect this leaf',
            status: 'completed',
            createdAt: DateTime.utc(2026, 8, 13, 9),
            queuePosition: null,
            messages: [user, assistant],
            reminderProposal: proposal,
          ),
        ];
      final outbox = InMemoryChatOutboxStore();
      await outbox.upsert(
        PendingChatEnvelope(
          localId: 'local-user',
          chatId: 'chat-1',
          content: 'Inspect this leaf',
          idempotencyKey: 'stable-key',
          createdAt: DateTime.utc(2026, 8, 13, 9),
        ),
      );
      final controller = await createTestController(
        live: true,
        chatRepository: repository,
        chatOutboxStore: outbox,
      );
      addTearDown(controller.dispose);
      controller.chats = [
        ChatThreadModel(
          id: 'chat-1',
          title: 'Leaf advice',
          scope: 'general',
          messages: [
            ChatMessageModel(
              id: 'local-user',
              author: ChatAuthor.farmer,
              text: 'Inspect this leaf',
              sentAt: DateTime.utc(2026, 8, 13, 9),
              delivery: ChatDelivery.queued,
              idempotencyKey: 'stable-key',
            ),
          ],
        ),
      ];

      await controller.loadChat('chat-1');

      expect(controller.chats.single.messages.map((message) => message.id), [
        'server-user',
        'server-assistant',
      ]);
      expect(await outbox.readAll(), isEmpty);
      expect(controller.reminderProposals.single.id, 'proposal-1');
    },
  );

  test('loads older messages once and preserves chronological order', () async {
    final repository = _FakeChatRepository()
      ..loadedChat = ChatThreadModel(
        id: 'chat-1',
        title: 'Long chat',
        scope: 'general',
        messages: [
          _message('message-3', ChatAuthor.farmer, sequence: 3),
          _message('message-4', ChatAuthor.assistant, sequence: 4),
        ],
      )
      ..page = ChatMessagePageModel(
        items: [
          _message('message-1', ChatAuthor.farmer, sequence: 1),
          _message('message-2', ChatAuthor.assistant, sequence: 2),
        ],
        nextBeforeSequence: null,
      );
    final controller = await createTestController(
      live: true,
      chatRepository: repository,
    );
    addTearDown(controller.dispose);
    controller.chats = [repository.loadedChat!];

    await controller.loadChat('chat-1');
    expect(controller.hasOlderChatMessages('chat-1'), isTrue);

    await controller.loadOlderChatMessages('chat-1');

    expect(controller.chats.single.messages.map((message) => message.id), [
      'message-1',
      'message-2',
      'message-3',
      'message-4',
    ]);
    expect(controller.hasOlderChatMessages('chat-1'), isFalse);
    expect(repository.pageRequests, 1);
  });

  test('turn polling pauses in background and resumes immediately', () async {
    final user = _message('server-user', ChatAuthor.farmer, sequence: 1);
    final assistant = _message(
      'server-assistant',
      ChatAuthor.assistant,
      sequence: 2,
    );
    final queued = ChatTurnModel(
      id: 'turn-1',
      chatId: 'chat-1',
      idempotencyKey: 'server-key',
      content: 'How are the leaves?',
      status: 'queued',
      createdAt: DateTime.utc(2026, 8, 13, 9),
      queuePosition: 1,
    );
    final repository = _FakeChatRepository()
      ..enqueueResult = queued
      ..polledTurn = ChatTurnModel(
        id: queued.id,
        chatId: queued.chatId,
        idempotencyKey: queued.idempotencyKey,
        content: queued.content,
        status: 'completed',
        createdAt: queued.createdAt,
        queuePosition: null,
        messages: [user, assistant],
      );
    final controller = await createTestController(
      live: true,
      chatRepository: repository,
      chatOutboxStore: InMemoryChatOutboxStore(),
    );
    addTearDown(controller.dispose);
    controller.chats = [
      const ChatThreadModel(
        id: 'chat-1',
        title: 'Leaf advice',
        scope: 'general',
        messages: [],
      ),
    ];
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);

    await controller.sendMessage('chat-1', queued.content);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repository.getTurnRequests, 0);
    expect(controller.isChatResponding('chat-1'), isTrue);

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(repository.getTurnRequests, 1);
    expect(controller.isChatResponding('chat-1'), isFalse);
    expect(controller.chats.single.messages.map((item) => item.id), [
      'server-user',
      'server-assistant',
    ]);
  });
}

ChatMessageModel _message(
  String id,
  ChatAuthor author, {
  required int sequence,
}) => ChatMessageModel(
  id: id,
  author: author,
  text: id,
  sentAt: DateTime.utc(2026, 8, 13, 9, sequence),
  sequence: sequence,
);

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository()
    : super(
        KrishiApi(
          ApiClient(
            baseUri: Uri.parse('https://example.test'),
            tokenStore: SecureTokenStore(),
          ),
        ),
      );

  ChatThreadModel? loadedChat;
  List<ChatTurnModel> turns = const [];
  ChatMessagePageModel page = const ChatMessagePageModel(
    items: [],
    nextBeforeSequence: null,
  );
  ApiException? enqueueError;
  ChatTurnModel? enqueueResult;
  ChatTurnModel? polledTurn;
  int pageRequests = 0;
  int getTurnRequests = 0;

  @override
  Future<ChatThreadModel> loadChat(String id) async => loadedChat!;

  @override
  Future<List<ChatTurnModel>> recentTurns(String id) async => turns;

  @override
  Future<ChatMessagePageModel> loadMessagesPage(
    String id, {
    int limit = 50,
    int? beforeSequence,
  }) async {
    pageRequests += 1;
    return page;
  }

  @override
  Future<ChatTurnModel> enqueueMessage(
    String id,
    String content, {
    required String idempotencyKey,
  }) async {
    final error = enqueueError;
    if (error != null) throw error;
    final result = enqueueResult;
    if (result != null) {
      return ChatTurnModel(
        id: result.id,
        chatId: result.chatId,
        idempotencyKey: idempotencyKey,
        content: result.content,
        status: result.status,
        createdAt: result.createdAt,
        queuePosition: result.queuePosition,
        errorCode: result.errorCode,
        messages: result.messages,
        reminderProposal: result.reminderProposal,
      );
    }
    throw StateError('enqueueMessage was not configured for this test');
  }

  @override
  Future<ChatTurnModel> getTurn(String chatId, String turnId) async {
    getTurnRequests += 1;
    final result = polledTurn;
    if (result == null) {
      throw StateError('getTurn was not configured for this test');
    }
    return result;
  }
}
