import SwiftUI

struct ChatView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Chat")
                .font(.system(size: 48, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}
