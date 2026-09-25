import Foundation

public struct GridPlacement: Hashable, Sendable {
    public var id: String
    public var col: Int
    public var row: Int
    public var cols: Int
    public var rows: Int

    public init(id: String, col: Int, row: Int, cols: Int, rows: Int) {
        self.id = id
        self.col = col
        self.row = row
        self.cols = cols
        self.rows = rows
    }
}

/// Dense first-fit packing (CSS `grid-auto-flow: row dense`): each tile goes
/// to the top-most, left-most free spot that fits it. Rearranging a page is
/// therefore just reordering its tiles.
public enum GridPacker {
    public static func pack(_ items: [(id: String, cols: Int, rows: Int)], columns: Int) -> [GridPlacement] {
        var occupied: [[Bool]] = []
        var placements: [GridPlacement] = []

        func ensureRows(_ count: Int) {
            while occupied.count < count { occupied.append(Array(repeating: false, count: columns)) }
        }

        func fits(_ row: Int, _ col: Int, _ w: Int, _ h: Int) -> Bool {
            ensureRows(row + h)
            for r in row..<(row + h) {
                for c in col..<(col + w) where occupied[r][c] { return false }
            }
            return true
        }

        for item in items {
            let w = min(max(item.cols, 1), columns)
            let h = max(item.rows, 1)
            var row = 0
            placed: while true {
                for col in 0...(columns - w) where fits(row, col, w, h) {
                    for r in row..<(row + h) {
                        for c in col..<(col + w) { occupied[r][c] = true }
                    }
                    placements.append(GridPlacement(id: item.id, col: col, row: row, cols: w, rows: h))
                    break placed
                }
                row += 1
            }
        }
        return placements
    }

    public static func pack(_ tiles: [Tile], columns: Int = Tile.gridColumns) -> [GridPlacement] {
        pack(tiles.map { (id: $0.id, cols: $0.cols, rows: $0.rows) }, columns: columns)
    }

    /// Rows used by a packing.
    public static func height(of placements: [GridPlacement]) -> Int {
        placements.map { $0.row + $0.rows }.max() ?? 0
    }
}
