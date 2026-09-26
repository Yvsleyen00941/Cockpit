import SwiftUI

/// Settings and the editors live in the same scene as the surface: the
/// backdrop behind a grouped list whose rows are glass.
struct CCForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(GlassRow())
        }
        .scrollContentBackground(.hidden)
        .background(SceneBackdrop(mood: .cobalt, dim: 0.22))
    }
}

/// A grouped-list row made of glass.
struct GlassRow: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(scheme == .light ? Color.white.opacity(0.72) : Color.white.opacity(0.07))
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(scheme == .light ? 0.9 : 0.06)).frame(height: 0.5)
            }
    }
}
