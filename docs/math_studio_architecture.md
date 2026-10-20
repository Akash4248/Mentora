# Math Studio & Scientific Calculator Technical Architecture

This document specifies the technical architecture, package dependencies, rendering engine design, and responsive layout guidelines for the **Mentora Math Studio & Scientific Calculator**.

---

## 1. Package Dependencies & Roles

| Package Name | Category | Primary Function |
| :--- | :--- | :--- |
| `vector_math` | 3D/2D Geometry | Provides `Matrix4`, `Vector3`, `Quaternion`, and 3D camera projection calculations. |
| `math_expressions` | Symbolic Math Engine | Parses user string mathematical expressions (`sin(x)*cos(y)`, `2*x^2 + 3`) into evaluation trees. |
| `decimal` | High-Precision Arithmetic | Eliminates floating-point rounding errors (e.g., `0.1 + 0.2 != 0.3`) in scientific calculations. |
| `ditredi` & `three_dart` | 3D Math Renderer | Renders 3D mesh surfaces $z = f(x,y)$, 3D vectors, spheres, cones, cylinders, and coordinate axes. |
| `flutter_inappwebview` | Offline Engine Bridge | Hosts offline-bundled GeoGebra 3D & Classic calculators via bidirectional JavaScript bridge. |
| `flame` & `flame_forge2d` | 2D Physics Simulation | Simulates gravity and mechanical balance scale equilibrium for the Algebraic Balance Scale. |
| `syncfusion_flutter_charts` | Statistical Charts | Renders high-density histograms, ogives, frequency polygons, and normal distribution curves. |

---

## 2. Rendering Pipelines

### A. 3D Interactive Surface Pipeline (`MathStudio3DCanvas`)
1. **User Input / Touch Events**:
   - `GestureDetector` tracks pan deltas ($\Delta x, \Delta y$) to update orbital azimuth ($\phi$) and polar angle ($\theta$).
2. **Camera Projection Matrix**:
   - Uses `vector_math.Matrix4.perspective(...)` combined with `vector_math.Matrix4.lookAt(...)`.
3. **Surface Evaluation Loop**:
   - Evaluates $z = f(x, y)$ over a 2D mesh grid $(x_i, y_j) \in [-5, 5]^2$.
   - Projects 3D vertices to 2D screen coordinates $(u, v)$ via viewport matrix mapping.
4. **Custom Paint Rendering**:
   - Draws wireframe mesh and gradient shaded polygons with depth sorting (painter's algorithm).

### B. Scientific Calculator Pipeline (`ScientificCalculatorScreen`)
1. **Expression Buffer**: Stores tokenized user input string (e.g. `sin(degToRad(30)) + log(100)`).
2. **Parser Phase**: `Parser().parse(expression)` constructs an `Expression` AST tree.
3. **Evaluation Phase**: Evaluates expression with `ContextModel()` and converts to high-precision `Decimal`.
4. **LaTeX Rendering**: Renders formatted mathematical expression for crisp visual presentation.

---

## 3. Responsive Mobile / Tablet Layout Rules

- **Phone Screen ($< 600\text{dp}$ width)**:
  - Default: Auto-switch to **Landscape Orientation** on entering 3D Lab.
  - Collapsible overlay drawer for toolbars and parameter sliders.
- **Tablet & Desktop Screen ($\ge 600\text{dp}$ width)**:
  - Dual-pane side-by-side layout: Canvas on left (60% width), Inspector & controls on right (40% width).
