import Cocoa

/// Column names and the drop highlight, drawn above the tiles. Tile layers paint outside their frames
/// and would cover a header underneath. Clicks pass through: the event tap decides what a press does.
final class ScreenColumnChrome: FlippedView {
    private var columnFrames = [CGRect]()
    private var names = [String]()
    private var highlighted: Int?

    func show(_ columns: [ScreenColumnLayout.PlacedColumn], xOffset: CGFloat) {
        columnFrames = columns.map { $0.frame.offsetBy(dx: xOffset, dy: 0) }
        names = columns.map { $0.name }
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
            let band = headerBand(frame)
            Appearance.fontColor.withAlphaComponent(index == highlighted ? 0.22 : 0.14).setFill()
            NSBezierPath(roundedRect: band.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            Appearance.fontColor.withAlphaComponent(index == highlighted ? 0.45 : 0.16).setStroke()
            let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            outline.lineWidth = index == highlighted ? 2 : 1
            outline.stroke()
            if index < names.count { drawName(names[index], in: band) }
        }
    }

    private func headerBand(_ frame: CGRect) -> CGRect {
        var band = frame
        band.size.height = min(ScreenColumnLayout.headerHeight, frame.height)
        return band
    }

    private func drawName(_ name: String, in band: CGRect) {
        guard !name.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Appearance.font.pointSize, weight: .semibold),
            .foregroundColor: Appearance.fontColor,
            .paragraphStyle: paragraph,
        ]
        let text = name as NSString
        let used = text.boundingRect(with: CGSize(width: max(0, band.width - 8), height: band.height),
            options: [.usesLineFragmentOrigin], attributes: attributes)
        var rect = band.insetBy(dx: 4, dy: 0)
        rect.origin.y += max(0, (rect.height - ceil(used.height)) / 2)
        rect.size.height = ceil(used.height)
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}
