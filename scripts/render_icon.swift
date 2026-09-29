import AppKit
import SwiftUI

/// 用 `BarTransIcon` 渲染 macOS 应用图标：1024 画布、824 圆角方块居中（Apple 图标网格），带投影。
@main
struct RenderIcon {
    @MainActor
    static func main() {
        let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        for (name, pixels) in sizes {
            let canvas: CGFloat = 1024
            let view = BarTransIcon(showsContextLines: pixels >= 64)
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
                .frame(width: canvas, height: canvas)
            let renderer = ImageRenderer(content: view)
            renderer.scale = pixels / canvas
            guard let cgImage = renderer.cgImage else { fatalError("render failed: \(name)") }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let data = rep.representation(using: .png, properties: [:])!
            try! data.write(to: outDir.appendingPathComponent("\(name).png"))
        }
    }
}
