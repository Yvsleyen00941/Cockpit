import CCCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders a page: tiles packed into a 12-column grid whose 12 rows exactly
/// fill the screen. Pages taller than 12 rows scroll.
struct PageView: View {
    let page: Page
    var columns = Tile.gridColumns
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let placements = GridPacker.pack(page.tiles, columns: columns)
            let byID = Dictionary(placements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let usedRows = GridPacker.height(of: placements)
            let rows = max(Tile.gridRows, usedRows + (model.editing ? 2 : 0))
            let grid = GridMetrics(size: proxy.size, columns: columns, visibleRows: Tile.gridRows)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    ForEach(page.tiles) { tile in
                        if let placement = byID[tile.id] {
                            TileContainer(tile: tile, page: page, order: placement.row * columns + placement.col)
                                .frame(width: grid.width(placement.cols), height: grid.height(placement.rows))
                                .offset(x: grid.x(placement.col), y: grid.y(placement.row))
                        }
                    }
                    if model.editing {
                        AddTileButton(page: page)
                            .frame(width: grid.width(3), height: grid.height(2))
                            .offset(x: grid.x(0), y: grid.y(usedRows))
                    }
                }
                .frame(width: proxy.size.width, height: grid.contentHeight(rows), alignment: .topLeading)
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: page.tiles)
            }
            .scrollDisabled(rows <= Tile.gridRows)
        }
    }
}

struct GridMetrics {
    let size: CGSize
    let columns: Int
    let visibleRows: Int
    var gap: CGFloat = Metrics.gap

    var columnWidth: CGFloat { (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns) }
    var rowHeight: CGFloat { max(30, (size.height - gap * CGFloat(visibleRows - 1)) / CGFloat(visibleRows)) }

    func width(_ cols: Int) -> CGFloat { CGFloat(cols) * columnWidth + CGFloat(cols - 1) * gap }
    func height(_ rows: Int) -> CGFloat { CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap }
    func x(_ col: Int) -> CGFloat { CGFloat(col) * (columnWidth + gap) }
    func y(_ row: Int) -> CGFloat { CGFloat(row) * (rowHeight + gap) }
    func contentHeight(_ rows: Int) -> CGFloat { height(rows) }
}

// MARK: - Tile container (edit chrome)

struct TileContainer: View {
    let tile: Tile
    let page: Page
    /// Reading order on the grid — tiles rise in one after another.
    var order = 0
    @Environment(AppModel.self) private var model
    @State private var inspecting = false
    @State private var targeted = false
    @State private var shown = false

    var body: some View {
        TileView(tile: tile, pageID: page.id)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .scaleEffect(shown ? 1 : 0.985)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.03 + Double(min(order, 60)) * 0.004)) { shown = true }
            }
            .allowsHitTesting(!model.editing || isKeys)
            .overlay {
                if model.editing {
                    ZStack {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: [7, 6]))
                            .foregroundStyle(targeted ? CC.accent : CC.orange.opacity(0.85))
                        if !isKeys {
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                .fill(Color.black.opacity(0.001))
                                .onTapGesture { inspecting = true }
                        }
                        VStack {
                            HStack {
                                EditCircle(symbol: "minus", color: CC.red) { remove() }
                                Spacer()
                                Menu {
                                    sizeMenu
                                } label: {
                                    EditCircleLabel(symbol: "arrow.up.left.and.arrow.down.right", color: CC.accent)
                                }
                                EditCircle(symbol: "slider.horizontal.3", color: CC.accent) { inspecting = true }
                            }
                            Spacer()
                            HStack {
                                Spacer()
                                Text("\(tile.cols) × \(tile.rows)")
                                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(CC.text)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(GlassShape(shape: Capsule(), shadow: false))
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CC.text)
                                    .frame(width: 32, height: 32)
                                    .background(GlassShape(shape: Circle(), shadow: false))
                            }
                        }
                        .padding(6)
                    }
                    .transition(.opacity)
                }
            }
            .draggable(TileDrag(pageID: page.id, tileID: tile.id)) {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(LinearGradient(colors: [CC.cardTop, CC.card], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(CC.accent.opacity(0.6), lineWidth: 1))
                    .overlay(Text(tileTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(CC.text))
                    .frame(width: 220, height: 120)
            }
            .dropDestination(for: TileDrag.self) { items, _ in
                guard model.editing, let item = items.first, item.pageID == page.id else { return false }
                move(item.tileID, before: tile.id)
                return true
            } isTargeted: { targeted = $0 && model.editing }
            .sheet(isPresented: $inspecting) {
                TileInspector(pageID: page.id, tileID: tile.id)
            }
    }

    private var isKeys: Bool {
        switch tile.content {
        case .keys: true
        default: false
        }
    }

    private var tileTitle: String {
        switch tile.content {
        case .widget(let kind): kind.title
        case .keys(let group): group.title ?? "Keys"
        case .appKeys: "App Keys"
        case .spacer: "Spacer"
        }
    }

    @ViewBuilder private var sizeMenu: some View {
        let presets: [(Int, Int)] = [(3, 3), (4, 3), (4, 4), (4, 5), (4, 6), (5, 5), (6, 3), (6, 4), (6, 5), (6, 6), (7, 5), (8, 4), (8, 5), (8, 6), (12, 1), (12, 2), (12, 3), (12, 4)]
        ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
            Button("\(preset.0) × \(preset.1)") { resize(cols: preset.0, rows: preset.1) }
        }
    }

    private func mutate(_ change: (inout Page) -> Void) {
        guard var current = model.workspace.page(page.id) else { return }
        change(&current)
        model.updatePage(current)
    }

    private func remove() {
        Feedback.tap()
        mutate { $0.tiles.removeAll { $0.id == tile.id } }
    }

    private func resize(cols: Int, rows: Int) {
        mutate { page in
            guard let index = page.tiles.firstIndex(where: { $0.id == tile.id }) else { return }
            page.tiles[index].cols = cols
            page.tiles[index].rows = rows
        }
    }

    private func move(_ id: String, before target: String) {
        guard id != target else { return }
        mutate { page in
            guard let from = page.tiles.firstIndex(where: { $0.id == id }) else { return }
            let moving = page.tiles.remove(at: from)
            let to = page.tiles.firstIndex(where: { $0.id == target }) ?? page.tiles.count
            page.tiles.insert(moving, at: to)
        }
        Feedback.tap()
    }
}

struct TileDrag: Codable, Transferable {
    var pageID: String
    var tileID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct EditCircle: View {
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) { EditCircleLabel(symbol: symbol, color: color) }
            .buttonStyle(PressStyle(scale: 0.9))
    }
}

struct EditCircleLabel: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .glow(color, spread: 8, opacity: 0.45, y: 3)
    }
}

struct AddTileButton: View {
    let page: Page
    @State private var adding = false

    var body: some View {
        Button { adding = true } label: {
            VStack(spacing: 10) {
                IconOrb(symbol: "plus", tint: CC.accent, size: 44)
                Text("Add tile")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(CC.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(CC.accent.opacity(0.7))
                    .background(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(CC.accent.opacity(0.06)))
            )
        }
        .buttonStyle(PressStyle())
        .sheet(isPresented: $adding) { AddTileSheet(pageID: page.id) }
    }
}

// MARK: - Tile dispatch

struct TileView: View {
    let tile: Tile
    let pageID: String

    var body: some View {
        switch tile.content {
        case .widget(let kind):
            WidgetTile(kind: kind, pageID: pageID)
        case .keys(let group):
            KeysTile(group: group, tileID: tile.id, pageID: pageID)
        case .appKeys(let limit):
            AppKeysTile(limit: limit, pageID: pageID)
        case .spacer:
            Color.clear
        }
    }
}

// MARK: - Keys

/// A titled panel of keys. Keys size themselves to fill the panel — never
/// smaller than 72 pt in the default layouts, never taller than wide.
struct KeysTile: View {
    let group: KeyGroup
    let tileID: String
    let pageID: String
    @Environment(AppModel.self) private var model
    @State private var editingKey: ButtonDef?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = group.title {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(CC.text)
                        .lineLimit(1)
                    Spacer()
                    if model.editing {
                        Button {
                            addKey()
                        } label: {
                            Label("Key", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CC.accent)
                        }
                    }
                }
            }
            GeometryReader { proxy in
                switch group.style {
                case .standard:
                    StandardKeyGrid(keys: group.keys, size: proxy.size, pageID: pageID, editing: model.editing) { editingKey = $0 }
                case .large:
                    LargeKeyStack(keys: group.keys, size: proxy.size, pageID: pageID, editing: model.editing) { editingKey = $0 }
                case .row:
                    RowKeyGrid(keys: group.keys, size: proxy.size, pageID: pageID, editing: model.editing) { editingKey = $0 }
                }
            }
        }
        .card(padding: 16)
        .sheet(item: $editingKey) { key in
            KeyEditor(pageID: pageID, tileID: tileID, key: key)
        }
    }

    private func addKey() {
        guard var page = model.workspace.page(pageID), let index = page.tiles.firstIndex(where: { $0.id == tileID }), case .keys(var group) = page.tiles[index].content else { return }
        let key = ButtonDef(label: "New Key", symbol: "square.dashed", action: .none)
        group.keys.append(key)
        page.tiles[index].content = .keys(group)
        model.updatePage(page)
        editingKey = key
    }
}

enum KeyLayout {
    /// Picks the column count that gives the largest keys, with keys never
    /// taller than wide and at most 1.7 : 1.
    static func standard(count: Int, in size: CGSize, gap: CGFloat = 10) -> (columns: Int, key: CGSize) {
        guard count > 0, size.width > 0, size.height > 0 else { return (1, .zero) }
        var best = (columns: count, key: CGSize(width: 60, height: 60), score: -1.0)
        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let w = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let h = (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            guard w >= 54, h >= 48 else { continue }
            let keyH = min(h, w, 118)
            let keyW = min(w, keyH * 1.7, 230)
            let score = Double(keyW * keyH)
            if score > best.score { best = (columns, CGSize(width: keyW, height: keyH), score) }
        }
        return (best.columns, best.key)
    }
}

struct StandardKeyGrid: View {
    let keys: [ButtonDef]
    let size: CGSize
    let pageID: String
    let editing: Bool
    let onEdit: (ButtonDef) -> Void

    var body: some View {
        let layout = KeyLayout.standard(count: keys.count, in: size)
        let rows = stride(from: 0, to: keys.count, by: layout.columns).map { Array(keys[$0..<min($0 + layout.columns, keys.count)]) }
        let gridWidth = CGFloat(layout.columns) * layout.key.width + CGFloat(layout.columns - 1) * 10
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { key in
                        KeyButton(key: key, pageID: pageID, size: layout.key, editing: editing) { onEdit(key) }
                    }
                }
            }
        }
        .frame(width: gridWidth, alignment: .leading)
        .frame(width: size.width, height: size.height, alignment: size.width - gridWidth > 40 ? .center : .topLeading)
    }
}

struct LargeKeyStack: View {
    let keys: [ButtonDef]
    let size: CGSize
    let pageID: String
    let editing: Bool
    let onEdit: (ButtonDef) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let height = min(Metrics.largeButton, (size.height - CGFloat(max(0, keys.count - 1)) * 10) / CGFloat(max(1, keys.count)))
        VStack(spacing: 10) {
            ForEach(keys) { key in
                LargeActionButton(title: key.label, symbol: key.symbol ?? "circle", color: key.color == .neutral ? CC.accent : CC.key(key.color), style: key.color == .red ? .tinted : .filled, height: height, hold: key.confirm == .hold && !editing) {
                    if editing { onEdit(key) } else { model.tap(key, pageID: pageID, confirmed: key.confirm == .hold) }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

struct RowKeyGrid: View {
    let keys: [ButtonDef]
    let size: CGSize
    let pageID: String
    let editing: Bool
    let onEdit: (ButtonDef) -> Void

    var body: some View {
        let columns = max(1, min(keys.count, Int((size.width + 10) / (230 + 10))))
        let rows = Int(ceil(Double(keys.count) / Double(columns)))
        let height = max(40, min(64, (size.height - CGFloat(max(0, rows - 1)) * 10) / CGFloat(max(1, rows))))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(keys) { key in
                RowKey(key: key, pageID: pageID, height: height, editing: editing) { onEdit(key) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// The frontmost Mac app's own keys — used on the Study page, so Safari,
/// Preview or Notion keys show up next to the Pomodoro.
struct AppKeysTile: View {
    let limit: Int
    let pageID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let context = model.store.context
        let mapped = context.flatMap { model.workspace.mappedPage(for: $0.bundleID) }
        let keys = mapped == pageID ? [] : Array((context.map { model.workspace.keys(forApp: $0.bundleID) } ?? []).prefix(limit))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIconView(bundleID: context?.bundleID, size: 26)
                Text("\(context?.appName ?? "App") keys")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
            }
            if keys.isEmpty {
                Text("No keys mapped for \(context?.appName ?? "this app"). Add a page for it in Settings → App Mappings.")
                    .font(.system(size: 13))
                    .foregroundStyle(CC.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                GeometryReader { proxy in
                    StandardKeyGrid(keys: keys, size: proxy.size, pageID: pageID, editing: false) { _ in }
                }
            }
        }
        .card(padding: 16)
        .animation(.easeOut(duration: 0.2), value: context?.bundleID)
    }
}
