import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/features/saathi/presentation/live_voice_session_controller.dart';
import 'package:krishisathi/features/saathi/presentation/voice_composer_controller.dart';

void main() {
  test(
    'voice turn stores only transcript and speaks owned assistant message',
    () async {
      final voice = FakeVoiceTurnIO(transcript: 'मेरे पत्ते पीले हैं');
      final sent = <String>[];
      final controller = LiveVoiceSessionController(
        chatId: 'chat-1',
        voice: voice,
        sendMessage: (text) async => sent.add(text),
      );
      addTearDown(controller.dispose);

      controller.acceptMessages([_assistant('old', 'Earlier answer')]);
      await controller.startListening();
      expect(controller.state, LiveVoiceSessionState.listening);

      await controller.finishFarmerTurn();
      expect(sent, ['मेरे पत्ते पीले हैं']);
      expect(controller.state, LiveVoiceSessionState.waiting);

      controller.acceptMessages([
        _assistant('old', 'Earlier answer'),
        _assistant('new', 'नई तस्वीर लेकर निचली पत्तियाँ जाँचें।'),
      ]);
      await _flush();

      expect(voice.spokenMessageIds, ['new']);
      expect(controller.state, LiveVoiceSessionState.speaking);
      expect(controller.farmerCaption, 'मेरे पत्ते पीले हैं');
      expect(
        controller.assistantCaption,
        'नई तस्वीर लेकर निचली पत्तियाँ जाँचें।',
      );

      voice.completeSpeech();
      await _flush();
      expect(controller.state, LiveVoiceSessionState.listening);
      expect(voice.startCount, 2);
    },
  );

  test('stopping Saathi cancels speech before listening again', () async {
    final voice = FakeVoiceTurnIO(transcript: 'What next?');
    final controller = LiveVoiceSessionController(
      chatId: 'chat-1',
      voice: voice,
      sendMessage: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.startListening();
    await controller.finishFarmerTurn();
    controller.acceptMessages([
      _assistant('answer', 'Inspect the lower leaves.'),
    ]);
    await _flush();
    expect(controller.state, LiveVoiceSessionState.speaking);

    await controller.stopSaathiAndListen();
    expect(voice.stopSpeechCount, greaterThanOrEqualTo(1));
    expect(controller.state, LiveVoiceSessionState.listening);
  });

  test(
    'ending prevents late assistant output from restarting microphone',
    () async {
      final voice = FakeVoiceTurnIO(transcript: 'Question');
      final controller = LiveVoiceSessionController(
        chatId: 'chat-1',
        voice: voice,
        sendMessage: (_) async {},
      );

      await controller.startListening();
      await controller.finishFarmerTurn();
      await controller.end();
      controller.acceptMessages([_assistant('late', 'Late answer')]);
      await _flush();

      expect(controller.state, LiveVoiceSessionState.ended);
      expect(voice.spokenMessageIds, isEmpty);
      controller.dispose();
    },
  );
}

ChatMessageModel _assistant(String id, String text) => ChatMessageModel(
  id: id,
  author: ChatAuthor.assistant,
  text: text,
  sentAt: DateTime(2026, 8, 15),
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class FakeVoiceTurnIO extends ChangeNotifier implements VoiceTurnIO {
  FakeVoiceTurnIO({required this.transcript});

  final String transcript;
  final List<String> spokenMessageIds = [];
  int startCount = 0;
  int stopSpeechCount = 0;

  @override
  VoiceComposerState state = VoiceComposerState.idle;
  @override
  Duration elapsed = Duration.zero;
  @override
  String? speakingMessageId;
  @override
  bool get isRecording => state == VoiceComposerState.recording;

  @override
  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  }) async {
    startCount++;
    state = VoiceComposerState.recording;
    notifyListeners();
  }

  @override
  Future<String?> stopAndTranscribe(String chatId) async {
    state = VoiceComposerState.transcribing;
    notifyListeners();
    state = VoiceComposerState.idle;
    notifyListeners();
    return transcript;
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
    spokenMessageIds.add(messageId);
    speakingMessageId = messageId;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stopSpeech() async {
    stopSpeechCount++;
    speakingMessageId = null;
    notifyListeners();
  }

  void completeSpeech() {
    speakingMessageId = null;
    notifyListeners();
  }
}
