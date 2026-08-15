import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/features/saathi/presentation/live_voice_screen.dart';
import 'package:krishisathi/features/saathi/presentation/voice_composer_controller.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_controller.dart';

void main() {
  for (final viewport in [
    (
      name: 'compact Android with large text',
      size: const Size(360, 780),
      scale: 2.0,
    ),
    (name: 'iPhone safe width', size: const Size(393, 852), scale: 1.0),
    (name: 'tablet', size: const Size(1024, 900), scale: 1.0),
  ]) {
    testWidgets('live voice remains usable on ${viewport.name}', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final app = await createTestController();
      addTearDown(app.dispose);
      app.chats = [
        const ChatThreadModel(
          id: 'chat-voice',
          title: 'Tomato field',
          scope: 'plot',
          scopeLabel: 'North plot',
          messages: [],
        ),
      ];
      final voice = _ScreenFakeVoice();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: LiveVoiceScreen(
              chatId: 'chat-voice',
              voiceFactory: (_) => voice,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-voice-orb')), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('live-voice-primary')),
      );
      await tester.tap(find.byKey(const ValueKey('live-voice-primary')));
      await tester.pump();
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Stop & send'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Ready when you are'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    });
  }
}

class _ScreenFakeVoice extends ChangeNotifier implements VoiceTurnIO {
  @override
  VoiceComposerState state = VoiceComposerState.idle;
  @override
  Duration elapsed = Duration.zero;
  @override
  String? speakingMessageId;
  @override
  bool get isRecording => state == VoiceComposerState.recording;

  @override
  Future<void> startRecording({
    required Future<void> Function() onLimitReached,
  }) async {
    state = VoiceComposerState.recording;
    notifyListeners();
  }

  @override
  Future<String?> stopAndTranscribe(String chatId) async => 'Question';

  @override
  Future<void> cancelRecording() async {
    state = VoiceComposerState.idle;
    notifyListeners();
  }

  @override
  Future<bool> toggleSpeech({
    required String chatId,
    required String messageId,
  }) async {
    speakingMessageId = messageId;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stopSpeech() async {
    speakingMessageId = null;
    notifyListeners();
  }
}
