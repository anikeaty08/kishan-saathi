import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/theme/app_theme.dart';

/// Renders trusted, backend-reviewed Saathi copy as selectable rich text.
///
/// Remote Markdown images and link navigation are deliberately disabled. This
/// prevents model-generated content from making unapproved network requests or
/// opening arbitrary destinations on the farmer's device.
class AssistantRichText extends StatelessWidget {
  const AssistantRichText(this.data, {super.key, this.prominent = false});

  final String data;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle =
        (prominent
                ? theme.textTheme.bodyLarge?.copyWith(fontSize: 17)
                : theme.textTheme.bodyMedium)
            ?.copyWith(height: 1.5);
    final headingColor = scheme.onSurface;
    final divider = scheme.outlineVariant.withValues(alpha: 0.8);

    return MarkdownBody(
      key: const ValueKey('assistant-rich-text'),
      data: data.trim(),
      selectable: true,
      fitContent: false,
      softLineBreak: true,
      // Deliberately leave links without a tap handler. They are selectable and
      // copyable but cannot navigate away from the app without product review.
      onTapLink: null,
      imageBuilder: (_, _, alt) => Text(
        alt?.trim().isNotEmpty == true ? alt!.trim() : 'Image reference',
        style: bodyStyle?.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: bodyStyle,
        pPadding: const EdgeInsets.only(bottom: 7),
        strong: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
        em: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
        h1: theme.textTheme.titleLarge?.copyWith(
          color: headingColor,
          fontWeight: FontWeight.w700,
        ),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 6),
        h2: theme.textTheme.titleMedium?.copyWith(
          color: headingColor,
          fontWeight: FontWeight.w700,
        ),
        h2Padding: const EdgeInsets.only(top: 8, bottom: 5),
        h3: theme.textTheme.bodyLarge?.copyWith(
          color: headingColor,
          fontWeight: FontWeight.w700,
        ),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 4),
        blockSpacing: 8,
        listIndent: 22,
        listBullet: bodyStyle?.copyWith(
          color: AppColors.leaf,
          fontWeight: FontWeight.w700,
        ),
        blockquote: bodyStyle?.copyWith(color: scheme.onSurfaceVariant),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.youngLeaf.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: const BorderDirectional(
            start: BorderSide(color: AppColors.leaf, width: 3),
          ),
        ),
        tableHead: theme.textTheme.labelMedium?.copyWith(
          color: AppColors.forest,
          fontWeight: FontWeight.w700,
        ),
        tableBody: theme.textTheme.bodySmall?.copyWith(height: 1.35),
        tableHeadAlign: TextAlign.start,
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        tableHeadCellsDecoration: BoxDecoration(
          color: AppColors.youngLeaf.withValues(alpha: 0.12),
        ),
        tableBorder: TableBorder.all(color: divider),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider)),
        ),
      ),
    );
  }
}
