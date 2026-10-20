import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/presentation/formatted_text_widget.dart';

void main() {
  group('FormattedTextWidget', () {
    testWidgets('renders markdown table correctly with Table widget', (tester) async {
      const markdown = '''
Here is the summary table:

| Concept | Equation | SI Units |
|---------|----------|----------|
| Distance | \$ d = \\sqrt{x^2 + y^2} \$ | Meter (m) |
| Speed | \$ v = \\frac{d}{t} \$ | Meter per second (m/s) |

Let me know if you need more details!
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedTextWidget(text: markdown),
          ),
        ),
      );

      // Verify that Table widget is present
      expect(find.byType(Table), findsOneWidget);

      // Verify table header cells
      expect(find.text('Concept'), findsOneWidget);
      expect(find.text('Equation'), findsOneWidget);
      expect(find.text('SI Units'), findsOneWidget);

      // Verify table data cells
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Meter (m)'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Meter per second (m/s)'), findsOneWidget);

      // Verify math expression was normalized
      expect(find.text('d = √(x² + y²)'), findsOneWidget);
      expect(find.text('v = (d / t)'), findsOneWidget);
    });

    testWidgets('strips raw mentora-tool-call blocks from rendered text', (tester) async {
      const markdown = '''
### Pendulum Motion

```mentora-tool-call
{"name": "lookup_simulation", "arguments": {"topic": "Interactive Pendulum & Motion Lab"}}
```

The pendulum oscillates with periodic motion.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedTextWidget(text: markdown),
          ),
        ),
      );

      expect(find.text('The pendulum oscillates with periodic motion.'), findsOneWidget);
      expect(find.textContaining('lookup_simulation'), findsNothing);
      expect(find.textContaining('mentora-tool-call'), findsNothing);
    });

    testWidgets('renders Mermaid diagram with MermaidDiagramCard and MermaidDiagram', (tester) async {
      const markdown = '''
Here is the concept map for Newton's laws:

```mermaid
graph TD
   A[Newton's Laws of Motion] --> B[Step-by-step Explanation]
   B --> C[Formulae]
   C --> D[Real-World Analogy]
   D --> E[Limitation of Analogy]
   E --> F[Conceptual Observation Check]
```

Review this flow carefully.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(text: markdown),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that prose before and after the diagram renders
      expect(find.text("Here is the concept map for Newton's laws:"), findsOneWidget);
      expect(find.text('Review this flow carefully.'), findsOneWidget);

      // Verify MermaidDiagramCard header components
      expect(find.text('Concept Diagram'), findsOneWidget);
      expect(find.text('Mermaid'), findsOneWidget);

      // Verify actions
      expect(find.byIcon(Icons.code_rounded), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      // Toggle code view
      await tester.tap(find.byIcon(Icons.code_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("A[Newton's Laws of Motion]"), findsOneWidget);

      // Toggle back to diagram view
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('renders generic code blocks with language header and copy button', (tester) async {
      const markdown = '''
Calculate force in Python:

```python
mass = 10.0
accel = 9.8
force = mass * accel
print(f"Force: {force} N")
```
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(text: markdown),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PYTHON'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining('force = mass * accel'), findsOneWidget);
    });
  });
}
