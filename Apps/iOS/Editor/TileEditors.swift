import CCCore
import SwiftUI

// MARK: - Tile inspector

struct TileInspector: View {
    let pageID: String
    let tileID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tile: Tile?
    @State private var editingKey: ButtonDef?

    var body: some View {
        NavigationStack {
            CCForm {
                if let binding = Binding($tile) {
                    content(binding)
                    Section("Size") {
                        Stepper("Width: \(binding.wrappedValue.cols) of 12 columns", value: binding.cols, in: 1...12)
                        Stepper("Height: \(binding.wrappedValue.rows) rows", value: binding.rows, in: 1...12)
                    }
                    Section {
                        Button("Duplicate Tile", systemImage: "plus.square.on.square") { duplicate() }
                        Button("Remove Tile", systemImage: "trash", role: .destructive) { remove() }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save() }.bold() }
            }
            .sheet(item: $editingKey) { key in
                KeyEditor(pageID: pageID, tileID: tileID, key: key) { updated in
                    replaceKey(updated)
                } onDelete: { id in
                    removeKey(id)
                }
            }
        }
        .onAppear { tile = model.workspace.page(pageID)?.tiles.first { $0.id == tileID } }
    }

    private var title: String {
        switch tile?.content {
        case .widget(let kind): kind.title
        case .keys(let group): group.title ?? "Keys"
        case .appKeys: "App Keys"
        default: "Tile"
        }
    }

    @ViewBuilder
    private func content(_ tile: Binding<Tile>) -> some View {
        switch tile.wrappedValue.content {
        case .widget(let kind):
            Section("Widget") {
                Picker("Shows", selection: Binding(get: { kind }, set: { tile.wrappedValue.content = .widget($0) })) {
                    ForEach(WidgetKind.Category.allCases, id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(WidgetKind.allCases.filter { $0.category == category }, id: \.self) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    }
                }
                LabeledContent("Suggested size", value: "\(kind.defaultSize.cols) × \(kind.defaultSize.rows)")
            }
        case .keys(let group):
            Section("Panel") {
                TextField("Title", text: Binding(get: { group.title ?? "" }, set: { value in
                    var copy = group
                    copy.title = value.isEmpty ? nil : value
                    tile.wrappedValue.content = .keys(copy)
                }))
                Picker("Style", selection: Binding(get: { group.style }, set: { value in
                    var copy = group
                    copy.style = value
                    tile.wrappedValue.content = .keys(copy)
                })) {
                    ForEach(KeyStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Keys") {
                ForEach(group.keys) { key in
                    Button {
                        editingKey = key
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: key.symbol ?? "circle.dashed")
                                .foregroundStyle(CC.keyTint(key.color))
                                .frame(width: 26)
                            VStack(alignment: .leading) {
                                Text(key.label).foregroundStyle(CC.text)
                                Text(key.action.summary).font(.caption).foregroundStyle(CC.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CC.text3)
                        }
                    }
                }
                .onMove { from, to in
                    var copy = group
                    copy.keys.move(fromOffsets: from, toOffset: to)
                    tile.wrappedValue.content = .keys(copy)
                }
                .onDelete { offsets in
                    var copy = group
                    copy.keys.remove(atOffsets: offsets)
                    tile.wrappedValue.content = .keys(copy)
                }
                Button("Add Key", systemImage: "plus") {
                    var copy = group
                    let key = ButtonDef(label: "New Key", symbol: "square.dashed", action: .none)
                    copy.keys.append(key)
                    tile.wrappedValue.content = .keys(copy)
                    editingKey = key
                }
            }
        case .appKeys(let limit):
            Section("App keys") {
                Stepper("Show up to \(limit) keys", value: Binding(get: { limit }, set: { tile.wrappedValue.content = .appKeys(limit: $0) }), in: 1...16)
                Text("Shows the keys of whichever app is in front on your Mac.")
                    .font(.caption)
                    .foregroundStyle(CC.text2)
            }
        case .spacer:
            Section { Text("An empty spacer tile.") }
        }
    }

    private func replaceKey(_ key: ButtonDef) {
        guard case .keys(var group) = tile?.content else { return }
        if let index = group.keys.firstIndex(where: { $0.id == key.id }) {
            group.keys[index] = key
        } else {
            group.keys.append(key)
        }
        tile?.content = .keys(group)
    }

    private func removeKey(_ id: String) {
        guard case .keys(var group) = tile?.content else { return }
        group.keys.removeAll { $0.id == id }
        tile?.content = .keys(group)
    }

    private func save() {
        guard let tile, var page = model.workspace.page(pageID), let index = page.tiles.firstIndex(where: { $0.id == tileID }) else { return dismiss() }
        page.tiles[index] = tile
        model.updatePage(page)
        dismiss()
    }

    private func duplicate() {
        guard let tile, var page = model.workspace.page(pageID), let index = page.tiles.firstIndex(where: { $0.id == tileID }) else { return }
        var copy = tile
        copy.id = UUID().uuidString
        if case .keys(var group) = copy.content {
            group.keys = group.keys.map { key in
                var key = key
                key.id = UUID().uuidString
                return key
            }
            copy.content = .keys(group)
        }
        page.tiles.insert(copy, at: index + 1)
        model.updatePage(page)
        dismiss()
    }

    private func remove() {
        guard var page = model.workspace.page(pageID) else { return }
        page.tiles.removeAll { $0.id == tileID }
        model.updatePage(page)
        dismiss()
    }
}

// MARK: - Add tile

struct AddTileSheet: View {
    let pageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Keys") {
                        option(symbol: "square.grid.3x2.fill", title: "Key Panel", detail: "Your own keys") {
                            add(Tile(cols: 6, rows: 4, content: .keys(KeyGroup(title: "Keys", keys: [ButtonDef(label: "New Key", symbol: "square.dashed", action: .none)]))))
                        }
                        option(symbol: "macwindow.on.rectangle", title: "App Keys", detail: "Follows the Mac's front app") {
                            add(Tile(cols: 6, rows: 4, content: .appKeys(limit: 8)))
                        }
                        option(symbol: "sparkles", title: "Scenes", detail: "Start the day, lecture…") {
                            let keys = model.workspace.scenes.map { ButtonDef(label: $0.name, symbol: $0.symbol, color: $0.color, action: .scene($0.id)) }
                            add(Tile(cols: 6, rows: 3, content: .keys(KeyGroup(title: "Scenes", keys: keys, style: .row))))
                        }
                    }
                    ForEach(WidgetKind.Category.allCases, id: \.self) { category in
                        section(category.rawValue) {
                            ForEach(WidgetKind.allCases.filter { $0.category == category }, id: \.self) { kind in
                                option(symbol: kind.symbol, title: kind.title, detail: "\(kind.defaultSize.cols) × \(kind.defaultSize.rows)") {
                                    add(Tile(cols: kind.defaultSize.cols, rows: kind.defaultSize.rows, content: .widget(kind)))
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(CC.bg)
            .navigationTitle("Add Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                content()
            }
        }
    }

    private func option(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CC.accent)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(CC.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(CC.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(CardBackground())
        }
        .buttonStyle(PressStyle())
    }

    private func add(_ tile: Tile) {
        guard var page = model.workspace.page(pageID) else { return }
        page.tiles.append(tile)
        model.updatePage(page)
        Feedback.success()
        dismiss()
    }
}

// MARK: - Key editor

struct KeyEditor: View {
    let pageID: String?
    let tileID: String?
    @State var key: ButtonDef
    var onSave: ((ButtonDef) -> Void)?
    var onDelete: ((String) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pickingSymbol = false
    @State private var testResult: ActionResult?

    init(pageID: String?, tileID: String?, key: ButtonDef, onSave: ((ButtonDef) -> Void)? = nil, onDelete: ((String) -> Void)? = nil) {
        self.pageID = pageID
        self.tileID = tileID
        _key = State(initialValue: key)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            CCForm {
                Section {
                    HStack {
                        Spacer()
                        KeyButton(key: key, pageID: nil, size: CGSize(width: 118, height: 96), editing: true)
                            .allowsHitTesting(false)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Key") {
                    TextField("Label", text: $key.label)
                    Button {
                        pickingSymbol = true
                    } label: {
                        HStack {
                            Text("Symbol").foregroundStyle(CC.text)
                            Spacer()
                            Image(systemName: key.symbol ?? "circle.dashed").foregroundStyle(CC.keyTint(key.color))
                            Text(key.symbol ?? "None").foregroundStyle(CC.text2).font(.caption)
                        }
                    }
                    ColorSwatches(selection: $key.color)
                    TextField("Caption (blank = automatic)", text: Binding(get: { key.caption ?? "" }, set: { key.caption = $0.isEmpty ? nil : $0 }))
                    Picker("Confirmation", selection: $key.confirm) {
                        Text("None").tag(ConfirmMode.none)
                        Text("Dialog").tag(ConfirmMode.dialog)
                        Text("Hold").tag(ConfirmMode.hold)
                    }
                    .pickerStyle(.segmented)
                }
                ActionEditor(action: $key.action)
                Section {
                    Button("Test on Mac", systemImage: "play.fill") {
                        Task { testResult = await model.perform(key.action.promptsForInput ? key.action.fillingInput("test") : key.action) }
                    }
                    if let testResult {
                        Label(testResult.message ?? (testResult.ok ? "Done" : "Failed"), systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testResult.ok ? CC.green : CC.red)
                    }
                    if onDelete != nil || tileID != nil {
                        Button("Delete Key", systemImage: "trash", role: .destructive) { delete() }
                    }
                }
            }
            .navigationTitle(key.label.isEmpty ? "Key" : key.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save() }.bold() }
            }
            .sheet(isPresented: $pickingSymbol) {
                SymbolPicker(selection: Binding(get: { key.symbol }, set: { key.symbol = $0 }))
            }
        }
    }

    private func save() {
        if let onSave {
            onSave(key)
        } else if let pageID, let tileID, var page = model.workspace.page(pageID), let index = page.tiles.firstIndex(where: { $0.id == tileID }), case .keys(var group) = page.tiles[index].content {
            if let keyIndex = group.keys.firstIndex(where: { $0.id == key.id }) {
                group.keys[keyIndex] = key
            } else {
                group.keys.append(key)
            }
            page.tiles[index].content = .keys(group)
            model.updatePage(page)
        }
        dismiss()
    }

    private func delete() {
        if let onDelete {
            onDelete(key.id)
        } else if let pageID, let tileID, var page = model.workspace.page(pageID), let index = page.tiles.firstIndex(where: { $0.id == tileID }), case .keys(var group) = page.tiles[index].content {
            group.keys.removeAll { $0.id == key.id }
            page.tiles[index].content = .keys(group)
            model.updatePage(page)
        }
        dismiss()
    }
}

struct ColorSwatches: View {
    @Binding var selection: KeyColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(KeyColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color == .neutral ? CC.elevated : CC.key(color))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(selection == color ? CC.text : CC.divider, lineWidth: selection == color ? 2.5 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
            }
        }
        .padding(.vertical, 4)
    }
}
