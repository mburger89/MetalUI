import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPrimitives

// C10 lane 3 — the gradient raster (ruling `LK-J` items 4–6).

/// One gradient fill layer (`LK-J`).
@MainActor
func paintGradientFill(_ fill: GradientFill, _ geometry: ShapeGeometry, style: FillStyle?, pass: PaintPass) {}

/// One centred gradient stroke layer (`LK-J`).
@MainActor
func paintGradientStroke(_ fill: GradientFill, _ geometry: ShapeGeometry, style: StrokeStyle, pass: PaintPass) {}
