import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_exception.dart';
import 'voice_audio_playback.dart';
import 'voice_audio_recorder.dart';

typedef VoiceTranscriber = Future<String> Function(
  String chatId,
  String audioPath,
);
typedef AssistantSpeechLoader = Future<List<int>> Function(
  String chatId,
  String messageId,
);
typedef VoiceTemporaryPathFactory = Future<String> Function();

enum VoiceComposerState { idle, starting, recording, stopping, transcribing }

abstract interface class VoiceTurnIO implements Listenable {
  VoiceComposerState get state;
  Duration get elapsed;
  String? get speakingMessageId;
  bool get isRecording;

  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  });

  Future<String?> stopAndTranscribe(String chatId);
  Future<void> cancelRecording();

  Future<bool> toggleSpeech({
    required String chatId,
    required String messageId,
  });

  Future<void> stopSpeech();
  void dispose();
}

class VoiceComposerController extends ChangeNotifier implements VoiceTurnIO {
  VoiceComposerController({
    required this.transcribe,
    required this.loadSpeech,
    VoiceAudioRecorder? recorder,
    VoiceAudioPlayback? playback,
    VoiceTemporaryPathFactory? temporaryPath,
  }) : _recorder = recorder ?? DeviceVoiceAudioRecorder(),
       _playback = playback ?? DeviceVoiceAudioPlayback(),
       _temporaryPath = temporaryPath ?? _defaultTemporaryPath {
    _playerCompletion = _playback.onComplete.listen((_) {
      speakingMessageId = null;
      _notify();
    });
  }

  static const maxRecordingDuration = Duration(seconds: 90);

  final VoiceTranscriber transcribe;
  final AssistantSpeechLoader loadSpeech;
  final VoiceAudioRecorder _recorder;
  final VoiceAudioPlayback _playback;
  final VoiceTemporaryPathFactory _temporaryPath;
  late final StreamSubscription<void> _playerCompletion;
  Timer? _ticker;
  String? _recordingPath;
  bool _disposed = false;
  bool _cancelStartRequested = false;
  Future<void>? _startOperation;
  int _speechOperation = 0;

  @override
  VoiceComposerState state = VoiceComposerState.idle;
  @override
  Duration elapsed = Duration.zero;
  @override
  String? speakingMessageId;

  @override
  bool get isRecording => state == VoiceComposerState.recording;
  bool get isTranscribing => state == VoiceComposerState.transcribing;
  bool get isBusy => state != VoiceComposerState.idle;

  @override
  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  }) {
    if (state != VoiceComposerState.idle || _disposed) {
      return Future<void>.value();
    }
    _cancelStartRequested = false;
    final operation = _performStartRecording(onLimitReached: onLimitReached);
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
  }

  Future<void> _performStartRecording({
    required Future<void> Function() onLimitReached,
  }) async {
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
      path = await _temporaryPath();
      _recordingPath = path;
      await _recorder.start(path);
      if (_disposed || _cancelStartRequested) {
        await _recorder.stop();
        await _deleteTemporary(path);
        _recordingPath = null;
        state = VoiceComposerState.idle;
        _notify();
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
      try {
        await _recorder.stop();
      } catch (_) {
        // The recorder may not have reached its started state.
      }
      state = VoiceComposerState.idle;
      _recordingPath = null;
      _notify();
      if (path != null) await _deleteTemporary(path);
      if (_cancelStartRequested) return;
      rethrow;
    }
  }

  @override
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

  @override
  Future<void> cancelRecording() async {
    if (_disposed) return;
    if (state == VoiceComposerState.starting) {
      _cancelStartRequested = true;
      state = VoiceComposerState.stopping;
      _notify();
      await _startOperation;
      return;
    }
    if (state != VoiceComposerState.recording) return;
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

  @override
  Future<bool> toggleSpeech({
    required String chatId,
    required String messageId,
  }) async {
    if (_disposed) return false;
    if (speakingMessageId == messageId) {
      await stopSpeech();
      return true;
    }
    final operation = ++_speechOperation;
    await _playback.stop();
    if (_disposed || operation != _speechOperation) return false;
    speakingMessageId = messageId;
    _notify();
    try {
      final bytes = await loadSpeech(chatId, messageId);
      if (_disposed || operation != _speechOperation) return false;
      await _playback.play(bytes);
      if (_disposed || operation != _speechOperation) {
        await _playback.stop();
        return false;
      }
      return true;
    } catch (_) {
      if (operation == _speechOperation) {
        speakingMessageId = null;
        _notify();
      }
      rethrow;
    }
  }

  @override
  Future<void> stopSpeech() async {
    _speechOperation++;
    await _playback.stop();
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
    await _playback.stop();
    await _recorder.dispose();
    await _playback.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_disposeResources());
    super.dispose();
  }
}

Future<String> _defaultTemporaryPath() async {
  final directory = await getTemporaryDirectory();
  return '${directory.path}${Platform.pathSeparator}'
      'saathi_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
}
