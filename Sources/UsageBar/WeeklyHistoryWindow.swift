import AppKit
import UsageBarCore

/// An on-demand utility panel; creating the menu-bar app never opens a window.
final class WeeklyHistoryWindowController: NSWindowController {
    private var history: [String: [UsageHistorySample]] = [:]
    private var text = Localizer(language: .english)
    private var recording = false
    private var selectedKey: String?
    private let providerSelector = NSSegmentedControl()
    private let sampleSlider = HistorySampleSlider()
    private let readout = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "—")
    private var samples: [UsageHistorySample] = []
    private var hasBuilt = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 620, height: 470)
        panel.center()
        super.init(window: panel)
        providerSelector.segmentCount = 2
        providerSelector.setLabel("Codex", forSegment: 0)
        providerSelector.setLabel("Claude Code", forSegment: 1)
        providerSelector.segmentStyle = .rounded
        providerSelector.trackingMode = .selectOne
        providerSelector.target = self
        providerSelector.action = #selector(selectProvider)
        sampleSlider.target = self
        sampleSlider.action = #selector(selectSample)
        providerSelector.widthAnchor.constraint(equalToConstant: 220).isActive = true
        sampleSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(history: [String: [UsageHistorySample]], text: Localizer, recording: Bool) {
        guard !hasBuilt || self.history != history || self.text.language != text.language || self.recording != recording else { return }
        hasBuilt = true
        self.history = history
        self.text = text
        self.recording = recording
        rebuild()
    }

    private func rebuild() {
        guard let window else { return }
        window.title = text.weeklyHistoryTitle
        let root = NSView()
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 24
            glass.contentView = root
            window.contentView = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            root.frame = material.bounds
            root.autoresizingMask = [.width, .height]
            material.addSubview(root)
            window.contentView = material
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        func label(_ value: String, size: CGFloat = 12, secondary: Bool = false) -> NSTextField {
            let field = NSTextField(labelWithString: value)
            field.font = .systemFont(ofSize: size)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            return field
        }
        func row(_ leading: NSView, _ trailing: NSView) -> NSStackView {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [leading, spacer, trailing])
            row.alignment = .centerY
            row.spacing = 12
            return row
        }
        func add(_ view: NSView, to parent: NSStackView) {
            parent.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        }

        let title = label(text.weeklyHistoryTitle, size: 20)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let status = label(recording ? text.weeklyHistoryRecording : text.weeklyHistoryPaused, size: 11, secondary: true)
        status.toolTip = text.weeklyHistoryHelp
        add(row(title, status), to: stack)

        let keys = ["Codex|weekly", "Claude Code|weekly"]
        selectedKey = selectedKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first
        if let selectedKey, let index = keys.firstIndex(of: selectedKey) { providerSelector.selectedSegment = index }
        providerSelector.font = .systemFont(ofSize: 12)
        providerSelector.setAccessibilityLabel(text.historySeries)
        samples = selectedKey.flatMap { history[$0] } ?? []
        let model = UsageHistoryChartModel(samples: samples, startsAtLatestReset: false)
        let range = label(text.usageHistoryRange(model.recordedDuration), secondary: true)
        range.isHidden = samples.isEmpty
        add(row(providerSelector, range), to: stack)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 16
        card.borderWidth = 0
        card.fillColor = .labelColor.withAlphaComponent(0.035)
        card.contentViewMargins = .zero
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 12
        body.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        card.contentView = content
        content.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        add(label(text.historyRemaining, size: 11, secondary: true), to: body)
        percentLabel.setAccessibilityLabel(text.historyRemaining)
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        readout.textColor = .secondaryLabelColor
        add(row(percentLabel, readout), to: body)

        let plot = NSView()
        plot.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        if samples.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: text.weeklyHistoryEmpty)
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            plot.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: plot.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: plot.centerYAnchor),
                empty.widthAnchor.constraint(lessThanOrEqualTo: plot.widthAnchor, constant: -80)
            ])
        } else {
            let graph = UsageSparklineView(frame: .zero, samples: samples, lineColor: .controlAccentColor, startsAtLatestReset: false)
            graph.translatesAutoresizingMaskIntoConstraints = false
            plot.addSubview(graph)
            NSLayoutConstraint.activate([
                graph.leadingAnchor.constraint(equalTo: plot.leadingAnchor, constant: 34),
                graph.trailingAnchor.constraint(equalTo: plot.trailingAnchor),
                graph.topAnchor.constraint(equalTo: plot.topAnchor, constant: 6),
                graph.bottomAnchor.constraint(equalTo: plot.bottomAnchor, constant: -6)
            ])
            for (value, fraction) in [(100, CGFloat(0)), (50, CGFloat(0.5)), (0, CGFloat(1))] {
                let axis = label("\(value)", size: 10, secondary: true)
                axis.translatesAutoresizingMaskIntoConstraints = false
                plot.addSubview(axis)
                axis.leadingAnchor.constraint(equalTo: plot.leadingAnchor).isActive = true
                let guide = NSLayoutGuide()
                plot.addLayoutGuide(guide)
                guide.topAnchor.constraint(equalTo: graph.topAnchor).isActive = true
                guide.heightAnchor.constraint(equalTo: graph.heightAnchor, multiplier: fraction).isActive = true
                axis.centerYAnchor.constraint(equalTo: guide.bottomAnchor).isActive = true
            }
            graph.setAccessibilityLabel(providerSelector.label(forSegment: providerSelector.selectedSegment) ?? text.weeklyHistoryTitle)
            graph.setAccessibilityValue(text.usageHistoryRange(model.recordedDuration))
            graph.onHoveredSampleChanged = { [weak self, weak graph] sample in
                guard let self else { return }
                if let sample { self.showSample(sample) } else { self.selectSample() }
                graph?.setAccessibilityValue("\(self.readout.stringValue) · \(self.percentLabel.stringValue)")
            }
        }
        add(plot, to: body)
        if let first = samples.first, let last = samples.last {
            add(row(label(text.historyDate(first.recordedAt), size: 10, secondary: true),
                    label(text.historyDate(last.recordedAt), size: 10, secondary: true)), to: body)
        }
        add(card, to: stack)

        samples = model.displaySamples
        sampleSlider.minValue = 0
        sampleSlider.maxValue = Double(max(1, samples.count - 1))
        sampleSlider.doubleValue = Double(max(0, samples.count - 1))
        sampleSlider.isEnabled = !samples.isEmpty
        sampleSlider.controlSize = .small
        sampleSlider.setAccessibilityLabel(text.historySample)
        sampleSlider.toolTip = text.historySample
        let footer = label(text.historyLocal, size: 11, secondary: true)
        footer.toolTip = text.weeklyHistoryHelp
        add(row(footer, sampleSlider), to: stack)
        selectSample()
    }

    @objc private func selectProvider() {
        let keys = ["Codex|weekly", "Claude Code|weekly"]
        guard keys.indices.contains(providerSelector.selectedSegment) else { return }
        selectedKey = keys[providerSelector.selectedSegment]
        rebuild()
    }

    @objc private func selectSample() {
        guard !samples.isEmpty else { percentLabel.stringValue = "—"; readout.stringValue = text.noData; return }
        showSample(samples[min(samples.count - 1, max(0, Int(sampleSlider.doubleValue.rounded())))])
    }

    private func showSample(_ sample: UsageHistorySample) {
        percentLabel.stringValue = text.language == .turkish ? "%\(sample.remainingPercent)" : "\(sample.remainingPercent)%"
        readout.stringValue = text.historyDate(sample.recordedAt)
        percentLabel.setAccessibilityValue(text.remaining(sample.remainingPercent))
        sampleSlider.setAccessibilityHelp("\(readout.stringValue) · \(text.remaining(sample.remainingPercent))")
    }
}

private final class HistorySampleSlider: NSSlider {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, [123, 124, 125, 126].contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        let step = [123, 125].contains(event.keyCode) ? -1.0 : 1.0
        doubleValue = min(maxValue, max(minValue, doubleValue.rounded() + step))
        sendAction(action, to: target)
    }
}
