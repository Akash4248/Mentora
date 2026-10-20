import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/idp_colors.dart';
import '../application/markdown_format_normalizer.dart';
import '../application/visual_stream_parser.dart';
import 'widgets/mermaid_diagram_card.dart';
import 'widgets/visual_card_widget.dart';

class FormattedTextWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedTextWidget({required this.text, this.style, super.key});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final parsedTurn = const VisualStreamParser().parse(text);
    if (parsedTurn.proseText.isEmpty && parsedTurn.visualIntents.isEmpty) {
      return const SizedBox.shrink();
    }

    final normalizedText = MarkdownFormatNormalizer.normalize(parsedTurn.proseText);
    final lines = normalizedText.split('\n');
    final List<Widget> children = [];

    List<String> currentList = [];
    bool isNumberedList = false;
    List<String> currentTable = [];

    bool inCodeBlock = false;
    String codeBlockLang = '';
    List<String> currentCodeBlockLines = [];

    void flushList() {
      if (currentList.isNotEmpty) {
        children.add(_buildList(currentList, isNumbered: isNumberedList));
        currentList = [];
        isNumberedList = false;
      }
    }

    void flushTable() {
      if (currentTable.isNotEmpty) {
        final tableWidget = _buildTable(currentTable);
        if (tableWidget != null) {
          children.add(tableWidget);
        } else {
          for (final tl in currentTable) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _buildRichText(tl),
            ));
          }
        }
        currentTable = [];
      }
    }

    void flushCodeBlock({bool isStillStreaming = false}) {
      if (currentCodeBlockLines.isNotEmpty || inCodeBlock) {
        final codeContent = currentCodeBlockLines.join('\n');
        if (codeBlockLang == 'mermaid') {
          children.add(MermaidDiagramCard(
            source: codeContent,
            isStreaming: isStillStreaming,
          ));
        } else {
          children.add(_buildCodeBlock(codeBlockLang, codeContent));
        }
        currentCodeBlockLines = [];
        inCodeBlock = false;
        codeBlockLang = '';
      }
    }

    final numberedRegex = RegExp(r'^\d+\.\s+');

    for (var line in lines) {
      final trimmed = line.trim();

      // Handle lines inside an active code block
      if (inCodeBlock) {
        if (trimmed == '```' || (trimmed.startsWith('```') && trimmed.length <= 4)) {
          flushCodeBlock(isStillStreaming: false);
          continue;
        } else {
          currentCodeBlockLines.add(line);
          continue;
        }
      }

      if (trimmed.isEmpty) {
        flushList();
        flushTable();
        children.add(const SizedBox(height: 6));
        continue;
      }

      // Check for code block opening (```mermaid, ```dart, ```, etc.)
      if (trimmed.startsWith('```')) {
        flushList();
        flushTable();
        inCodeBlock = true;
        codeBlockLang = trimmed.substring(3).trim().toLowerCase();
        currentCodeBlockLines = [];
        continue;
      }

      // Check for table row (e.g. starts and ends with '|')
      if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
        flushList();
        currentTable.add(trimmed);
        continue;
      } else {
        flushTable();
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

        // Check for horizontal rule
        if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
          children.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
          ));
          continue;
        }

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
    flushTable();
    if (inCodeBlock) {
      flushCodeBlock(isStillStreaming: parsedTurn.hasIncompleteBlock);
    }

    for (final intent in parsedTurn.visualIntents) {
      children.add(VisualCardWidget(intent: intent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildCodeBlock(String language, String code) {
    final displayLang = language.isEmpty ? 'code' : language;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                Text(
                  displayLang.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (ctx) => InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: Color(0xFF94A3B8)),
                          SizedBox(width: 4),
                          Text('Copy', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFF1F5F9),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildTable(List<String> rawLines) {
    if (rawLines.length < 2) return null;

    final delimiterRegex = RegExp(r'^\|?(\s*:?-+:?\s*\|)+\s*$');
    final rows = <List<String>>[];

    for (final raw in rawLines) {
      final line = raw.trim();
      if (delimiterRegex.hasMatch(line)) {
        continue;
      }
      final parts = line.split('|');
      final start = line.startsWith('|') ? 1 : 0;
      final end = line.endsWith('|') ? parts.length - 1 : parts.length;
      if (start < end) {
        final cells = parts.sublist(start, end).map((c) => c.trim()).toList();
        if (cells.isNotEmpty) {
          rows.add(cells);
        }
      }
    }

    if (rows.isEmpty) return null;

    final maxCols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (maxCols == 0) return null;

    final headerRow = rows.first;
    final dataRows = rows.skip(1).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            verticalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFEEF2FF)),
              children: List.generate(maxCols, (colIdx) {
                final text = colIdx < headerRow.length ? headerRow[colIdx] : '';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: _buildRichText(
                    text,
                    customStyle: (style ?? IDPTypography.bodyMd).copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                );
              }),
            ),
            ...dataRows.asMap().entries.map((entry) {
              final rowIdx = entry.key;
              final rowCells = entry.value;
              final isEven = rowIdx % 2 == 0;
              return TableRow(
                decoration: BoxDecoration(
                  color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                ),
                children: List.generate(maxCols, (colIdx) {
                  final text = colIdx < rowCells.length ? rowCells[colIdx] : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: _buildRichText(
                      text,
                      customStyle: (style ?? IDPTypography.bodyMd).copyWith(
                        fontSize: 13,
                      ),
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
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

  static String _normalizeMathExpression(String expr) {
    var s = expr;
    // Replace \sqrt{...} with √(...)
    s = s.replaceAllMapped(RegExp(r'\\sqrt\{([^}]+)\}'), (m) => '√(${m.group(1)})');
    // Replace \frac{a}{b} with (a / b)
    s = s.replaceAllMapped(RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'), (m) => '(${m.group(1)} / ${m.group(2)})');
    // Greek letters & math symbols
    s = s.replaceAll(r'\pi', 'π')
         .replaceAll(r'\theta', 'θ')
         .replaceAll(r'\alpha', 'α')
         .replaceAll(r'\beta', 'β')
         .replaceAll(r'\times', '×')
         .replaceAll(r'\cdot', '·')
         .replaceAll(r'\pm', '±')
         .replaceAll(r'\approx', '≈')
         .replaceAll(r'\le', '≤')
         .replaceAll(r'\leq', '≤')
         .replaceAll(r'\ge', '≥')
         .replaceAll(r'\geq', '≥')
         .replaceAll(r'\Delta', 'Δ')
         .replaceAll(r'\lambda', 'λ')
         .replaceAll(r'\mu', 'μ')
         .replaceAll(r'\infty', '∞')
         .replaceAll(r'\neq', '≠');
    // Superscripts ^2, ^3
    s = s.replaceAll('^2', '²').replaceAll('^3', '³');
    return s;
  }

  Widget _buildRichText(String rawText, {TextStyle? customStyle}) {
    final baseStyle = customStyle ?? style ?? IDPTypography.bodyMd.copyWith(color: IDPColors.onSurface);
    final spans = <TextSpan>[];

    // Markdown inline parser for **bold**, *italic*, `code`, and $math$
    final regExp = RegExp(r'(\*\*.*?\*\*|\*.*?\*|`.*?`|\$[^\$]+?\$)');
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
      } else if (matchText.startsWith('\$') && matchText.endsWith('\$') && matchText.length >= 2) {
        final content = matchText.substring(1, matchText.length - 1).trim();
        final readableMath = _normalizeMathExpression(content);
        spans.add(TextSpan(
          text: readableMath,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: IDPColors.primary,
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
