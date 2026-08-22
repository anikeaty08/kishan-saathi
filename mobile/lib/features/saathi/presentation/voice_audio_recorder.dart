import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class VoiceAudioRecorder {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<Stream<Uint8List>> startStream();
  Future<String?> stop();
  Future<void> dispose();
}

class DeviceVoiceAudioRecorder implements VoiceAudioRecorder {
  DeviceVoiceAudioRecorder([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: path,
  );

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 24000,
      numChannels: 1,
    ),
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}
