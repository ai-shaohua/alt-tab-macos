import Cocoa

/// Column names and the drop highlight behind the tiles. Clicks pass through: the event tap decides
/// what a press does, and this view only draws.
final class ScreenColumnChrome: FlippedView {
    private var columnFrames = [CGRect]()
    private var labels = [NSTextField]()
    private var highlighted: Int?

    func show(_ columns: [ScreenColumnLayout.PlacedColumn], xOffset: CGFloat) {
        columnFrames = columns.map { $0.frame.offsetBy(dx: xOffset, dy: 0) }
        while labels.count < columns.count { labels.append(makeLabel()) }
        for (index, column) in columns.enumerated() {
            let label = labels[index]
            label.isHidden = false
            if label.stringValue != column.name { label.stringValue = column.name }
            label.font = Appearance.font
            label.textColor = Appearance.fontColor
            var header = column.headerFrame
            header.origin.x += xOffset
            label.frame = header.insetBy(dx: 4, dy: 0)
        }
        for label in labels.dropFirst(columns.count) { label.isHidden = true }
        if let highlighted, highlighted >= columnFrames.count { self.highlighted = nil }
        needsDisplay = true
    }

    func highlight(_ index: Int?) {
        let next = index.flatMap { $0 >= 0 && $0 < columnFrames.count ? $0 : nil }
        guard next != highlighted else { return }
        highlighted = next
        needsDisplay = true
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        for (index, frame) in columnFrames.enumerated() where dirtyRect.intersects(frame) {
            var band = frame
            band.size.height = min(ScreenColumnLayout.headerHeight, frame.height)
            Appearance.fontColor.withAlphaComponent(index == highlighted ? 0.18 : 0.08).setFill()
            NSBezierPath(roundedRect: band.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            Appearance.fontColor.withAlphaComponent(index == highlighted ? 0.45 : 0.16).setStroke()
            let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            outline.lineWidth = index == highlighted ? 2 : 1
            outline.stroke()
        }
    }

    private func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.font = Appearance.font
        label.textColor = Appearance.fontColor
        addSubview(label)
        return label
    }
}
