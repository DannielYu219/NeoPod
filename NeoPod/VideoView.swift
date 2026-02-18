import SwiftUI

struct VideoView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Video")
                .font(.system(size: 48, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        VideoView()
    }
}
