import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import 'voice_composer_controller.dart';

typedef LiveVoiceMessageSender = Future<void> Function(String text);

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

/// Coordinates one continuous, turn-based voice conversation.
///
/// Audio I/O remains isolated in [VoiceTurnIO]. Farmer speech is transcribed,
/// sent through the existing ordered chat pipeline, and only an owned persisted
/// assistant message can be spoken back. This preserves all existing chat
/// context, safety validation, idempotency, and authorization rules.
class LiveVoiceSessionController extends ChangeNotifier {
  factory LiveVoiceSessionController({
    required String chatId,
    required VoiceTurnIO voice,
    required LiveVoiceMessageSender sendMessage,
  }) => LiveVoiceSessionController._(
    chatId: chatId,
    voice: voice,
    sendMessage: sendMessage,
  );

  LiveVoiceSessionController._({
    required this.chatId,
    required this._voice,
    required this._sendMessage,
  }) {
    _voice.addListener(_handleVoiceChange);
  }

  final String chatId;
  final VoiceTurnIO _voice;
  final LiveVoiceMessageSender _sendMessage;

  LiveVoiceSessionState state = LiveVoiceSessionState.ready;
  String? farmerCaption;
  String? assistantCaption;
  String? errorCode;
  String? _pendingAssistantMessageId;
  Set<String> _assistantIdsBeforeTurn = const {};
  List<ChatMessageModel> _latestMessages = const [];
  bool _active = true;
  bool _disposed = false;
  bool _speechStarted = false;
  int _operation = 0;

  Duration get elapsed => _voice.elapsed;
  bool get isActive => _active && state != LiveVoiceSessionState.ended;

  Future<void> startListening() async {
    if (!isActive ||
        state == LiveVoiceSessionState.starting ||
        state == LiveVoiceSessionState.listening ||
        state == LiveVoiceSessionState.transcribing ||
        state == LiveVoiceSessionState.waiting) {
      return;
    }
    final operation = ++_operation;
    errorCode = null;
    _speechStarted = false;
    if (_voice.speakingMessageId != null) await _voice.stopSpeech();
    if (!_isCurrent(operation)) return;
    state = LiveVoiceSessionState.starting;
    _notify();
    try {
      await _voice.startRecording(onLimitReached: finishFarmerTurn);
      if (!_isCurrent(operation)) return;
      if (_voice.isRecording) {
        state = LiveVoiceSessionState.listening;
        _notify();
      }
    } on ApiException catch (error) {
      _fail(error.code);
    } catch (_) {
      _fail('VOICE_UNAVAILABLE');
    }
  }

  Future<void> finishFarmerTurn([List<ChatMessageModel>? messages]) async {
    if (!isActive || state != LiveVoiceSessionState.listening) return;
    final operation = ++_operation;
    state = LiveVoiceSessionState.transcribing;
    _notify();
    try {
      final transcript = await _voice.stopAndTranscribe(chatId);
      if (!_isCurrent(operation)) return;
      final normalized = transcript?.trim() ?? '';
      if (normalized.isEmpty) {
        state = LiveVoiceSessionState.ready;
        _notify();
        return;
      }
      farmerCaption = normalized;
      assistantCaption = null;
      _pendingAssistantMessageId = null;
      _assistantIdsBeforeTurn = (messages ?? _latestMessages)
          .where((message) => message.author == ChatAuthor.assistant)
          .map((message) => message.id)
          .toSet();
      state = LiveVoiceSessionState.waiting;
      _notify();
      await _sendMessage(normalized);
    } on ApiException catch (error) {
      if (_isCurrent(operation)) _fail(error.code);
    } catch (_) {
      if (_isCurrent(operation)) _fail('VOICE_TURN_FAILED');
    }
  }

  /// Called by the view whenever the canonical chat changes.
  void acceptMessages(List<ChatMessageModel> messages) {
    _latestMessages = List.unmodifiable(messages);
    if (!isActive || state != LiveVoiceSessionState.waiting) return;
    final candidates = messages
        .where(
          (message) =>
              message.author == ChatAuthor.assistant &&
              message.delivery == ChatDelivery.sent &&
              !_assistantIdsBeforeTurn.contains(message.id),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final assistant = candidates.last;
    if (_pendingAssistantMessageId == assistant.id) return;
    _pendingAssistantMessageId = assistant.id;
    assistantCaption = assistant.text;
    unawaited(_speak(assistant.id));
  }

  Future<void> _speak(String messageId) async {
    final operation = ++_operation;
    state = LiveVoiceSessionState.speaking;
    _speechStarted = false;
    _notify();
    try {
      final started = await _voice.toggleSpeech(
        chatId: chatId,
        messageId: messageId,
      );
      if (!_isCurrent(operation)) return;
      if (!started || _voice.speakingMessageId == null) {
        _fail('VOICE_PLAYBACK_FAILED');
        return;
      }
      _speechStarted = true;
      _notify();
    } on ApiException catch (error) {
      if (_isCurrent(operation)) _fail(error.code);
    } catch (_) {
      if (_isCurrent(operation)) _fail('VOICE_PLAYBACK_FAILED');
    }
  }

  Future<void> stopSaathiAndListen() async {
    if (!isActive || state != LiveVoiceSessionState.speaking) return;
    ++_operation;
    _speechStarted = false;
    await _voice.stopSpeech();
    if (!isActive) return;
    state = LiveVoiceSessionState.ready;
    _notify();
    await startListening();
  }

  Future<void> retry() async {
    if (!isActive || state != LiveVoiceSessionState.error) return;
    state = LiveVoiceSessionState.ready;
    errorCode = null;
    _notify();
    await startListening();
  }

  Future<void> pause() async {
    if (!isActive) return;
    ++_operation;
    _speechStarted = false;
    if (_voice.state == VoiceComposerState.starting ||
        _voice.state == VoiceComposerState.recording) {
      await _voice.cancelRecording();
    }
    await _voice.stopSpeech();
    if (!isActive) return;
    state = LiveVoiceSessionState.ready;
    _notify();
  }

  Future<void> end() async {
    if (!_active) return;
    _active = false;
    ++_operation;
    if (_voice.state == VoiceComposerState.starting ||
        _voice.state == VoiceComposerState.recording) {
      await _voice.cancelRecording();
    }
    await _voice.stopSpeech();
    state = LiveVoiceSessionState.ended;
    _notify();
  }

  void _handleVoiceChange() {
    if (!isActive) return;
    if (state == LiveVoiceSessionState.starting && _voice.isRecording) {
      state = LiveVoiceSessionState.listening;
      _notify();
      return;
    }
    if (state == LiveVoiceSessionState.listening &&
        _voice.state == VoiceComposerState.transcribing) {
      state = LiveVoiceSessionState.transcribing;
      _notify();
      return;
    }
    if (state == LiveVoiceSessionState.speaking &&
        _speechStarted &&
        _voice.speakingMessageId == null) {
      _speechStarted = false;
      state = LiveVoiceSessionState.ready;
      _notify();
      unawaited(startListening());
    }
  }

  bool _isCurrent(int operation) =>
      !_disposed && isActive && operation == _operation;

  void _fail(String code) {
    if (!isActive) return;
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
    _active = false;
    _operation++;
    _voice.removeListener(_handleVoiceChange);
    _voice.dispose();
    super.dispose();
  }
}
