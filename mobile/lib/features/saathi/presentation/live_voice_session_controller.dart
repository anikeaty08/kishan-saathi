import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import 'voice_composer_controller.dart';

typedef LiveVoiceMessageSender = Future<void> Function(
  String chatId,
  String text,
);
typedef LiveVoiceMessages = List<ChatMessageModel> Function();

enum LiveVoiceSessionState {
  ready,
  starting,
  listening,
  transcribing,
  waiting,
  speaking,
  error,
  ended,
}

class LiveVoiceSessionController extends ChangeNotifier {
  factory LiveVoiceSessionController({
    required String chatId,
    required VoiceTranscriber transcribe,
    required LiveVoiceMessageSender sendMessage,
    required AssistantSpeechLoader loadSpeech,
    required LiveVoiceMessages messages,
    VoiceTurnIO? voice,
  }) => LiveVoiceSessionController._(
    chatId: chatId,
    sendMessage: sendMessage,
    messages: messages,
    voice:
        voice ??
        VoiceComposerController(transcribe: transcribe, loadSpeech: loadSpeech),
  );

  LiveVoiceSessionController._({
    required this.chatId,
    required this._sendMessage,
    required this._messages,
    required this._voice,
  }) {
    _voice.addListener(_handleVoiceState);
  }

  final String chatId;
  final LiveVoiceMessageSender _sendMessage;
  final LiveVoiceMessages _messages;
  final VoiceTurnIO _voice;

  LiveVoiceSessionState state = LiveVoiceSessionState.ready;
  String? farmerCaption;
  String? assistantCaption;
  String? errorCode;
  bool _disposed = false;
  bool _advancingAfterSpeech = false;

  bool get isActive => state != LiveVoiceSessionState.ended;

  Future<void> startListening() async {
    if (_disposed ||
        (state != LiveVoiceSessionState.ready &&
            state != LiveVoiceSessionState.error)) {
      return;
    }
    errorCode = null;
    state = LiveVoiceSessionState.starting;
    _notify();
    try {
      await _voice.startRecording(
        onLimitReached: () => finishFarmerTurn(_messages()),
      );
      if (_disposed || state == LiveVoiceSessionState.ended) return;
      if (!_voice.isRecording) {
        throw const ApiException(
          code: 'VOICE_RECORDING_FAILED',
          message: 'The microphone could not start',
        );
      }
      state = LiveVoiceSessionState.listening;
      _notify();
    } on ApiException catch (error) {
      await _fail(error.code);
    } catch (_) {
      await _fail('VOICE_UNAVAILABLE');
    }
  }

  void acceptMessages(List<ChatMessageModel> messages) {
    if (_disposed || messages.isEmpty) return;
    final assistant = messages.reversed.cast<ChatMessageModel?>().firstWhere(
      (message) =>
          message?.author == ChatAuthor.assistant &&
          message!.text.trim().isNotEmpty,
      orElse: () => null,
    );
    if (assistant != null &&
        (state == LiveVoiceSessionState.waiting ||
            state == LiveVoiceSessionState.speaking)) {
      assistantCaption = assistant.text;
      _notify();
    }
  }

  Future<void> finishFarmerTurn([List<ChatMessageModel>? messages]) async {
    if (_disposed || state != LiveVoiceSessionState.listening) return;
    final before = (messages ?? _messages())
        .map((message) => message.id)
        .toSet();
    state = LiveVoiceSessionState.transcribing;
    _notify();
    try {
      final transcript = await _voice.stopAndTranscribe(chatId);
      if (_disposed || state == LiveVoiceSessionState.ended) return;
      if (transcript == null || transcript.trim().isEmpty) {
        state = LiveVoiceSessionState.ready;
        _notify();
        return;
      }
      farmerCaption = transcript.trim();
      assistantCaption = null;
      state = LiveVoiceSessionState.waiting;
      _notify();

      await _sendMessage(chatId, transcript);
      if (_disposed || state == LiveVoiceSessionState.ended) return;
      final assistant = _messages().reversed
          .cast<ChatMessageModel?>()
          .firstWhere(
            (message) =>
                message?.author == ChatAuthor.assistant &&
                !before.contains(message!.id),
            orElse: () => null,
          );
      if (assistant == null) {
        throw const ApiException(
          code: 'VOICE_ASSISTANT_MESSAGE_MISSING',
          message: 'The spoken reply was not saved',
        );
      }
      assistantCaption = assistant.text;
      state = LiveVoiceSessionState.speaking;
      _notify();
      final started = await _voice.toggleSpeech(
        chatId: chatId,
        messageId: assistant.id,
      );
      if (!started && !_disposed) await _startNextTurn();
    } on ApiException catch (error) {
      await _fail(error.code);
    } catch (_) {
      await _fail('VOICE_UNAVAILABLE');
    }
  }

  Future<void> stopSaathiAndListen() async {
    if (_disposed || state != LiveVoiceSessionState.speaking) return;
    await _voice.stopSpeech();
    await _startNextTurn();
  }

  Future<void> retry() async {
    if (_disposed || state != LiveVoiceSessionState.error) return;
    state = LiveVoiceSessionState.ready;
    errorCode = null;
    _notify();
    await startListening();
  }

  Future<void> pause() async {
    if (_disposed || state == LiveVoiceSessionState.ended) return;
    await _stopLocalAudio();
    state = LiveVoiceSessionState.ready;
    _notify();
  }

  Future<void> end() async {
    if (_disposed) return;
    await _stopLocalAudio();
    state = LiveVoiceSessionState.ended;
    _notify();
  }

  void _handleVoiceState() {
    if (_disposed ||
        state != LiveVoiceSessionState.speaking ||
        _voice.speakingMessageId != null ||
        _advancingAfterSpeech) {
      return;
    }
    unawaited(_startNextTurn());
  }

  Future<void> _startNextTurn() async {
    if (_advancingAfterSpeech || _disposed) return;
    _advancingAfterSpeech = true;
    try {
      state = LiveVoiceSessionState.ready;
      _notify();
      await startListening();
    } finally {
      _advancingAfterSpeech = false;
    }
  }

  Future<void> _stopLocalAudio() async {
    if (_voice.isRecording) await _voice.cancelRecording();
    if (_voice.speakingMessageId != null) await _voice.stopSpeech();
  }

  Future<void> _fail(String code) async {
    if (_disposed || !isActive) return;
    await _stopLocalAudio();
    errorCode = code;
    state = LiveVoiceSessionState.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _voice
      ..removeListener(_handleVoiceState)
      ..dispose();
    super.dispose();
  }
}
