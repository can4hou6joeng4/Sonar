import CoreGraphics

/// Geometry is independent of AppKit so display arrangements can be verified locally.
struct NotchGeometry {
    let screen: CGRect
    let safeTop: CGFloat
    let hardwareWidth: CGFloat

    var hasNotch: Bool { safeTop > 0 && hardwareWidth > 0 }
    var topHeight: CGFloat { hasNotch ? max(32, safeTop) : 36 }
    var centerGap: CGFloat { hasNotch ? hardwareWidth : 142 }

    func frame(expanded: Bool) -> CGRect {
        let width = max(0, min(screen.width - 24, expanded ? max(420, centerGap + 100) : centerGap + 88))
        let height = max(0, min(screen.height - 12, topHeight + (expanded ? 226 : 0)))
        let top = screen.maxY - (hasNotch ? 0 : 6)
        return CGRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
    }
}
