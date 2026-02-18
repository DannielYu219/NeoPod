import SwiftUI

struct ZuneTopBar: View {
    let title: String
    let accent: Color
    let showsBack: Bool
    let onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if showsBack {
                    Button(action: { onBack?() }) {
                        Image(systemName: "arrow.backward.circle")
                            .font(.system(size: 48, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundColor(accent)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "arrow.backward.circle")
                        .font(.system(size: 48, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(accent.opacity(0.4))
                        .padding(.vertical, 6)
                }
                Spacer()
            }

            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(.system(size: 64, weight: .regular, design: .rounded))
                    .tracking(1.5)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ZUNE HD")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                    Text("library")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
}

struct ZuneBackground: View {
    var body: some View {
        Color.black
        .ignoresSafeArea()
    }
}
