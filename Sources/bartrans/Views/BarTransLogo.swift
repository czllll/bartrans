import AppKit
import SwiftUI

/// 品牌色与共用的视觉常量。
///
/// 视觉语言来自"划词"这个动作本身：深靛蓝的墨水底色，
/// 加上一道荧光笔式的琥珀色高亮——选中的那个词。
enum Theme {
    /// 墨水靛蓝：品牌主色、按钮、强调
    static let ink = Color(red: 0.20, green: 0.25, blue: 0.62)
    static let inkDeep = Color(red: 0.11, green: 0.13, blue: 0.36)
    static let inkBright = Color(red: 0.29, green: 0.36, blue: 0.84)
    /// 用在文字 / 图标上的靛蓝：深色模式下提亮，保证对比度
    static let inkText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.62, green: 0.68, blue: 1.0, alpha: 1)
            : NSColor(red: 0.20, green: 0.25, blue: 0.62, alpha: 1)
    })
    /// 荧光笔琥珀：选区高亮、主操作
    static let highlighter = Color(red: 1.0, green: 0.80, blue: 0.25)
    static let highlighterSoft = Color(red: 1.0, green: 0.80, blue: 0.25).opacity(0.38)

    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 10
}

/// App 图标 / 面板 Logo：一段文字里被荧光笔选中的 "A文"，两端是文本选择手柄。
/// 全部用矢量图形绘制，`scripts/make_icon.sh` 也用这个视图渲染 AppIcon.icns。
struct BarTransIcon: View {
    /// 小尺寸下省略装饰性的"上下文文字行"，保证可辨认
    var showsContextLines: Bool = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.inkBright, Theme.inkDeep], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center))

                if showsContextLines {
                    contextLine(width: 0.50, at: 0.255, s: s, offsetX: -0.05)
                    contextLine(width: 0.40, at: 0.745, s: s, offsetX: -0.10)
                }

                selection(s: s)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func contextLine(width: CGFloat, at y: CGFloat, s: CGFloat, offsetX: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: s * width, height: s * 0.055)
            .position(x: s * (0.5 + offsetX), y: s * y)
    }

    private func selection(s: CGFloat) -> some View {
        // 小尺寸下没有上下文文字行，把选区放大，保证 "A文" 仍然可辨认
        let k: CGFloat = showsContextLines ? 1 : 1.22
        let width = s * 0.60 * k
        let height = s * 0.30 * k
        let handleLine = max(s * 0.022, 1)
        let knob = s * 0.075 * k

        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.022, style: .continuous)
                .fill(Theme.highlighter)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.01)

            HStack(spacing: s * 0.015) {
                Text("A")
                    .font(.system(size: s * 0.22 * k, weight: .heavy, design: .rounded))
                Text("文")
                    .font(.system(size: s * 0.20 * k, weight: .heavy))
            }
            .foregroundStyle(Theme.inkDeep)

            // 左手柄：竖线 + 顶部圆点
            handle(line: handleLine, knob: knob, height: height, knobOnTop: true)
                .offset(x: -width / 2)
            // 右手柄：竖线 + 底部圆点
            handle(line: handleLine, knob: knob, height: height, knobOnTop: false)
                .offset(x: width / 2)
        }
        .position(x: s / 2, y: s / 2)
    }

    private func handle(line: CGFloat, knob: CGFloat, height: CGFloat, knobOnTop: Bool) -> some View {
        VStack(spacing: 0) {
            if knobOnTop { Circle().fill(.white).frame(width: knob, height: knob) }
            Rectangle().fill(.white).frame(width: line, height: height + knob * 0.4)
            if !knobOnTop { Circle().fill(.white).frame(width: knob, height: knob) }
        }
        .offset(y: knobOnTop ? -knob * 0.5 : knob * 0.5)
    }
}

/// 面板 / 设置窗口里用的小尺寸品牌标识。
struct BarTransLogo: View {
    var size: CGFloat = 24

    var body: some View {
        BarTransIcon(showsContextLines: size >= 40)
            .frame(width: size, height: size)
    }
}

/// 菜单栏图标（template image，单色）：一块圆角"选区"，镂空出"文"字，
/// 两端带选择手柄。随浅色 / 深色菜单栏自动反色。
struct BarTransMark: View {
    var color: Color = .black

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let width = s * 0.78
            let height = s * 0.56
            let knob = s * 0.2

            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                        .fill(color)
                        .frame(width: width, height: height)
                    Text("文")
                        .font(.system(size: s * 0.44, weight: .bold))
                        .foregroundStyle(.black)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                Circle().fill(color)
                    .frame(width: knob, height: knob)
                    .position(x: s / 2 - width / 2, y: s / 2 - height / 2 - knob * 0.15)
                Circle().fill(color)
                    .frame(width: knob, height: knob)
                    .position(x: s / 2 + width / 2, y: s / 2 + height / 2 + knob * 0.15)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
