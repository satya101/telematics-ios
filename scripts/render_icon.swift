// Renders the AppIcon from AssetIQLogo. Run from the repo root:
//   swiftc -parse-as-library scripts/render_icon.swift TelematicsApp/Views/AssetIQLogo.swift -o /tmp/render_icon && /tmp/render_icon
import SwiftUI
import AppKit

@main
struct RenderIcon {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: AssetIQLogo(cornerRadius: 0).frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            fatalError("render failed")
        }
        let out = URL(fileURLWithPath: "TelematicsApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
        try! png.write(to: out)
        print("wrote \(out.path) \(cg.width)x\(cg.height)")
    }
}
