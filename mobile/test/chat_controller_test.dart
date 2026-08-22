import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/features/saathi/data/chat_repository.dart';

import 'support/test_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renders assistant deltas before the direct request completes',
    () async {
      final repository = _FakeStreamingChatRepository()..holdCompletion = true;
      final controller = await createTestController(
        live: true,
        chatRepository: repository,
      );
      addTearDown(controller.dispose);
      controller.chats = [_thread()];

      final send = controller.sendMessage('chat-1', 'Hey sup');
      await repository.firstDelta.future;

      expect(controller.isChatResponding('chat-1'), isTrue);
      expect(controller.chats.single.messages, hasLength(2));
      expect(controller.chats.single.messages.first.author, ChatAuthor.farmer);
      expect(
        controller.chats.single.messages.first.delivery,
        ChatDelivery.sending,
      );
      expect(controller.chats.single.messages.last.text, 'Hello ');

      repository.release();
      await send;

      expect(controller.isChatResponding('chat-1'), isFalse);
      expect(controller.chats.single.messages.map((message) => message.id), [
        'server-user-1',
        'server-assistant-1',
      ]);
      expect(controller.chats.single.messages.last.text, 'Hello farmer.');
    },
  );

  test('marks a failed direct request and retries the same message', () async {
    final repository = _FakeStreamingChatRepository()..fail = true;
    final controller = await createTestController(
      live: true,
      chatRepository: repository,
    );
    addTearDown(controller.dispose);
    controller.chats = [_thread()];

    await expectLater(
      controller.sendMessage('chat-1', 'Check my crop'),
      throwsA(isA<ApiException>()),
    );
    final failedUser = controller.chats.single.messages.firstWhere(
      (message) => message.author == ChatAuthor.farmer,
    );
    expect(failedUser.delivery, ChatDelivery.failed);

    repository.fail = false;
    await controller.retryChatMessage('chat-1', failedUser.id);

    expect(repository.requests, 2);
    expect(controller.chats.single.messages, hasLength(2));
    expect(
      controller.chats.single.messages.every(
        (message) => message.delivery == ChatDelivery.sent,
      ),
      isTrue,
    );
  });

  test('starts a second stream without waiting for the first one', () async {
    final repository = _ConcurrentStreamingChatRepository();
    final controller = await createTestController(
      live: true,
      chatRepository: repository,
    );
    addTearDown(controller.dispose);
    controller.chats = [_thread()];

    final first = controller.sendMessage('chat-1', 'First');
    final second = controller.sendMessage('chat-1', 'Second');
    await repository.bothStarted.future;

    expect(repository.activeRequests, 2);
    expect(controller.isChatResponding('chat-1'), isTrue);

    repository.releaseAll();
    await Future.wait([first, second]);

    expect(repository.maximumConcurrentRequests, 2);
    expect(controller.isChatResponding('chat-1'), isFalse);
  });
}

ChatThreadModel _thread() => const ChatThreadModel(
  id: 'chat-1',
  title: 'Direct chat',
  scope: 'general',
  messages: [],
);

ChatSendResult _result(int request) => ChatSendResult(
  userMessage: ChatMessageModel(
    id: 'server-user-$request',
    author: ChatAuthor.farmer,
    text: 'Farmer message',
    sentAt: DateTime.utc(2026, 8, 19),
    sequence: request * 2 - 1,
  ),
  assistantMessage: ChatMessageModel(
    id: 'server-assistant-$request',
    author: ChatAuthor.assistant,
    text: 'Hello farmer.',
    sentAt: DateTime.utc(2026, 8, 19),
    sequence: request * 2,
  ),
  followUpQuestions: const [],
);

KrishiApi _unusedApi() => KrishiApi(
  ApiClient(
    baseUri: Uri.parse('https://example.test'),
    tokenStore: SecureTokenStore(),
  ),
);

class _FakeStreamingChatRepository extends ChatRepository {
  _FakeStreamingChatRepository() : super(_unusedApi());

  final firstDelta = Completer<void>();
  Completer<void>? _release;
  bool fail = false;
  int requests = 0;

  set holdCompletion(bool value) {
    _release = value ? Completer<void>() : null;
  }

  void release() => _release?.complete();

  @override
  Future<ChatSendResult> streamMessage(
    String id,
    String content, {
    required String idempotencyKey,
    required void Function(String delta) onDelta,
  }) async {
    requests += 1;
    onDelta('Hello ');
    if (!firstDelta.isCompleted) firstDelta.complete();
    if (_release case final release?) await release.future;
    if (fail) {
      throw const ApiException(
        code: 'LLM_TEMPORARILY_UNAVAILABLE',
        message: 'Try again',
      );
    }
    onDelta('farmer.');
    return _result(requests);
  }
}

class _ConcurrentStreamingChatRepository extends ChatRepository {
  _ConcurrentStreamingChatRepository() : super(_unusedApi());

  final bothStarted = Completer<void>();
  final _release = Completer<void>();
  int activeRequests = 0;
  int maximumConcurrentRequests = 0;
  int requests = 0;

  void releaseAll() => _release.complete();

  @override
  Future<ChatSendResult> streamMessage(
    String id,
    String content, {
    required String idempotencyKey,
    required void Function(String delta) onDelta,
  }) async {
    final request = ++requests;
    activeRequests += 1;
    if (activeRequests > maximumConcurrentRequests) {
      maximumConcurrentRequests = activeRequests;
    }
    if (activeRequests == 2 && !bothStarted.isCompleted) bothStarted.complete();
    onDelta('$content ');
    await _release.future;
    activeRequests -= 1;
    return _result(request);
  }
}
