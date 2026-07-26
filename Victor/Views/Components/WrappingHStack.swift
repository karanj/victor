import SwiftUI

/// Flow layout: lays subviews out left-to-right, wrapping when the next one
/// would overrun the proposed width. SwiftUI ships no wrapping stack on
/// macOS 14, and `ConfigFieldView`'s `.stringArray` chip rows need one.
///
/// Claims the full proposed width when offered, else the natural single-line
/// width — so `sizeThatFits` probes don't collapse it to one column.
struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4
    /// Trailing by default, to match the trailing-aligned controls on every
    /// other `LabeledContent` row.
    var alignment: HorizontalAlignment = .trailing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }

        let maxWidth = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? sizes.reduce(0) { $0 + $1.width } + horizontalSpacing * CGFloat(sizes.count - 1)

        let lines = lineBreaks(sizes: sizes, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, lines.count - 1))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return }

        let lines = lineBreaks(sizes: sizes, maxWidth: bounds.width)
        var y = bounds.minY

        for line in lines {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .center: x = bounds.minX + (bounds.width - line.width) / 2
            default: x = bounds.maxX - line.width
            }

            for index in line.range {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += line.height + verticalSpacing
        }
    }

    // MARK: - Line breaking

    private func lineBreaks(sizes: [CGSize], maxWidth: CGFloat) -> [WrappingHStackLine] {
        WrappingHStackLine.breakIntoLines(sizes: sizes, maxWidth: maxWidth, spacing: horizontalSpacing)
    }
}

/// One laid-out row. Non-nested so the line-breaking below is unit testable
/// without a `Layout.Subviews` proxy in scope.
struct WrappingHStackLine: Equatable {
    var range: Range<Int>
    var width: CGFloat
    var height: CGFloat

    /// Greedy first-fit: each subview goes on the current line unless it
    /// would overrun `maxWidth`, in which case it starts a new one. A single
    /// subview wider than `maxWidth` gets its own line rather than looping.
    static func breakIntoLines(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [WrappingHStackLine] {
        var lines: [WrappingHStackLine] = []
        var start = 0
        var width: CGFloat = 0
        var height: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let needed = width == 0 ? size.width : width + spacing + size.width
            if width > 0 && needed > maxWidth {
                lines.append(WrappingHStackLine(range: start..<index, width: width, height: height))
                start = index
                width = size.width
                height = size.height
            } else {
                width = needed
                height = max(height, size.height)
            }
        }

        if start < sizes.count {
            lines.append(WrappingHStackLine(range: start..<sizes.count, width: width, height: height))
        }
        return lines
    }
}
