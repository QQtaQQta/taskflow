import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 24)
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .background(.red, in: Capsule())
            .padding()
    }
}
