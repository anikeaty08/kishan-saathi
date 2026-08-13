import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class VoiceRepository {
  const VoiceRepository(this._api);

  final KrishiApi _api;

  Future<String> transcribe({
    required String chatId,
    required String audioPath,
  }) async {
    final payload = await _api.transcribeChatAudio(chatId, audioPath);
    if (payload case {'transcript': final String transcript}
        when transcript.trim().isNotEmpty) {
      return transcript.trim();
    }
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'The voice transcript could not be read',
    );
  }

  Future<List<int>> speech({
    required String chatId,
    required String messageId,
  }) => _api.assistantSpeech(chatId, messageId);
}
