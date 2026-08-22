import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/features/saathi/presentation/saathi_screens.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets('Saathi home suggestions keep readable light-theme contrast', (
    tester,
  ) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_screen(controller, const SaathiScreen()));
    await tester.pumpAndSettle();

    const prompt = 'What should I do before rain?';
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('saathi-home-prompt-$prompt')),
    );
    final label = tester.widget<Text>(find.text(prompt));
    expect(surface.color, const Color(0xFFE7F0E5));
    expect(label.style?.color, AppColors.ink);
  });

  testWidgets('new chat keeps the selected farm visible', (tester) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);
    controller.farms = const [
      FarmModel(id: 'farm-1', name: 'North Farm', plots: []),
    ];

    await tester.pumpWidget(_screen(controller, const NewChatScreen()));
    final scopePicker = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    scopePicker.onSelectionChanged!({'farm'});
    await tester.pumpAndSettle();

    final selector = find.byType(DropdownButtonFormField<String>);
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('North Farm').last);
    await tester.pumpAndSettle();

    final selected = tester.widget<DropdownButtonFormField<String>>(selector);
    expect(selected.initialValue, 'farm-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty general chat opens with useful natural starters', (
    tester,
  ) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);
    controller.chats = [
      const ChatThreadModel(
        id: 'chat-general-empty',
        title: 'New conversation',
        scope: 'general',
        messages: [],
      ),
    ];

    await tester.pumpWidget(
      _screen(controller, const ChatDetailScreen(chatId: 'chat-general-empty')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('general-chat-welcome')), findsOneWidget);
    expect(find.text('What can I help with today?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-context-pill')),
      findsNothing,
    );

    const starter = 'Help me think through a crop problem';
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('general-chat-prompt-$starter')),
    );
    final label = tester.widget<Text>(find.text(starter));
    expect(surface.color, const Color(0xFFE7F0E5));
    expect(label.style?.color, AppColors.ink);
    await tester.tap(find.text(starter));
    await tester.pump();
    final composer = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-composer')),
    );
    expect(composer.controller?.text, starter);
  });

  testWidgets('archived chat restores before the composer is enabled', (
    tester,
  ) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);
    controller.chats = [
      const ChatThreadModel(
        id: 'chat-archived',
        title: 'Archived advice',
        scope: 'general',
        archived: true,
        messages: [],
      ),
    ];

    await tester.pumpWidget(
      _screen(controller, const ChatDetailScreen(chatId: 'chat-archived')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archived conversation'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(controller.chats.single.archived, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('chat renders a pending typed reminder proposal', (tester) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);
    controller.chats = [
      const ChatThreadModel(
        id: 'chat-reminder',
        title: 'Leaf follow-up',
        scope: 'general',
        messages: [],
      ),
    ];
    controller.reminderProposals = [
      ReminderProposalModel(
        id: 'proposal-1',
        chatId: 'chat-reminder',
        title: 'Check the leaves again',
        dueAt: DateTime(2026, 8, 14, 9),
        status: 'pending',
      ),
    ];

    await tester.pumpWidget(
      _screen(controller, const ChatDetailScreen(chatId: 'chat-reminder')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggested reminder'), findsOneWidget);
    expect(find.text('Check the leaves again'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('scan chat uses linked evidence and document-style AI replies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createTestController();
    addTearDown(controller.dispose);
    final diagnosis = DemoData.diagnoses.single;
    controller.diagnoses = [diagnosis];
    controller.chats = [
      ChatThreadModel(
        id: 'chat-scan',
        title: 'Tomato leaf scan',
        scope: 'scan',
        scopeLabel: diagnosis.plotName,
        diagnosisCaseId: diagnosis.id,
        messages: [
          ChatMessageModel(
            id: 'farmer-1',
            author: ChatAuthor.farmer,
            text: 'What should I do now?',
            sentAt: DateTime(2026, 8, 13, 9),
          ),
          ChatMessageModel(
            id: 'assistant-1',
            author: ChatAuthor.assistant,
            text: 'Inspect the lower leaves and keep them dry.',
            sentAt: DateTime(2026, 8, 13, 9, 1),
            structuredReply: const ChatAssistantReplyModel(
              shortAnswer: 'Start with a careful inspection today.',
              disposition: 'in_scope',
              certainty: 'possible',
              answerSections: [],
              explanationPoints: [
                'Moist leaves can increase disease pressure.',
              ],
              nextSteps: [
                'Inspect the lower leaves.',
                'Avoid wetting foliage.',
              ],
              followUpQuestions: ['Can it spread?'],
              generalPrecautions: [
                'Wash hands after handling affected leaves.',
              ],
              consultLocalExpert: false,
            ),
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      _screen(controller, const ChatDetailScreen(chatId: 'chat-scan')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('linked-scan-card')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('linked-scan-card')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(find.text('What to do now'), findsOneWidget);
    expect(find.text('Why this matters'), findsOneWidget);
    expect(find.text('General precautions'), findsOneWidget);
    expect(find.text('Can it spread?'), findsOneWidget);
    final followUp = tester.widget<ActionChip>(
      find.byKey(const ValueKey('follow-up-question-Can it spread?')),
    );
    expect(followUp.backgroundColor, const Color(0xFFE7F0E5));
    expect(followUp.labelStyle?.color, AppColors.ink);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.text('Read aloud'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-composer')), findsOneWidget);
    final microphone = find.byKey(const ValueKey('chat-voice-button'));
    final send = find.byTooltip('Send');
    expect(microphone, findsOneWidget);
    expect(send, findsOneWidget);
    expect(
      tester.getCenter(microphone).dx,
      lessThan(tester.getCenter(send).dx),
    );

    await tester.ensureVisible(find.text('Can it spread?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can it spread?'));
    await tester.pump();
    final composer = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-composer')),
    );
    expect(composer.controller?.text, 'Can it spread?');
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation column stays readable on tablet and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = await createTestController();
    addTearDown(controller.dispose);
    controller.chats = [
      ChatThreadModel(
        id: 'chat-1',
        title: 'Field planning',
        scope: 'general',
        messages: [
          ChatMessageModel(
            id: 'farmer-tablet',
            author: ChatAuthor.farmer,
            text: 'What should I check today?',
            sentAt: DateTime(2026, 8, 15, 8),
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      _screen(controller, const ChatDetailScreen(chatId: 'chat-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport
      in <
        ({
          String name,
          Size size,
          String locale,
          bool rtl,
          double textScale,
          FakeViewPadding padding,
        })
      >[
        (
          name: 'Realme-sized Android at 200 percent text',
          size: Size(360, 780),
          locale: 'en',
          rtl: false,
          textScale: 2,
          padding: FakeViewPadding(top: 24),
        ),
        (
          name: 'iPhone safe areas',
          size: Size(393, 852),
          locale: 'en',
          rtl: false,
          textScale: 1,
          padding: FakeViewPadding(top: 47, bottom: 34),
        ),
        (
          name: 'RTL phone',
          size: Size(393, 852),
          locale: 'en',
          rtl: true,
          textScale: 1,
          padding: FakeViewPadding(top: 47, bottom: 34),
        ),
        (
          name: 'centered tablet',
          size: Size(1024, 900),
          locale: 'en',
          rtl: false,
          textScale: 1,
          padding: FakeViewPadding.zero,
        ),
      ]) {
    testWidgets('conversation remains document-like on ${viewport.name}', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = viewport.padding;
      tester.view.viewPadding = viewport.padding;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controller = await createTestController(locale: viewport.locale);
      addTearDown(controller.dispose);
      controller.chats = [
        ChatThreadModel(
          id: 'chat-visual',
          title: 'Field planning',
          scope: 'general',
          messages: [
            ChatMessageModel(
              id: 'farmer-visual',
              author: ChatAuthor.farmer,
              text: 'What should I check today?',
              sentAt: DateTime(2026, 8, 15, 8),
            ),
            ChatMessageModel(
              id: 'assistant-visual',
              author: ChatAuthor.assistant,
              text: 'Walk the field early and inspect the lower leaves first.',
              sentAt: DateTime(2026, 8, 15, 8, 1),
            ),
          ],
        ),
      ];
      const detail = ChatDetailScreen(chatId: 'chat-visual');
      await tester.pumpWidget(
        _screen(
          controller,
          viewport.rtl
              ? Directionality(textDirection: TextDirection.rtl, child: detail)
              : detail,
        ),
      );
      await tester.pumpAndSettle();

      final composer = find.byKey(const ValueKey('chat-composer-surface'));
      expect(composer, findsOneWidget);
      expect(
        tester.getSize(composer).width,
        lessThanOrEqualTo(
          viewport.size.width >= 600 ? 720 : viewport.size.width,
        ),
      );
      expect(find.byType(Image), findsNothing);
      if (viewport.rtl) {
        expect(Directionality.of(tester.element(composer)), TextDirection.rtl);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _screen(AppController controller, Widget child) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      locale: controller.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: child,
    ),
  );
}
