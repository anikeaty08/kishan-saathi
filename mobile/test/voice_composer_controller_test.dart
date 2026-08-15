import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/features/saathi/presentation/voice_audio_playback.dart';
import 'package:krishisathi/features/saathi/presentation/voice_audio_recorder.dart';
import 'package:krishisathi/features/saathi/presentation/voice_composer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stop during speech download prevents stale audio playback', () async {
    final pending = Completer<List<int>>();
    final playback = _FakePlayback();
    final controller = VoiceComposerController(
      transcribe: (_, _) async => 'unused',
      loadSpeech: (_, _) => pending.future,
      recorder: _FakeRecorder(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    final start = controller.toggleSpeech(chatId: 'chat', messageId: 'one');
    await Future<void>.delayed(Duration.zero);
    expect(controller.speakingMessageId, 'one');

    await controller.stopSpeech();
    pending.complete([1, 2, 3]);

    expect(await start, isFalse);
    expect(playback.played, isEmpty);
    expect(controller.speakingMessageId, isNull);
  });

  test('switching messages cannot let the older download win', () async {
    final first = Completer<List<int>>();
    final playback = _FakePlayback();
    final controller = VoiceComposerController(
      transcribe: (_, _) async => 'unused',
      loadSpeech: (_, messageId) =>
          messageId == 'one' ? first.future : Future.value([2]),
      recorder: _FakeRecorder(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    final oldStart = controller.toggleSpeech(chatId: 'chat', messageId: 'one');
    await Future<void>.delayed(Duration.zero);
    final newStart = controller.toggleSpeech(chatId: 'chat', messageId: 'two');
    expect(await newStart, isTrue);
    first.complete([1]);

    expect(await oldStart, isFalse);
    expect(playback.played, [
      [2],
    ]);
    expect(controller.speakingMessageId, 'two');
  });

  test('cancel during recorder startup stops and cleans the state', () async {
    final recorder = _BlockingRecorder();
    final playback = _FakePlayback();
    final controller = VoiceComposerController(
      transcribe: (_, _) async => 'unused',
      loadSpeech: (_, _) async => const [],
      recorder: recorder,
      playback: playback,
      temporaryPath: () async => 'voice-test.m4a',
    );
    addTearDown(controller.dispose);

    final start = controller.startRecording(onLimitReached: () async {});
    await recorder.started.future;
    final cancel = controller.cancelRecording();
    recorder.allowStart.complete();
    await Future.wait([start, cancel]);

    expect(recorder.stopCount, 1);
    expect(controller.state, VoiceComposerState.idle);
    expect(controller.isRecording, isFalse);
  });
}

class _FakePlayback implements VoiceAudioPlayback {
  final StreamController<void> _completion = StreamController.broadcast();
  final List<List<int>> played = [];

  @override
  Stream<void> get onComplete => _completion.stream;

  @override
  Future<void> play(List<int> bytes) async => played.add(List.of(bytes));

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _completion.close();
}

class _FakeRecorder implements VoiceAudioRecorder {
  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {}

  @override
  Future<String?> stop() async => null;
}

class _BlockingRecorder implements VoiceAudioRecorder {
  final Completer<void> started = Completer<void>();
  final Completer<void> allowStart = Completer<void>();
  int stopCount = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    started.complete();
    await allowStart.future;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    return 'voice-test.m4a';
  }
}
