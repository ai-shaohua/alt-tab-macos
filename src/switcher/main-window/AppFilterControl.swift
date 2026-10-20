import Cocoa
import Carbon.HIToolbox.Events

/// Popup-styled button. The panel's event tap deletes presses inside the switcher, so this click
/// is only delivered because `CursorEvents` passes the chrome through. `mouseDown` does not call
/// super: the real menu is the filter dropdown, not AppKit's item list.
final class AppFilterButton: NSPopUpButton {
    convenience init() {
        self.init(frame: .zero, pullsDown: false)
    }

    override init(frame frameRect: NSRect, pullsDown: Bool) {
        super.init(frame: frameRect, pullsDown: pullsDown)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var acceptsFirstResponder: Bool { false }

    func applyChromeStyle() {
        bezelStyle = .rounded
        font = .systemFont(ofSize: NSFont.systemFontSize)
        if #available(macOS 26.0, *) { controlSize = .extraLarge }
        else if #available(macOS 13.0, *) { controlSize = .large }
        if numberOfItems == 0 { addItem(withTitle: " ") }
        guard let popupCell = cell as? NSPopUpButtonCell else { return }
        popupCell.imagePosition = .imageLeading
        popupCell.lineBreakMode = .byTruncatingTail
    }

    func show(title: String, image: NSImage?) {
        if numberOfItems == 0 { addItem(withTitle: title) }
        let shown = item(at: 0)
        guard shown?.title != title || shown?.image !== image else { return }
        shown?.title = title
        shown?.image = image
        selectItem(at: 0)
    }

    override func mouseDown(with event: NSEvent) {
        TilesView.toggleAppFilter()
    }
}

/// The list under the app button: a name field, then the apps that contain that name.
final class AppFilterDropdown: NSVisualEffectView {
    let filterField = NSSearchField()
    var onPick: ((AppFilterRow) -> Void)?
    var onContentChanged: (() -> Void)?
    private let scrollView = NSScrollView()
    private let list = AppFilterListView()
    private let pad = CGFloat(8)
    private let fieldHeight = CGFloat(28)
    private var choices = [AppFilterChoice]()
    private var iconCache = [pid_t: NSImage]()
    static let allAppsImage: NSImage? = {
        let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }()

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        material = .popover
        blendingMode = .withinWindow
        state = .active
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        isHidden = true
        autoresizesSubviews = false
        configureFilterField()
        configureList()
        updateBorder()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    func show(choices: [AppFilterChoice], icons: [pid_t: CGImage], selectedPid: pid_t?, allTitle: String) {
        self.choices = choices
        absorbIcons(icons)
        list.allTitle = allTitle
        list.icons = iconsForChoices(choices)
        filterField.stringValue = ""
        applyQuery("", preferredPid: selectedPid, prefer: true)
    }

    func updateChoices(_ choices: [AppFilterChoice], icons: [pid_t: CGImage], allTitle: String) {
        let hasHighlight = list.rows.indices.contains(list.selectedIndex)
        let highlighted = hasHighlight ? list.rows[list.selectedIndex].pid : nil
        guard choices != self.choices || allTitle != list.allTitle else { return }
        self.choices = choices
        absorbIcons(icons)
        list.allTitle = allTitle
        list.icons = iconsForChoices(choices)
        applyQuery(filterField.stringValue, preferredPid: highlighted, prefer: hasHighlight)
    }

    func buttonImage(for pid: pid_t?, icons: [pid_t: CGImage]) -> NSImage? {
        guard let pid else { return Self.allAppsImage }
        if let cached = iconCache[pid] { return cached }
        guard let image = icons[pid] else { return nil }
        let sized = NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
        iconCache[pid] = sized
        return sized
    }

    var filterFieldHasMarkedText: Bool {
        (filterField.currentEditor() as? NSTextView)?.hasMarkedText() == true
    }

    var preferredHeight: CGFloat {
        let visibleRows = min(max(list.rows.count, 1), 8)
        return pad + fieldHeight + 6 + CGFloat(visibleRows) * AppFilterListView.rowHeight + pad
    }

    func moveSelection(_ delta: Int) {
        guard !list.rows.isEmpty else { return }
        let next = min(max(list.selectedIndex + delta, 0), list.rows.count - 1)
        list.setSelection(next)
        scrollSelectionVisible()
    }

    func confirmSelection() {
        guard list.rows.indices.contains(list.selectedIndex) else { return }
        onPick?(list.rows[list.selectedIndex])
    }

    override func layout() {
        super.layout()
        let width = bounds.width - pad * 2
        filterField.frame = NSRect(x: pad, y: bounds.height - pad - fieldHeight, width: width, height: fieldHeight)
        let scrollTop = filterField.frame.minY - 4
        scrollView.frame = NSRect(x: pad, y: pad, width: width, height: max(0, scrollTop - pad))
        scrollView.layoutSubtreeIfNeeded()
        list.frame.size.width = max(scrollView.contentSize.width, width)
        list.reloadIfNeeded()
        scrollSelectionVisible()
    }

    private func configureFilterField() {
        filterField.placeholderString = NSLocalizedString("Filter by app", comment: "Placeholder in the app picker")
        filterField.sendsSearchStringImmediately = true
        filterField.sendsWholeSearchString = true
        filterField.bezelStyle = .roundedBezel
        filterField.controlSize = .regular
        filterField.font = .systemFont(ofSize: 13)
        filterField.target = self
        filterField.action = #selector(filterEdited)
        addSubview(filterField)
        NotificationCenter.default.addObserver(self, selector: #selector(filterEdited), name: NSControl.textDidChangeNotification, object: filterField)
    }

    private func configureList() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = list
        addSubview(scrollView)
        list.onPick = { [weak self] row in self?.onPick?(row) }
    }

    private func updateBorder() {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @objc private func filterEdited() {
        applyQuery(filterField.stringValue)
    }

    private func applyQuery(_ query: String, preferredPid: pid_t? = nil, prefer: Bool = false) {
        list.rows = AppFilter.rows(choices: choices, query: query, allTitle: list.allTitle)
        if prefer, let index = list.rows.firstIndex(where: { $0.pid == preferredPid }) {
            list.selectedIndex = index
        } else {
            list.selectedIndex = list.rows.isEmpty ? -1 : 0
        }
        list.invalidate()
        list.reloadIfNeeded()
        scrollSelectionVisible()
        onContentChanged?()
    }

    private func scrollSelectionVisible() {
        guard list.selectedIndex >= 0 else { return }
        let y = CGFloat(list.selectedIndex) * AppFilterListView.rowHeight
        list.scrollToVisible(CGRect(x: 0, y: y, width: max(list.bounds.width, 1), height: AppFilterListView.rowHeight))
    }

    private func absorbIcons(_ icons: [pid_t: CGImage]) {
        for (pid, image) in icons where iconCache[pid] == nil {
            iconCache[pid] = NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
        }
    }

    private func iconsForChoices(_ choices: [AppFilterChoice]) -> [pid_t: NSImage] {
        var images = [pid_t: NSImage]()
        for choice in choices {
            if let image = iconCache[choice.pid] { images[choice.pid] = image }
        }
        return images
    }
}

private final class AppFilterListView: FlippedView {
    static let rowHeight = CGFloat(28)
    var rows = [AppFilterRow]()
    var icons = [pid_t: NSImage]()
    var allTitle = ""
    var selectedIndex = 0
    var onPick: ((AppFilterRow) -> Void)?
    private var rendered = [AppFilterRow]()
    private var renderedSelection = Int.min
    private var renderedWidth = CGFloat(-1)

    func setSelection(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        invalidate()
        reloadIfNeeded()
    }

    func invalidate() {
        renderedWidth = -1
    }

    func reloadIfNeeded() {
        guard rows != rendered || selectedIndex != renderedSelection || bounds.width != renderedWidth else { return }
        rendered = rows
        renderedSelection = selectedIndex
        renderedWidth = bounds.width
        rebuild()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        highlight(row(at: event))
    }

    override func mouseDown(with event: NSEvent) {
        let index = row(at: event)
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        onPick?(rows[index])
    }

    private func highlight(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        setSelection(index)
    }

    private func row(at event: NSEvent) -> Int {
        let local = convert(event.locationInWindow, from: nil)
        return Int(floor(local.y / Self.rowHeight))
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        frame.size.height = CGFloat(max(rows.count, 1)) * Self.rowHeight
        for (index, row) in rows.enumerated() {
            addSubview(rowView(row, index: index))
        }
    }

    private func rowView(_ row: AppFilterRow, index: Int) -> NSView {
        let width = bounds.width
        let view = NSView(frame: CGRect(x: 4, y: CGFloat(index) * Self.rowHeight + 2, width: max(0, width - 8), height: Self.rowHeight - 4))
        if index == selectedIndex {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
            view.layer?.cornerRadius = 6
        }
        let iconView = NSImageView(frame: CGRect(x: 6, y: (view.bounds.height - 16) / 2, width: 16, height: 16))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = icon(for: row)
        if case .all = row {
            iconView.contentTintColor = index == selectedIndex ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
        let label = NSTextField(labelWithString: title(for: row))
        label.font = .systemFont(ofSize: 13)
        label.textColor = index == selectedIndex ? .alternateSelectedControlTextColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.frame = CGRect(x: 28, y: (view.bounds.height - 16) / 2, width: max(0, view.bounds.width - 36), height: 16)
        view.addSubview(iconView)
        view.addSubview(label)
        return view
    }

    private func title(for row: AppFilterRow) -> String {
        switch row {
        case .all: return allTitle
        case .app(let choice): return choice.title
        }
    }

    private func icon(for row: AppFilterRow) -> NSImage? {
        switch row {
        case .all: return AppFilterDropdown.allAppsImage
        case .app(let choice): return icons[choice.pid]
        }
    }
}

extension TilesView {
    static var isAppFilterOpen: Bool { appFilterDropdown.superview != nil && !appFilterDropdown.isHidden }

    static func configureAppFilterControl() {
        appFilterButton.applyChromeStyle()
        appFilterDropdown.onPick = { applyAppFilter($0) }
        appFilterDropdown.onContentChanged = { placeAppFilterDropdown() }
    }

    static func toggleAppFilter() {
        if isAppFilterOpen { closeAppFilter() } else { openAppFilter() }
    }

    static func focusSearchFromClick() {
        if isAppFilterOpen { closeAppFilter() }
        guard !isSearchEditing else { return }
        enableSearchEditing()
    }

    /// Hides the list immediately. Resigning its text field deactivates the system text-input
    /// context, the same synchronous XPC as taking the search caret (#5981), so that happens a turn later.
    static func closeAppFilter() {
        guard isAppFilterOpen else { return }
        appFilterDropdown.isHidden = true
        DispatchQueue.main.async { finishCloseAppFilter() }
    }

    static func handleAppFilterKeyDown(_ event: NSEvent) -> Bool {
        guard isAppFilterOpen, !appFilterDropdown.filterFieldHasMarkedText else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape:
            closeAppFilter()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            appFilterDropdown.confirmSelection()
            return true
        case kVK_UpArrow:
            appFilterDropdown.moveSelection(-1)
            return true
        case kVK_DownArrow:
            appFilterDropdown.moveSelection(1)
            return true
        case kVK_Tab:
            return true
        default:
            return false
        }
    }

    static func updateAppFilterButton() {
        let built = appFilterChoices()
        let selected = AppFilter.resolvedSelection(SwitcherSession.current?.appFilterPid, choices: built.choices)
        let title = built.choices.first { $0.pid == selected }?.title ?? allAppsTitle
        appFilterButton.show(title: title, image: appFilterDropdown.buttonImage(for: selected, icons: built.icons))
        guard isAppFilterOpen else { return }
        appFilterDropdown.updateChoices(built.choices, icons: built.icons, allTitle: allAppsTitle)
    }

    static func placeAppFilterDropdown() {
        guard isAppFilterOpen, let host = contentView?.hostView else { return }
        host.addSubview(appFilterDropdown)
        let button = appFilterButton
        let width = min(max(button.frame.width, 220), max(0, host.bounds.width - Appearance.windowPadding * 2))
        var x = button.frame.maxX - width
        let minX = Appearance.windowPadding
        if x < minX { x = minX }
        let available = max(0, button.frame.minY - 8)
        let height = min(appFilterDropdown.preferredHeight, available)
        let y = button.frame.minY - 4 - height
        appFilterDropdown.frame = CGRect(x: x, y: max(4, y), width: width, height: max(height, 0))
    }

    private static var allAppsTitle: String { NSLocalizedString("All apps", comment: "") }

    private static var panelAcceptedMouseMoved: Bool?

    private static func openAppFilter() {
        guard SwitcherSession.isActive, let host = contentView?.hostView else { return }
        if panelAcceptedMouseMoved == nil { panelAcceptedMouseMoved = TilesPanel.shared.acceptsMouseMovedEvents }
        TilesPanel.shared.acceptsMouseMovedEvents = true
        let built = appFilterChoices()
        appFilterDropdown.isHidden = false
        host.addSubview(appFilterDropdown)
        appFilterDropdown.show(choices: built.choices, icons: built.icons, selectedPid: SwitcherSession.current?.appFilterPid, allTitle: allAppsTitle)
        placeAppFilterDropdown()
        DispatchQueue.main.async {
            guard isAppFilterOpen, SwitcherSession.isActive else { return }
            TilesPanel.shared.makeFirstResponder(appFilterDropdown.filterField)
        }
    }

    private static func applyAppFilter(_ row: AppFilterRow) {
        let pid = row.pid
        closeAppFilter()
        guard SwitcherSession.current?.appFilterPid != pid else { return }
        Windows.updateAppFilter(pid)
        App.refreshUi(true)
    }

    private static func appFilterChoices() -> (choices: [AppFilterChoice], icons: [pid_t: CGImage]) {
        var seen = Set<pid_t>()
        var apps = [(pid: pid_t, name: String)]()
        var icons = [pid_t: CGImage]()
        for window in Windows.list where window.shouldShowTheUser {
            let pid = window.application.pid
            guard seen.insert(pid).inserted else { continue }
            apps.append((pid, window.application.localizedName ?? ""))
            if let icon = window.application.icon { icons[pid] = icon }
        }
        return (AppFilter.choices(apps, unnamed: NSLocalizedString("App", comment: "Application with no localized name")), icons)
    }

    private static func finishCloseAppFilter() {
        guard appFilterDropdown.isHidden else { return }
        let field = appFilterDropdown.filterField
        let editor = field.currentEditor()
        let heldCaret = TilesPanel.shared.firstResponder === field || TilesPanel.shared.firstResponder === editor
        field.stringValue = ""
        appFilterDropdown.removeFromSuperview()
        if let accepted = panelAcceptedMouseMoved {
            TilesPanel.shared.acceptsMouseMovedEvents = accepted
            panelAcceptedMouseMoved = nil
        }
        guard heldCaret, SwitcherSession.isActive, isSearchEditing else { return }
        giveTheFieldTheCaretNow()
    }
}

final class SwitcherSearchField: NSSearchField {
    override func mouseDown(with event: NSEvent) {
        TilesView.focusSearchFromClick()
        super.mouseDown(with: event)
    }
}
