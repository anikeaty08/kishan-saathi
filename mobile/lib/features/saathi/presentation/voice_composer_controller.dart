import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/network/api_exception.dart';

typedef VoiceTranscriber = Future<String> Function(
  String chatId,
  String audioPath,
);
typedef AssistantSpeechLoader = Future<List<int>> Function(
  String chatId,
  String messageId,
);

enum VoiceComposerState { idle, starting, recording, stopping, transcribing }

class VoiceComposerController extends ChangeNotifier {
  VoiceComposerController({
    required this.transcribe,
    required this.loadSpeech,
    AudioRecorder? recorder,
    AudioPlayer? player,
    FlutterTts? deviceSpeech,
  }) : _recorder = recorder ?? AudioRecorder(),
       _player = player ?? AudioPlayer(),
       _deviceSpeech = deviceSpeech ?? FlutterTts() {
    _playerCompletion = _player.onPlayerComplete.listen((_) {
      speakingMessageId = null;
      _notify();
    });
    _deviceSpeech.setCompletionHandler(() {
      speakingMessageId = null;
      _notify();
    });
    _deviceSpeech.setErrorHandler((_) {
      speakingMessageId = null;
      _notify();
    });
  }

  static const maxRecordingDuration = Duration(seconds: 90);

  final VoiceTranscriber transcribe;
  final AssistantSpeechLoader loadSpeech;
  final AudioRecorder _recorder;
  final AudioPlayer _player;
  final FlutterTts _deviceSpeech;
  late final StreamSubscription<void> _playerCompletion;
  Timer? _ticker;
  String? _recordingPath;
  bool _disposed = false;

  VoiceComposerState state = VoiceComposerState.idle;
  Duration elapsed = Duration.zero;
  String? speakingMessageId;

  bool get isRecording => state == VoiceComposerState.recording;
  bool get isTranscribing => state == VoiceComposerState.transcribing;
  bool get isBusy => state != VoiceComposerState.idle;

  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  }) async {
    if (state != VoiceComposerState.idle || _disposed) return;
    state = VoiceComposerState.starting;
    _notify();
    String? path;
    try {
      if (!await _recorder.hasPermission()) {
        throw const ApiException(
          code: 'VOICE_PERMISSION_DENIED',
          message: 'Microphone permission was not granted',
        );
      }
      final directory = await getTemporaryDirectory();
      path =
          '${directory.path}${Platform.pathSeparator}'
          'saathi_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      _recordingPath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (_disposed) {
        await _recorder.stop();
        await _deleteTemporary(path);
        return;
      }
      elapsed = Duration.zero;
      state = VoiceComposerState.recording;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_disposed || state != VoiceComposerState.recording) {
          timer.cancel();
          return;
        }
        elapsed += const Duration(seconds: 1);
        _notify();
        if (elapsed >= maxRecordingDuration) {
          timer.cancel();
          unawaited(onLimitReached());
        }
      });
      _notify();
    } catch (_) {
      state = VoiceComposerState.idle;
      _recordingPath = null;
      _notify();
      if (path != null) await _deleteTemporary(path);
      rethrow;
    }
  }

  Future<String?> stopAndTranscribe(String chatId) async {
    if (state != VoiceComposerState.recording || _disposed) return null;
    state = VoiceComposerState.stopping;
    _notify();
    _ticker?.cancel();
    var path = _recordingPath;
    try {
      path = await _recorder.stop() ?? path;
      if (path == null) {
        throw const ApiException(
          code: 'VOICE_RECORDING_FAILED',
          message: 'The recording could not be prepared',
        );
      }
      state = VoiceComposerState.transcribing;
      _notify();
      return await transcribe(chatId, path);
    } finally {
      state = VoiceComposerState.idle;
      elapsed = Duration.zero;
      _recordingPath = null;
      _notify();
      if (path != null) await _deleteTemporary(path);
    }
  }

  Future<void> cancelRecording() async {
    if (state != VoiceComposerState.recording || _disposed) return;
    state = VoiceComposerState.stopping;
    _notify();
    _ticker?.cancel();
    var path = _recordingPath;
    try {
      path = await _recorder.stop() ?? path;
    } finally {
      state = VoiceComposerState.idle;
      elapsed = Duration.zero;
      _recordingPath = null;
      _notify();
      if (path != null) await _deleteTemporary(path);
    }
  }

  Future<bool> toggleSpeech({
    required String chatId,
    required String messageId,
    required String fallbackText,
    required String languageTag,
  }) async {
    if (_disposed) return false;
    if (speakingMessageId == messageId) {
      await stopSpeech();
      return true;
    }
    await stopSpeech();
    speakingMessageId = messageId;
    _notify();
    try {
      final bytes = await loadSpeech(chatId, messageId);
      if (_disposed) return false;
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
      return true;
    } on ApiException {
      if (_disposed) return false;
      await _deviceSpeech.setLanguage(languageTag);
      await _deviceSpeech.setSpeechRate(0.46);
      await _deviceSpeech.speak(fallbackText);
      return false;
    } catch (_) {
      speakingMessageId = null;
      _notify();
      rethrow;
    }
  }

  Future<void> stopSpeech() async {
    await _player.stop();
    await _deviceSpeech.stop();
    speakingMessageId = null;
    _notify();
  }

  Future<void> _deleteTemporary(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Temporary storage is OS-managed; disposal also retries cleanup.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _disposeResources() async {
    _ticker?.cancel();
    final path = _recordingPath;
    _recordingPath = null;
    if (state
        case VoiceComposerState.starting ||
            VoiceComposerState.recording ||
            VoiceComposerState.stopping) {
      try {
        await _recorder.stop();
      } catch (_) {
        // Continue disposal so local privacy cleanup is not skipped.
      }
    }
    if (path != null) await _deleteTemporary(path);
    await _playerCompletion.cancel();
    await _player.stop();
    await _deviceSpeech.stop();
    await _recorder.dispose();
    await _player.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_disposeResources());
    super.dispose();
  }
}
