import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import '../../../../core/theme/idp_colors.dart';

/// A rich, interactive Flutter card that renders Mermaid diagrams natively
/// using `mermaid_flutter`. Provides pinch-to-zoom & pan in an expanded modal,
/// copy-to-clipboard, raw code inspection, and friendly streaming fallback.
class MermaidDiagramCard extends StatefulWidget {
  final String source;
  final bool isStreaming;

  const MermaidDiagramCard({
    required this.source,
    this.isStreaming = false,
    super.key,
  });

  @override
  State<MermaidDiagramCard> createState() => _MermaidDiagramCardState();
}

class _MermaidDiagramCardState extends State<MermaidDiagramCard> {
  bool _showCode = false;

  String _cleanSource(String raw) {
    var s = raw.trim();
    final lines = s.split('\n');
    if (lines.isNotEmpty && lines.first.trim().toLowerCase() == 'mermaid') {
      lines.removeAt(0);
      s = lines.join('\n').trim();
    }
    return s;
  }

  void _openInteractiveViewer(BuildContext context, String source) {
    showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Row(
                children: [
                  Icon(Icons.schema_rounded, size: 20, color: IDPColors.primary),
                  SizedBox(width: 8),
                  Text('Interactive Diagram', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: 'Copy Diagram Code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: source));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Diagram source copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: MermaidView(
                source: source,
                theme: MaterialMermaidTheme.fromTheme(Theme.of(ctx)),
                showControls: true,
                allowFullscreen: false,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final clean = _cleanSource(widget.source);
    if (clean.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schema_rounded,
                  size: 18,
                  color: IDPColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Concept Diagram',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: const Text(
                    'Mermaid',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: IDPColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                // Toggle Code / Diagram
                IconButton(
                  icon: Icon(
                    _showCode ? Icons.visibility_rounded : Icons.code_rounded,
                    size: 18,
                    color: const Color(0xFF64748B),
                  ),
                  tooltip: _showCode ? 'View Diagram' : 'View Code',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showCode = !_showCode),
                ),
                // Copy button
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 17, color: Color(0xFF64748B)),
                  tooltip: 'Copy Diagram Code',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: clean));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Diagram source copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                // Expand / Fullscreen
                IconButton(
                  icon: const Icon(Icons.fullscreen_rounded, size: 20, color: IDPColors.primary),
                  tooltip: 'Interactive Zoom & Pan',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openInteractiveViewer(context, clean),
                ),
              ],
            ),
          ),

          // Body
          if (_showCode)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF0F172A),
              child: SelectableText(
                clean,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFF8FAFC),
                  height: 1.4,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: MermaidDiagram(
                  source: clean,
                  theme: MaterialMermaidTheme.fromTheme(Theme.of(context)),
                  errorBuilder: (ctx, err) {
                    if (widget.isStreaming) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Drawing diagram...',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                              SizedBox(width: 6),
                              Text(
                                'Diagram layout pending syntax completion',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            clean,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF78350F),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
