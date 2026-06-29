import SwiftUI
import AppKit

struct IconPickerButton: View {
    let image: NSImage?
    let placeholderSystemImage: String
    let hasCustomIcon: Bool
    let onPick: () -> Void
    let onReset: () -> Void
    var backgroundPreviewColor: Color? = nil
    var size: CGFloat = 64

    private var cornerRadius: CGFloat { size * 0.219 }
    private var innerSize: CGFloat    { size * 0.75 }
    private var scale: CGFloat        { size / 64 }

    var body: some View {
        Button(action: onPick) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        if let bg = backgroundPreviewColor {
                            ZStack {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(bg)
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: innerSize, height: innerSize)
                            }
                            .frame(width: size, height: size)
                        } else {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.quaternary)
                            .frame(width: size, height: size)
                            .overlay {
                                Image(systemName: placeholderSystemImage)
                                    .font(.system(size: 24 * scale))
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .blue)
                    .offset(x: 10 * scale, y: 5 * scale)
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
                .offset(x: -10 * scale, y: -6 * scale)
            }
        }
    }
}
