# C14b fixture: MetalCreator's bracket window, node drag (developer-c0, 2026-10-13)

This is read from MetalCreator's code. Rebuild it as a MetalUI test and benchmark. Never read or edit MetalCreator's trees: everything needed is below.

## Window

- Size 1440×900 at scale 2.

## Graph canvas (460 pt wide panel)

- 20 nodes and 21 wires.
- Each node is 168 pt wide and 24 + 12 + 20·rows pt tall.
- The nodes sit in one row, 40 pt apart, so they overlap.
- At zoom 1 roughly half fall outside the 460 pt canvas plus a 160 pt cull margin, so they are not built. Reproduce this cull.

Nodes, as inputs/outputs:

| Node | Inputs/outputs |
|---|---|
| Graph Parameter (×3) | 0/4 |
| Rounded Rectangle | 5/1 |
| Rectangle | 4/1 |
| Circle | 2/1 |
| Extrude (×3) | 4/1 |
| Grid Points | 6/1 |
| Plane | 2/1 |
| Boolean (×2) | 3/1 |
| Edges By Direction | 3/1 |
| Edge Filter | 4/1 |
| Edge Set Op | 3/1 |
| Edges By Tag | 1/1 |
| Fillet | 2/1 |
| Chamfer | 2/1 |
| Output | 1/1 |

- That is 82 rows and 82 socket dots in total.
- Every row is plain labels, with no inline controls.
- Only Fillet is selected.

## NodeView (about 20 leaf primitives per node)

- Header: an HStack of a title Text, a Spacer and a status badge. The badge is a Text on a Capsule, with `.help`.
- Body: a VStack of row HStacks.
  - An input row is a label Text, a Spacer and a value Text.
  - An output row is a Spacer and a label Text.
- Decoration:
  - a rounded-rect background;
  - `clipShape`;
  - a border overlay;
  - `.opacity`;
  - a keyframeAnimator offset for the refusal shake, idle during the drag.
- Socket overlay: a ZStack holding `Color.clear` plus one ZStack per dot. Each dot is a Circle fill with a Circle border overlay.
- Environment:
  - In MetalCreator, the views read `@Environment(ThemeStore.self)`, which divergence 346 refuses for `.equatable()`.
  - When MetalCreator adopts C14, it will pass the palette in as a VALUE.
  - The fixture should pass the palette as a value, so the node views can be `.equatable()` on their own node value plus palette. Also keep one arm that reads the environment, to show the refusal cost.

## Wires

- One WireView per link.
- Each is a WireShape, one cubic bezier Path stroked at 2 pt and framed to its padded bounds.
- The control-point offset is `max(40, |dx|·0.5)`.

## The rest of the window

- A full-window viewport: a `.onDemand` GPUSurface (a MetalView in MetalCreator) holding a mesh and one handle. It does not redraw on a node drag.
- A top bar: a Text, a menu Picker, two Buttons and a Menu.
- A graph panel, 460 pt wide:
  - a header with breadcrumbs and 7 Buttons;
  - a node library: a caption, a TextField and a windowed List;
  - then the canvas.
- A glass inspector, 280 pt wide:
  - a Material background with backdrop blur;
  - a header and a badge;
  - 3 sections holding 4 Slider plus number-entry rows, a Toggle, a summary row and a Button.

## The drag to measure: a node drag

1. `.mouseDown` on the selected node (Fillet).
2. `.mouseDragged` events moving it 2 pt each, with one simulated display-link tick per event.

Only the graph model changes (the moved node's position, and so its wires). Nothing else re-evaluates, the viewport does not redraw, and the work is CPU only.

MetalCreator reported 15 ms per drag event in release, on a loaded Mac, for this drag. It is a whole-window rebuild today. Record §105 measured a simpler 20-node drag at 1.14 ms release and 5.4 ms debug.

(A different benchmark, a handle drag that re-evaluates the model 75 times against a 100 ms budget, is NOT this item's target.)
