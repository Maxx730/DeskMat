import SwiftUI
import Foundation

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String = "Default Section", @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(EdgeInsets(top: 16, leading: 6, bottom: 4, trailing: 0))
            VStack {
                content
            }
            .padding(16)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
