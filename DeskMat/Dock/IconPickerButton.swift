import SwiftUI
import AppKit

struct IconPickerButton: View {
    let image: NSImage?
    let placeholderSystemImage: String
    let hasCustomIcon: Bool
    let onPick: () -> Void
    let onReset: () -> Void

    var body: some View {
        Button(action: onPick) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.quaternary)
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: placeholderSystemImage)
                                    .font(.system(size: 24))
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .blue)
                    .offset(x: 10, y: 5)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if hasCustomIcon {
                Button(action: onReset) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(1.0))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .offset(x: -10, y: -6)
            }
        }
    }
}
