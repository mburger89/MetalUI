import MetalUICore
import MetalUIMarkdown

/// A GFM table: a `Grid` in a horizontal scroller, columns aligned by the delimiter row (`BM-E`).
///
/// The header's cells are bold. A full-width rule follows the header and every body row but the last. Cell text
/// does not wrap, so a wide table scrolls sideways instead of squeezing its columns.
struct MarkdownTable: Component, ProposalElementGroup, @MainActor Equatable {
    let alignments: [MarkdownTableAlignment]
    let header: [String]
    let rows: [[String]]
    let theme: MarkdownTheme

    /// The horizontal alignment a delimiter cell asks for.
    static func alignment(_ alignment: MarkdownTableAlignment) -> HorizontalAlignment {
        switch alignment {
        case .none, .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var content: some ProposalElementGroup {
        let theme = theme, alignments = alignments, header = header, rows = rows
        func column(_ index: Int) -> HorizontalAlignment {
            index < alignments.count ? Self.alignment(alignments[index]) : .leading
        }
        return ProposalScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: theme.tableColumnSpacing,
                 verticalSpacing: theme.tableRowSpacing) {
                GridRow {
                    ForEach(Array(header.indices), id: \.self) { index in
                        MarkdownInlineLowering.text(header[index], theme: theme, font: theme.bodyFont, weight: .bold)
                            .fixedSize(horizontal: true, vertical: false)
                            .gridColumnAlignment(column(index))
                    }
                }
                ForEach(Array(rows.indices), id: \.self) { row in
                    MarkdownTableRule(color: theme.tableRule)
                    GridRow {
                        ForEach(Array(rows[row].indices), id: \.self) { index in
                            MarkdownInlineLowering.text(rows[row][index], theme: theme, font: theme.bodyFont)
                                .fixedSize(horizontal: true, vertical: false)
                                .gridColumnAlignment(column(index))
                        }
                    }
                }
            }
        }
    }

    static func == (l: MarkdownTable, r: MarkdownTable) -> Bool {
        l.alignments == r.alignments && l.header == r.header && l.rows == r.rows && l.theme == r.theme
    }
}

/// A one-point rule across a table.
struct MarkdownTableRule: Component, ProposalElementGroup, @MainActor Equatable {
    let color: Color

    var content: some ProposalElementGroup {
        color.frame(height: Pixels(1))
    }
}
