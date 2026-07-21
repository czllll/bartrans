import SwiftUI

/// bartrans 的品牌图形：一个圆角"窗口"外框，顶部一条实心的
/// "菜单栏"色块与外框顶边贴合，中间是双向箭头——三者连成一个
/// 整体，而不是几个漂浮的独立小图形。全部用 SwiftUI 矢量图形
/// 绘制，不需要任何外部美术资源，缩放到任意尺寸都清晰。
struct BarTransMark: View {
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let corner = size * 0.26
            let lineWidth = max(size * 0.07, 1.2)
            let barHeight = size * 0.2

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(color, lineWidth: lineWidth)

                VStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: corner - lineWidth * 0.4,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: corner - lineWidth * 0.4,
                        style: .continuous
                    )
                    .fill(color)
                    .frame(height: barHeight)
                    Spacer(minLength: 0)
                }
                .padding(lineWidth * 0.5)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.3, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.top, barHeight * 0.55)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 彩色版本：用于面板 / 设置窗口的品牌标识，纯色背景（不用渐变）。
struct BarTransLogo: View {
    var size: CGFloat = 24
    static let brandColor = Color(red: 0.29, green: 0.51, blue: 0.98)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Self.brandColor)
            BarTransMark(color: .white)
                .padding(size * 0.16)
        }
        .frame(width: size, height: size)
    }
}
