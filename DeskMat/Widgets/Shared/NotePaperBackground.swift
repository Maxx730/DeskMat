import SwiftUI

struct NotePaperBackground: View {
    var lineSpacing: CGFloat = 11
    var lineColor: Color = .black.opacity(0.1)
    var marginColor: Color = Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.45)
    var marginX: CGFloat = 16
    var cornerRadius: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            // Horizontal ruled lines
            var y = lineSpacing
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                y += lineSpacing
            }

            // Vertical margin line
            var margin = Path()
            margin.move(to: CGPoint(x: marginX, y: 0))
            margin.addLine(to: CGPoint(x: marginX, y: size.height))
            context.stroke(margin, with: .color(marginColor), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
