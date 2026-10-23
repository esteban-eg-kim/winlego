import SwiftUI
import WinlegoCore

/// The editor's working copy. An object rather than `@State`, because the Command Line
/// Tools ship no SwiftUI macro plugin and `@State` is a macro in this SDK.
@MainActor
final class LayoutEditorModel: ObservableObject {
    @Published var draft = Presets.fullScreen
    @Published var selected: NodePath? = []
    @Published var portrait = false

    func load(_ layout: WinlegoCore.Layout) {
        draft = layout
        selected = []
    }
}

/// Draw a layout: pick a zone, split it top/bottom or left/right, drag the dividers,
/// name the zones, save.
struct LayoutEditorView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: LayoutEditorModel
    var onClose: () -> Void

    private var draft: WinlegoCore.Layout {
        get { editor.draft }
        nonmutating set { editor.draft = newValue }
    }
    private var selected: NodePath? {
        get { editor.selected }
        nonmutating set { editor.selected = newValue }
    }

    private var selectedZone: Zone? {
        selected.flatMap { path in draft.zones.first { $0.path == path } }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("Layout name", text: $editor.draft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Spacer()
                Picker("Preview", selection: $editor.portrait) {
                    Text("Landscape").tag(false)
                    Text("Portrait").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            canvas
                .aspectRatio(editor.portrait ? 9 / 16 : 16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Button {
                    split(.horizontal)
                } label: { Label("Split Left | Right", systemImage: "rectangle.split.2x1") }
                Button {
                    split(.vertical)
                } label: { Label("Split Top / Bottom", systemImage: "rectangle.split.1x2") }
                Button(role: .destructive) {
                    guard let path = selected else { return }
                    draft = draft.removing(path)
                    selected = draft.zones.first?.path
                } label: { Label("Remove Zone", systemImage: "trash") }
                    .disabled(selected == nil || draft.zones.count < 2)
                Spacer()
                if let zone = selectedZone {
                    TextField("Zone name", text: Binding(
                        get: { zone.name },
                        set: { draft = draft.renaming(zone.path, to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }
            }
            .disabled(selected == nil)

            HStack {
                Text("Click a zone to select it. Drag the handles to change the split.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.saveCustomLayout(draft)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
    }

    private func split(_ axis: WinlegoCore.Axis) {
        guard let path = selected else { return }
        draft = draft.splitting(path, axis: axis)
        selected = path + [0]
    }

    private var canvas: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.4))
                ForEach(draft.zones, id: \.path) { zone in
                    let r = zone.rect
                    let isSelected = zone.path == selected
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.55) : Color.accentColor.opacity(0.22))
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Color.accentColor : Color.accentColor.opacity(0.5), lineWidth: isSelected ? 3 : 1)
                        Text(zone.name).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .frame(width: max(w * r.width - 6, 0), height: max(h * r.height - 6, 0))
                    .offset(x: w * r.x + 3, y: h * r.y + 3)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = zone.path }
                }
                ForEach(draft.dividers, id: \.path) { divider in
                    let line = divider.line
                    let region = divider.region
                    let isVertical = divider.axis == .horizontal
                    ZStack {
                        Rectangle().fill(Color.clear)
                        Capsule().fill(Color.white).frame(width: isVertical ? 6 : nil, height: isVertical ? nil : 6)
                            .shadow(radius: 1)
                        Circle().fill(Color.accentColor).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .frame(width: isVertical ? 18 : w * line.width, height: isVertical ? h * line.height : 18)
                    .offset(x: w * line.x - (isVertical ? 9 : 0), y: h * line.y - (isVertical ? 0 : 9))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                let ratio = isVertical
                                    ? (value.location.x / w - region.x) / region.width
                                    : (value.location.y / h - region.y) / region.height
                                draft = draft.settingRatio(ratio, at: divider.path)
                            }
                    )
                }
            }
            .coordinateSpace(name: "canvas")
        }
    }
}
