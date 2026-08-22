import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/features/saathi/presentation/voice_audio_playback.dart';
import 'package:krishisathi/features/saathi/presentation/voice_audio_recorder.dart';
import 'package:krishisathi/features/saathi/presentation/voice_composer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stop during speech download prevents stale audio playback', () async {
    final pending = Completer<AuthenticatedResource>();
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
    pending.complete(_speechSource('one'));

    expect(await start, isFalse);
    expect(playback.played, isEmpty);
    expect(controller.speakingMessageId, isNull);
  });

  test('switching messages cannot let the older download win', () async {
    final first = Completer<AuthenticatedResource>();
    final playback = _FakePlayback();
    final controller = VoiceComposerController(
      transcribe: (_, _) async => 'unused',
      loadSpeech: (_, messageId) => messageId == 'one'
          ? first.future
          : Future.value(_speechSource('two')),
      recorder: _FakeRecorder(),
      playback: playback,
    );
    addTearDown(controller.dispose);

    final oldStart = controller.toggleSpeech(chatId: 'chat', messageId: 'one');
    await Future<void>.delayed(Duration.zero);
    final newStart = controller.toggleSpeech(chatId: 'chat', messageId: 'two');
    expect(await newStart, isTrue);
    first.complete(_speechSource('one'));

    expect(await oldStart, isFalse);
    expect(playback.played, [Uri.parse('https://example.test/two.mp3')]);
    expect(controller.speakingMessageId, 'two');
  });

  test('cancel during recorder startup stops and cleans the state', () async {
    final recorder = _BlockingRecorder();
    final playback = _FakePlayback();
    final controller = VoiceComposerController(
      transcribe: (_, _) async => 'unused',
      loadSpeech: (_, _) async => _speechSource('unused'),
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
  final List<Uri> played = [];

  @override
  Stream<void> get onComplete => _completion.stream;

  @override
  Future<void> play(AuthenticatedResource source) async =>
      played.add(source.uri);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _completion.close();
}

AuthenticatedResource _speechSource(String id) => AuthenticatedResource(
  uri: Uri.parse('https://example.test/$id.mp3'),
  headers: const {'Authorization': 'Bearer test'},
);

class _FakeRecorder implements VoiceAudioRecorder {
  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {}

  @override
  Future<Stream<Uint8List>> startStream() async => const Stream.empty();

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
  Future<Stream<Uint8List>> startStream() async => const Stream.empty();

  @override
  Future<String?> stop() async {
    stopCount++;
    return 'voice-test.m4a';
  }
}
