import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/presentation/formatted_text_widget.dart';
import 'package:mentora/features/chat/presentation/widgets/geometry_canvas.dart';
import 'package:mentora/features/chat/presentation/widgets/ray_optics_canvas.dart';
import 'package:mentora/features/chat/presentation/widgets/solution_step_card.dart';
import 'package:mentora/features/chat/presentation/widgets/visual_card_widget.dart';

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

    testWidgets(r'renders block math $$ ... $$ and converts LaTeX symbols to Unicode', (tester) async {
      const markdown = r'''
Here is the integral to solve:

$$
\int (2 x^2 + 5 y^3 dx)
$$

And the summation formula:
\[ \sum_{i=1}^n i = \frac{n(n+1)}{2} \]
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

      expect(find.byIcon(Icons.functions_rounded), findsNWidgets(2));
      expect(find.textContaining('∫ (2 x² + 5 y³ dx)'), findsOneWidget);
      expect(find.textContaining('∑'), findsOneWidget);
    });

    testWidgets('attaches circuit schematic visual card when student asks about kirchhoff', (tester) async {
      const markdown = '''
Kirchhoff's Current Law states that the total current entering a junction must equal the total current leaving.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(
                text: markdown,
                studentQuestion: "show me how kirchoff's law works",
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify that circuit visual card is attached
      expect(find.textContaining("Kirchhoff's Current Law"), findsOneWidget);
      expect(find.text("Kirchhoff's Laws & Circuit Loop"), findsOneWidget);
      expect(find.text('Voltage (V)'), findsOneWidget);
    });

    testWidgets('renders ray optics canvas for merora-visual misspelling with trailing brace', (tester) async {
      const markdown =
          '```merora-visual {"type": "optics.ray_diagram", "scenario": "concave_mirror", "title": "Rays Reflecting from a Concave Mirror", "inputs": {"focal_length_cm": 15, "object_distance_cm": 30}} } ```';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(text: markdown),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify that ray optics canvas rendered instead of black code card
      expect(find.text('Rays Reflecting from a Concave Mirror'), findsOneWidget);
      expect(find.text('MERORA-VISUAL'), findsNothing);
      expect(find.byType(RayOpticsCanvas), findsOneWidget);
    });

    testWidgets('intercepts tool-call escaping into ```mermaid and renders visual card without syntax error', (tester) async {
      const markdown =
          '```mermaid {"name": "geometry.construction", "arguments": {"scenario": "bionomial", "inputs": {"base": 10, "height": 6, "radius": 3, "distance": 4}}} ```';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(text: markdown),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify that Mermaid error banner is NOT displayed
      expect(find.textContaining('Diagram layout pending syntax completion'), findsNothing);
      expect(find.textContaining('syntax error'), findsNothing);
      // Verify visual intent was intercepted and geometry canvas is rendered
      expect(find.byType(VisualCardWidget), findsOneWidget);
      expect(find.byType(GeometryCanvas), findsOneWidget);
    });

    testWidgets('renders SolutionStepCard when model emits steps.solution inside mermaid without disappearing', (tester) async {
      const markdown =
          '```mermaid {"name": "steps.solution", "arguments": {"expression": "(a + b)^n", "steps": ["Use Pascal\'s triangle to find the coefficients of the expansion", "Expand each term using the binomial theorem", "Combine like terms to get the final expression"]}} ```';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedTextWidget(text: markdown),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify that Mermaid error banner is NOT displayed
      expect(find.textContaining('Diagram layout pending syntax completion'), findsNothing);
      // Verify that SolutionStepCard was rendered and did NOT disappear
      expect(find.byType(SolutionStepCard), findsOneWidget);
      expect(find.textContaining('(a + b)^n'), findsWidgets);
      expect(find.textContaining("Use Pascal's triangle"), findsOneWidget);
      expect(find.textContaining("Expand each term"), findsOneWidget);
    });
  });
}
