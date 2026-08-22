import 'package:just_audio/just_audio.dart';

import '../../../core/network/api_client.dart';

abstract interface class VoiceAudioPlayback {
  Stream<void> get onComplete;
  Future<void> play(AuthenticatedResource source);
  Future<void> stop();
  Future<void> dispose();
}

class DeviceVoiceAudioPlayback implements VoiceAudioPlayback {
  DeviceVoiceAudioPlayback([AudioPlayer? player])
    : _player =
          player ??
          AudioPlayer(
            useProxyForRequestHeaders: false,
            userAgent: 'KrishiSathi Android',
          );

  final AudioPlayer _player;

  @override
  Stream<void> get onComplete => _player.processingStateStream
      .where((state) => state == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> play(AuthenticatedResource source) async {
    await _player.setAudioSource(
      AudioSource.uri(source.uri, headers: source.headers),
    );
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
