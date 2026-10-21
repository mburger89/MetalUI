import MetalUI

/// The statistics panel: words per note as bars, notes made per day as a line.
/// Both are ordinary shapes (MetalUI has no `Canvas`): rectangles in a stack,
/// and a `Shape` whose `path(in:)` is the line.
struct StatsView: Component {
    let model: NotesModel

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(16)) {
            Text("Statistics").font(size: 20)
            Text(model.statsSummary).foregroundColor(.secondary)
            WordBars(model: model)
            PerDayLine(model: model)
        }
        .padding(Edges(all: Pixels(16)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Statistics: \(model.statsSummary)")
    }
}

/// One bar per note, tallest the longest note, 120 points at most.
struct WordBars: Component {
    let model: NotesModel

    var content: some ElementGroup {
        let counts = model.notes.map(\.wordCount)
        let tallest = max(counts.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Pixels(6)) {
            Text("Words per note").font(size: 13)
            HStack(alignment: .bottom, spacing: Pixels(8)) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                    Rectangle().fill(.chartInk)
                        .frame(width: Pixels(24), height: Pixels(Float(max(2, 120 * count / tallest))))
                }
            }
            .frame(height: Pixels(120), alignment: .bottomLeading)
        }
    }
}

/// The line of notes made per day over the last week.
struct PerDayLine: Component {
    let model: NotesModel

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(6)) {
            Text("Notes per day, last 7 days").font(size: 13)
            LineShape(values: model.notesPerDay().map(\.count))
                .stroke(.chartInk, lineWidth: Pixels(2))
                .frame(width: Pixels(240), height: Pixels(80))
        }
    }
}

/// A polyline through `values`, scaled to the rect.
struct LineShape: Shape {
    let values: [Int]

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            let width = rect.size.width.value, height = rect.size.height.value
            let top = Float(max(values.max() ?? 1, 1))
            for (index, value) in values.enumerated() {
                let x = values.count > 1 ? width * Float(index) / Float(values.count - 1) : 0
                let y = height - height * Float(value) / top
                let point = Point(x: Pixels(x), y: Pixels(y))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}
