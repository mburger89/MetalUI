import MetalUICore
import MetalUIMarkdown

/// A GFM table: a `Grid`, columns aligned by the delimiter row, in a horizontal scroller only when the theme asks
/// (`BM-E`, `BM-H`).
///
/// The header's cells are bold. A full-width rule follows the header and every body row but the last. Cell text
/// wraps in a table that does not scroll; in one that does it stays whole and the table scrolls sideways.
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
        let scrolls = theme.tableScrolls
        let grid = Grid(alignment: .topLeading, horizontalSpacing: theme.tableColumnSpacing,
                        verticalSpacing: theme.tableRowSpacing) {
            GridRow {
                ForEach(Array(header.indices), id: \.self) { index in
                    MarkdownInlineLowering.text(header[index], theme: theme, font: theme.bodyFont, weight: .bold)
                        .gridColumnAlignment(column(index))
                }
            }
            ForEach(Array(rows.indices), id: \.self) { row in
                MarkdownTableRule(color: theme.tableRule)
                GridRow {
                    ForEach(Array(rows[row].indices), id: \.self) { index in
                        MarkdownInlineLowering.text(rows[row][index], theme: theme, font: theme.bodyFont)
                                .gridColumnAlignment(column(index))
                    }
                }
            }
        }
        return VStack(alignment: .leading, spacing: Pixels(0)) {
            if scrolls {
                ProposalScrollView(.horizontal) { grid }
            } else {
                grid
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
