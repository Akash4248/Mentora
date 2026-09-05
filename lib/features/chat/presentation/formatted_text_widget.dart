import 'package:flutter/material.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';

class FormattedTextWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedTextWidget({required this.text, this.style, super.key});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = text.split('\n');
    final List<Widget> children = [];

    List<String> currentList = [];
    bool isNumberedList = false;

    void flushList() {
      if (currentList.isNotEmpty) {
        children.add(_buildList(currentList, isNumbered: isNumberedList));
        currentList = [];
        isNumberedList = false;
      }
    }

    final numberedRegex = RegExp(r'^\d+\.\s+');

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushList();
        children.add(const SizedBox(height: 6));
        continue;
      }

      // Check for bullet list
      if (trimmed.startsWith('* ') || trimmed.startsWith('- ') || trimmed.startsWith('• ')) {
        if (isNumberedList) flushList();
        isNumberedList = false;
        final content = trimmed.substring(2);
        currentList.add(content);
      } else if (numberedRegex.hasMatch(trimmed)) {
        if (!isNumberedList) flushList();
        isNumberedList = true;
        currentList.add(trimmed);
      } else {
        flushList();

        // Check for headers (####, ###, ##, #)
        if (trimmed.startsWith('#### ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: _buildRichText(
              trimmed.substring(5),
              customStyle: (style ?? IDPTypography.bodyMd).copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: const Color(0xFF1E293B),
              ),
            ),
          ));
        } else if (trimmed.startsWith('### ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: _buildRichText(
              trimmed.substring(4),
              customStyle: (style ?? IDPTypography.titleSmall).copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: IDPColors.primary,
              ),
            ),
          ));
        } else if (trimmed.startsWith('## ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: _buildRichText(
              trimmed.substring(3),
              customStyle: (style ?? IDPTypography.titleMd).copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: IDPColors.primary,
              ),
            ),
          ));
        } else if (trimmed.startsWith('# ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: _buildRichText(
              trimmed.substring(2),
              customStyle: (style ?? IDPTypography.titleLarge).copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: IDPColors.primary,
              ),
            ),
          ));
        } else {
          // Normal text line
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _buildRichText(line),
          ));
        }
      }
    }

    flushList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildList(List<String> items, {required bool isNumbered}) {
    final numberedRegex = RegExp(r'^(\d+\.)\s+(.*)$');

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          if (isNumbered) {
            final match = numberedRegex.firstMatch(item);
            final prefix = match != null ? match.group(1)! : '•';
            final body = match != null ? match.group(2)! : item;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$prefix ',
                    style: (style ?? IDPTypography.bodyMd).copyWith(
                      fontWeight: FontWeight.bold,
                      color: IDPColors.primary,
                    ),
                  ),
                  Expanded(child: _buildRichText(body)),
                ],
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 8),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: IDPColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: _buildRichText(item)),
                ],
              ),
            );
          }
        }).toList(),
      ),
    );
  }

  Widget _buildRichText(String rawText, {TextStyle? customStyle}) {
    final baseStyle = customStyle ?? style ?? IDPTypography.bodyMd.copyWith(color: IDPColors.onSurface);
    final spans = <TextSpan>[];

    // Simple markdown inline parser for **bold** and *italic*
    final regExp = RegExp(r'(\*\*.*?\*\*|\*.*?\*|`.*?`)');
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(rawText)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: rawText.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final matchText = match.group(0)!;
      if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        final content = matchText.substring(2, matchText.length - 2);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        final content = matchText.substring(1, matchText.length - 1);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('`') && matchText.endsWith('`') && matchText.length >= 2) {
        final content = matchText.substring(1, matchText.length - 1);
        spans.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0xFFF1F5F9),
          ),
        ));
      } else {
        spans.add(TextSpan(text: matchText, style: baseStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < rawText.length) {
      spans.add(TextSpan(
        text: rawText.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans.isEmpty ? [TextSpan(text: rawText, style: baseStyle)] : spans),
    );
  }
}
