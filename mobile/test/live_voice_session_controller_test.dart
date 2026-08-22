import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/features/saathi/presentation/live_voice_session_controller.dart';
import 'package:krishisathi/features/saathi/presentation/voice_composer_controller.dart';

void main() {
  test('voice turn is transcribed, streamed into chat, and spoken', () async {
    final voice = _FakeVoiceTurn();
    final messages = <ChatMessageModel>[];
    final controller = LiveVoiceSessionController(
      chatId: 'chat-1',
      transcribe: (_, _) async => 'unused',
      sendMessage: (chatId, text) async {
        messages.addAll([
          ChatMessageModel(
            id: 'user-1',
            author: ChatAuthor.farmer,
            text: text,
            sentAt: DateTime.utc(2026, 8, 19),
          ),
          ChatMessageModel(
            id: 'assistant-1',
            author: ChatAuthor.assistant,
            text: 'Inspect the lower leaves.',
            sentAt: DateTime.utc(2026, 8, 19),
          ),
        ]);
      },
      loadSpeech: (_, _) async => AuthenticatedResource(
        uri: Uri(scheme: 'https', host: 'example.test', path: '/speech.mp3'),
        headers: {},
      ),
      messages: () => messages,
      voice: voice,
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    expect(controller.state, LiveVoiceSessionState.listening);

    await controller.finishFarmerTurn(messages);

    expect(controller.farmerCaption, 'How are my leaves?');
    expect(controller.assistantCaption, 'Inspect the lower leaves.');
    expect(controller.state, LiveVoiceSessionState.speaking);
    expect(voice.spokenMessageId, 'assistant-1');

    voice.completeSpeech();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, LiveVoiceSessionState.listening);
    expect(voice.startCount, 2);
  });
}

class _FakeVoiceTurn extends ChangeNotifier implements VoiceTurnIO {
  @override
  VoiceComposerState state = VoiceComposerState.idle;
  @override
  Duration elapsed = Duration.zero;
  @override
  String? speakingMessageId;
  String? spokenMessageId;
  int startCount = 0;

  @override
  bool get isRecording => state == VoiceComposerState.recording;

  @override
  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  }) async {
    startCount += 1;
    state = VoiceComposerState.recording;
    notifyListeners();
  }

  @override
  Future<String?> stopAndTranscribe(String chatId) async {
    state = VoiceComposerState.idle;
    notifyListeners();
    return 'How are my leaves?';
  }

  @override
  Future<void> cancelRecording() async {
    state = VoiceComposerState.idle;
    notifyListeners();
  }

  @override
  Future<bool> toggleSpeech({
    required String chatId,
    required String messageId,
  }) async {
    spokenMessageId = messageId;
    speakingMessageId = messageId;
    notifyListeners();
    return true;
  }

  void completeSpeech() {
    speakingMessageId = null;
    notifyListeners();
  }

  @override
  Future<void> stopSpeech() async {
    speakingMessageId = null;
    notifyListeners();
  }
}
