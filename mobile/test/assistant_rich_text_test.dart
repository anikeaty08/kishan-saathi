import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/features/saathi/presentation/assistant_rich_text.dart';

void main() {
  testWidgets('renders assistant formatting without loading remote images', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AssistantRichText('''
## What to do

Use **clean tools** and *inspect daily*.

- Check lower leaves
- Avoid overhead watering

| Sign | Action |
| --- | --- |
| Spots | Retake a photo |

![Untrusted remote leaf](https://example.invalid/leaf.jpg)
'''),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Untrusted remote leaf'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide tables remain usable on compact large-text phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: AssistantRichText('''
### Observation table

| Observation with a long heading | Recommended farmer action | When to review again |
| --- | --- | --- |
| Yellow spots on lower leaves | Keep leaves dry and monitor spread | Tomorrow morning |
'''),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Scrollbar), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
