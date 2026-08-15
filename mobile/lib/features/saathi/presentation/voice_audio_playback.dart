import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract interface class VoiceAudioPlayback {
  Stream<void> get onComplete;
  Future<void> play(List<int> bytes);
  Future<void> stop();
  Future<void> dispose();
}

class DeviceVoiceAudioPlayback implements VoiceAudioPlayback {
  DeviceVoiceAudioPlayback([AudioPlayer? player])
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(List<int> bytes) =>
      _player.play(BytesSource(Uint8List.fromList(bytes)));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
