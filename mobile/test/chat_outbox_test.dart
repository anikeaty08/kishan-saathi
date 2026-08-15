import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/features/saathi/data/chat_outbox_store.dart';

void main() {
  test('chat outbox preserves idempotency identity until completion', () async {
    final store = InMemoryChatOutboxStore();
    final created = PendingChatEnvelope(
      localId: 'local-1',
      chatId: 'chat-1',
      content: 'Meri fasal ke patte pe daag hain',
      idempotencyKey: 'stable-request-key',
      createdAt: DateTime.utc(2026, 8, 13, 10),
    );

    await store.upsert(created);
    await store.upsert(created.copyWith(turnId: 'turn-1'));

    final restored = await store.readAll();
    expect(restored, hasLength(1));
    expect(restored.single.idempotencyKey, 'stable-request-key');
    expect(restored.single.turnId, 'turn-1');
    expect(restored.single.content, created.content);

    await store.remove(created.localId);
    expect(await store.readAll(), isEmpty);
  });
}
