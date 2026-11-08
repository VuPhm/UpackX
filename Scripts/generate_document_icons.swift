#!/usr/bin/env swift

import AppKit
import Foundation

struct FormatSpec {
    let id: String
    let fileName: String
    let extensionLabel: String
    let subLabel: String
    let topColor: NSColor
    let bottomColor: NSColor
    let isDiskImage: Bool
}

let formats: [FormatSpec] = [
    FormatSpec(
        id: "zip",
        fileName: "Document-ZIP",
        extensionLabel: "ZIP",
        subLabel: "ARCHIVE",
        topColor: NSColor(srgbRed: 1.0, green: 0.58, blue: 0.05, alpha: 1.0),     // Amber Orange #FF940D
        bottomColor: NSColor(srgbRed: 0.92, green: 0.28, blue: 0.05, alpha: 1.0),  // Deep Orange #EB470D
        isDiskImage: false
    ),
    FormatSpec(
        id: "7z",
        fileName: "Document-7Z",
        extensionLabel: "7Z",
        subLabel: "7-ZIP ARCHIVE",
        topColor: NSColor(srgbRed: 0.08, green: 0.65, blue: 0.98, alpha: 1.0),     // Cyan Sky #14A6FA
        bottomColor: NSColor(srgbRed: 0.02, green: 0.38, blue: 0.88, alpha: 1.0),  // Royal Blue #0561E0
        isDiskImage: false
    ),
    FormatSpec(
        id: "rar",
        fileName: "Document-RAR",
        extensionLabel: "RAR",
        subLabel: "RAR ARCHIVE",
        topColor: NSColor(srgbRed: 0.72, green: 0.38, blue: 0.96, alpha: 1.0),     // Orchid Violet #B861F5
        bottomColor: NSColor(srgbRed: 0.46, green: 0.15, blue: 0.75, alpha: 1.0),  // Royal Purple #7526BF
        isDiskImage: false
    ),
    FormatSpec(
        id: "tar",
        fileName: "Document-TAR",
        extensionLabel: "TAR",
        subLabel: "TARBALL",
        topColor: NSColor(srgbRed: 0.18, green: 0.80, blue: 0.44, alpha: 1.0),     // Emerald #2ECC70
        bottomColor: NSColor(srgbRed: 0.05, green: 0.52, blue: 0.28, alpha: 1.0),  // Forest Green #0D8547
        isDiskImage: false
    ),
    FormatSpec(
        id: "gz",
        fileName: "Document-GZ",
        extensionLabel: "GZ",
        subLabel: "GZIP ARCHIVE",
        topColor: NSColor(srgbRed: 0.10, green: 0.75, blue: 0.70, alpha: 1.0),     // Mint Teal #1AC0B2
        bottomColor: NSColor(srgbRed: 0.04, green: 0.48, blue: 0.46, alpha: 1.0),  // Deep Teal #0B7A75
        isDiskImage: false
    ),
    FormatSpec(
        id: "bz2",
        fileName: "Document-BZ2",
        extensionLabel: "BZ2",
        subLabel: "BZIP2 ARCHIVE",
        topColor: NSColor(srgbRed: 0.15, green: 0.55, blue: 0.85, alpha: 1.0),     // Steel Azure #268CD9
        bottomColor: NSColor(srgbRed: 0.08, green: 0.28, blue: 0.58, alpha: 1.0),  // Deep Navy #144794
        isDiskImage: false
    ),
    FormatSpec(
        id: "xz",
        fileName: "Document-XZ",
        extensionLabel: "XZ",
        subLabel: "XZ ARCHIVE",
        topColor: NSColor(srgbRed: 0.45, green: 0.48, blue: 0.95, alpha: 1.0),     // Indigo #737AF2
        bottomColor: NSColor(srgbRed: 0.22, green: 0.20, blue: 0.65, alpha: 1.0),  // Deep Indigo #3833A6
        isDiskImage: false
    ),
    FormatSpec(
        id: "iso",
        fileName: "Document-ISO",
        extensionLabel: "ISO",
        subLabel: "DISK IMAGE",
        topColor: NSColor(srgbRed: 0.52, green: 0.58, blue: 0.65, alpha: 1.0),     // Silver Slate #8594A6
        bottomColor: NSColor(srgbRed: 0.22, green: 0.27, blue: 0.33, alpha: 1.0),  // Dark Graphite #384554
        isDiskImage: true
    ),
    FormatSpec(
        id: "archive",
        fileName: "Document-Archive",
        extensionLabel: "ARC",
        subLabel: "UPACKX ARCHIVE",
        topColor: NSColor(srgbRed: 0.15, green: 0.45, blue: 0.85, alpha: 1.0),     // UpackX Blue #2673D9
        bottomColor: NSColor(srgbRed: 0.08, green: 0.14, blue: 0.24, alpha: 1.0),  // Charcoal #14243D
        isDiskImage: false
    )
]

func renderIconBitmap(spec: FormatSpec, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = nsContext
    nsContext.imageInterpolation = .high
    
    let ctx = nsContext.cgContext
    
    let scale = CGFloat(pixelSize) / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    
    // Geometry constants in 1024x1024 space
    let pageLeft: CGFloat = 184
    let pageRight: CGFloat = 840
    let pageBottom: CGFloat = 80
    let pageTop: CGFloat = 924
    let cornerRadius: CGFloat = 50
    let foldSize: CGFloat = 180
    
    let foldStartX = pageRight - foldSize
    let foldStartY = pageTop - foldSize
    
    // 1. Draw Document Drop Shadow
    ctx.saveGState()
    let paperPath = CGMutablePath()
    paperPath.move(to: CGPoint(x: pageLeft, y: pageBottom + cornerRadius))
    paperPath.addArc(tangent1End: CGPoint(x: pageLeft, y: pageBottom),
                     tangent2End: CGPoint(x: pageLeft + cornerRadius, y: pageBottom),
                     radius: cornerRadius)
    paperPath.addLine(to: CGPoint(x: pageRight - cornerRadius, y: pageBottom))
    paperPath.addArc(tangent1End: CGPoint(x: pageRight, y: pageBottom),
                     tangent2End: CGPoint(x: pageRight, y: pageBottom + cornerRadius),
                     radius: cornerRadius)
    paperPath.addLine(to: CGPoint(x: pageRight, y: foldStartY))
    paperPath.addLine(to: CGPoint(x: foldStartX, y: pageTop))
    paperPath.addLine(to: CGPoint(x: pageLeft + cornerRadius, y: pageTop))
    paperPath.addArc(tangent1End: CGPoint(x: pageLeft, y: pageTop),
                     tangent2End: CGPoint(x: pageLeft, y: pageTop - cornerRadius),
                     radius: cornerRadius)
    paperPath.closeSubpath()
    
    // Ambient soft shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 32, color: NSColor(white: 0.0, alpha: 0.22).cgColor)
    ctx.addPath(paperPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    
    // Direct key shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -28), blur: 20, color: NSColor(white: 0.0, alpha: 0.18).cgColor)
    ctx.addPath(paperPath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2. Fill Paper Base with Subtle macOS Gradient
    ctx.saveGState()
    ctx.addPath(paperPath)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let paperGradientColors = [
        NSColor(white: 0.99, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1.0).cgColor
    ] as CFArray
    if let paperGrad = CGGradient(colorsSpace: colorSpace, colors: paperGradientColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(paperGrad,
                               start: CGPoint(x: 512, y: pageTop),
                               end: CGPoint(x: 512, y: pageBottom),
                               options: [])
    }
    
    // Subtle top inner glow
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.7).cgColor)
    ctx.setLineWidth(3.0)
    ctx.strokeLineSegments(between: [
        CGPoint(x: pageLeft + cornerRadius, y: pageTop - 2),
        CGPoint(x: foldStartX, y: pageTop - 2)
    ])
    ctx.restoreGState()
    
    // Paper Outer Border Stroke
    ctx.saveGState()
    ctx.addPath(paperPath)
    ctx.setStrokeColor(NSColor(white: 0.0, alpha: 0.12).cgColor)
    ctx.setLineWidth(2.0)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 3. Draw Zipper (Central motif for archives)
    let centerX: CGFloat = 512
    let zipperTop: CGFloat = 860
    let zipperBottom: CGFloat = 480
    
    ctx.saveGState()
    // Zipper groove track
    let trackRect = CGRect(x: centerX - 8, y: zipperBottom, width: 16, height: zipperTop - zipperBottom)
    let trackPath = CGPath(roundedRect: trackRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
    ctx.addPath(trackPath)
    ctx.setFillColor(NSColor(srgbRed: 0.82, green: 0.85, blue: 0.88, alpha: 1.0).cgColor)
    ctx.fillPath()
    
    // Zipper seam line
    ctx.setStrokeColor(NSColor(srgbRed: 0.65, green: 0.70, blue: 0.75, alpha: 0.8).cgColor)
    ctx.setLineWidth(1.5)
    ctx.strokeLineSegments(between: [
        CGPoint(x: centerX, y: zipperBottom + 4),
        CGPoint(x: centerX, y: zipperTop - 4)
    ])
    
    // Zipper teeth (metallic polished studs)
    var yPos = zipperBottom + 12
    var side = true
    while yPos < zipperTop - 16 {
        let toothWidth: CGFloat = 16
        let toothHeight: CGFloat = 8
        let toothX = side ? (centerX - 18) : (centerX + 2)
        let toothRect = CGRect(x: toothX, y: yPos, width: toothWidth, height: toothHeight)
        let toothPath = CGPath(roundedRect: toothRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor(white: 0, alpha: 0.2).cgColor)
        ctx.addPath(toothPath)
        
        let toothGradColors = [
            NSColor(white: 0.98, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1.0).cgColor
        ] as CFArray
        if let toothGrad = CGGradient(colorsSpace: colorSpace, colors: toothGradColors, locations: [0.0, 1.0]) {
            ctx.clip()
            ctx.drawLinearGradient(toothGrad,
                                   start: CGPoint(x: toothX, y: yPos + toothHeight),
                                   end: CGPoint(x: toothX, y: yPos),
                                   options: [])
        }
        ctx.restoreGState()
        
        // Tooth subtle highlight
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.6).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokeLineSegments(between: [
            CGPoint(x: toothX + 2, y: yPos + toothHeight - 1),
            CGPoint(x: toothX + toothWidth - 2, y: yPos + toothHeight - 1)
        ])
        
        yPos += 16
        side.toggle()
    }
    
    // Zipper Slider (Con trượt khóa kéo kim loại)
    let sliderY: CGFloat = 680
    let sliderWidth: CGFloat = 48
    let sliderHeight: CGFloat = 40
    let sliderRect = CGRect(x: centerX - sliderWidth / 2, y: sliderY, width: sliderWidth, height: sliderHeight)
    let sliderPath = CGPath(roundedRect: sliderRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(sliderPath)
    
    let sliderGradColors = [
        NSColor(white: 0.98, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.70, green: 0.74, blue: 0.78, alpha: 1.0).cgColor
    ] as CFArray
    if let sliderGrad = CGGradient(colorsSpace: colorSpace, colors: sliderGradColors, locations: [0.0, 1.0]) {
        ctx.clip()
        ctx.drawLinearGradient(sliderGrad,
                               start: CGPoint(x: centerX, y: sliderY + sliderHeight),
                               end: CGPoint(x: centerX, y: sliderY),
                               options: [])
    }
    ctx.restoreGState()
    
    // Slider chrome highlight rim
    ctx.saveGState()
    ctx.addPath(sliderPath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.8).cgColor)
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Zipper Pull Tab (Thẻ kéo)
    let pullWidth: CGFloat = 28
    let pullHeight: CGFloat = 58
    let pullY = sliderY - 44
    let pullRect = CGRect(x: centerX - pullWidth / 2, y: pullY, width: pullWidth, height: pullHeight)
    let pullPath = CGPath(roundedRect: pullRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: NSColor(white: 0, alpha: 0.3).cgColor)
    ctx.addPath(pullPath)
    
    let pullGradColors = [
        NSColor(white: 0.95, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.65, green: 0.70, blue: 0.75, alpha: 1.0).cgColor
    ] as CFArray
    if let pullGrad = CGGradient(colorsSpace: colorSpace, colors: pullGradColors, locations: [0.0, 1.0]) {
        ctx.clip()
        ctx.drawLinearGradient(pullGrad,
                               start: CGPoint(x: centerX, y: pullY + pullHeight),
                               end: CGPoint(x: centerX, y: pullY),
                               options: [])
    }
    ctx.restoreGState()
    
    // Pull tab inner hole
    let holeRect = CGRect(x: centerX - 6, y: pullY + 12, width: 12, height: 22)
    let holePath = CGPath(roundedRect: holeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
    ctx.saveGState()
    ctx.addPath(holePath)
    ctx.setFillColor(NSColor(srgbRed: 0.50, green: 0.55, blue: 0.60, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    ctx.restoreGState()
    
    // 4. Hero Color-Coded Format Badge (Thẻ định dạng có màu rực rỡ)
    let badgeLeft: CGFloat = 224
    let badgeBottom: CGFloat = 140
    let badgeWidth: CGFloat = 576
    let badgeHeight: CGFloat = 310
    let badgeRadius: CGFloat = 44
    let badgeRect = CGRect(x: badgeLeft, y: badgeBottom, width: badgeWidth, height: badgeHeight)
    let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: badgeRadius, cornerHeight: badgeRadius, transform: nil)
    
    ctx.saveGState()
    // Vibrant Colored Glow Shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -14),
                  blur: 26,
                  color: spec.bottomColor.withAlphaComponent(0.45).cgColor)
    ctx.addPath(badgePath)
    ctx.setFillColor(spec.bottomColor.cgColor)
    ctx.fillPath()
    
    // Badge Main Gradient
    ctx.addPath(badgePath)
    ctx.clip()
    let badgeGradColors = [
        spec.topColor.cgColor,
        spec.bottomColor.cgColor
    ] as CFArray
    if let badgeGrad = CGGradient(colorsSpace: colorSpace, colors: badgeGradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(badgeGrad,
                               start: CGPoint(x: centerX, y: badgeBottom + badgeHeight),
                               end: CGPoint(x: centerX, y: badgeBottom),
                               options: [])
    }
    
    // Glossy Top Specular Arc (Hiệu ứng mặt gương Apple)
    let glossPath = CGMutablePath()
    glossPath.move(to: CGPoint(x: badgeLeft, y: badgeBottom + badgeHeight))
    glossPath.addLine(to: CGPoint(x: badgeLeft + badgeWidth, y: badgeBottom + badgeHeight))
    glossPath.addLine(to: CGPoint(x: badgeLeft + badgeWidth, y: badgeBottom + badgeHeight * 0.45))
    glossPath.addCurve(to: CGPoint(x: badgeLeft, y: badgeBottom + badgeHeight * 0.65),
                       control1: CGPoint(x: badgeLeft + badgeWidth * 0.6, y: badgeBottom + badgeHeight * 0.45),
                       control2: CGPoint(x: badgeLeft + badgeWidth * 0.3, y: badgeBottom + badgeHeight * 0.60))
    glossPath.closeSubpath()
    
    ctx.saveGState()
    ctx.addPath(glossPath)
    ctx.clip()
    let glossColors = [
        NSColor(white: 1.0, alpha: 0.32).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let glossGrad = CGGradient(colorsSpace: colorSpace, colors: glossColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(glossGrad,
                               start: CGPoint(x: centerX, y: badgeBottom + badgeHeight),
                               end: CGPoint(x: centerX, y: badgeBottom + badgeHeight * 0.4),
                               options: [])
    }
    ctx.restoreGState()
    
    // Badge Inner Highlight Stroke
    ctx.addPath(badgePath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.45).cgColor)
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    
    ctx.restoreGState()
    
    // 5. Badge Content: Icon Glyph, Extension Text, Sub-Label
    ctx.saveGState()
    
    if spec.isDiskImage {
        // Draw Optical Disc Glyph for ISO
        let discCenter = CGPoint(x: centerX, y: badgeBottom + badgeHeight - 65)
        let outerDiscRadius: CGFloat = 34
        let innerDiscRadius: CGFloat = 11
        
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.85).cgColor)
        ctx.setLineWidth(4.0)
        ctx.strokeEllipse(in: CGRect(x: discCenter.x - outerDiscRadius, y: discCenter.y - outerDiscRadius,
                                     width: outerDiscRadius * 2, height: outerDiscRadius * 2))
        
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.95).cgColor)
        ctx.setLineWidth(3.0)
        ctx.strokeEllipse(in: CGRect(x: discCenter.x - innerDiscRadius, y: discCenter.y - innerDiscRadius,
                                     width: innerDiscRadius * 2, height: innerDiscRadius * 2))
    } else {
        // Draw Symmetric Inward Compression Arrows (Biểu tượng nén dữ liệu thanh lịch)
        let glyphY = badgeBottom + badgeHeight - 60
        let arrowOffset: CGFloat = 38
        
        // Left arrow pointing right ->
        let leftArrow = CGMutablePath()
        leftArrow.move(to: CGPoint(x: centerX - arrowOffset - 24, y: glyphY + 12))
        leftArrow.addLine(to: CGPoint(x: centerX - arrowOffset, y: glyphY))
        leftArrow.addLine(to: CGPoint(x: centerX - arrowOffset - 24, y: glyphY - 12))
        
        // Right arrow pointing left <-
        let rightArrow = CGMutablePath()
        rightArrow.move(to: CGPoint(x: centerX + arrowOffset + 24, y: glyphY + 12))
        rightArrow.addLine(to: CGPoint(x: centerX + arrowOffset, y: glyphY))
        rightArrow.addLine(to: CGPoint(x: centerX + arrowOffset + 24, y: glyphY - 12))
        
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.88).cgColor)
        ctx.setLineWidth(4.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(leftArrow)
        ctx.addPath(rightArrow)
        ctx.strokePath()
        
        // Center compression block
        let blockRect = CGRect(x: centerX - 10, y: glyphY - 14, width: 20, height: 28)
        let blockPath = CGPath(roundedRect: blockRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(blockPath)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.90).cgColor)
        ctx.fillPath()
    }
    
    // Main Extension Text
    let len = spec.extensionLabel.count
    let mainFontSize: CGFloat
    if len <= 2 {
        mainFontSize = 112
    } else if len == 3 {
        mainFontSize = 98
    } else {
        mainFontSize = 80
    }
    
    let mainFont = NSFont.systemFont(ofSize: mainFontSize, weight: .heavy)
    let textShadow = NSShadow()
    textShadow.shadowOffset = NSSize(width: 0, height: -3)
    textShadow.shadowBlurRadius = 6
    textShadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    
    let mainAttrs: [NSAttributedString.Key: Any] = [
        .font: mainFont,
        .foregroundColor: NSColor.white,
        .shadow: textShadow
    ]
    
    let mainText = NSAttributedString(string: spec.extensionLabel, attributes: mainAttrs)
    let textSize = mainText.size()
    let textX = centerX - textSize.width / 2
    let textY = badgeBottom + 82
    mainText.draw(at: NSPoint(x: textX, y: textY))
    
    // Sub Label Text ("ARCHIVE", "TARBALL", etc.)
    let subFont = NSFont.systemFont(ofSize: 22, weight: .bold)
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.82),
        .kern: 3.5
    ]
    let subText = NSAttributedString(string: spec.subLabel, attributes: subAttrs)
    let subSize = subText.size()
    let subX = centerX - subSize.width / 2
    let subY = badgeBottom + 36
    subText.draw(at: NSPoint(x: subX, y: subY))
    
    ctx.restoreGState()
    
    // 6. Draw Top-Right Dog-Ear Fold Flap
    ctx.saveGState()
    
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: foldStartX, y: pageTop))
    foldPath.addLine(to: CGPoint(x: foldStartX, y: foldStartY + 16))
    foldPath.addArc(tangent1End: CGPoint(x: foldStartX, y: foldStartY),
                    tangent2End: CGPoint(x: foldStartX + 16, y: foldStartY),
                    radius: 14)
    foldPath.addLine(to: CGPoint(x: pageRight, y: foldStartY))
    foldPath.closeSubpath()
    
    // Fold Drop Shadow onto Paper
    ctx.setShadow(offset: CGSize(width: -8, height: -8),
                  blur: 14,
                  color: NSColor(white: 0.0, alpha: 0.28).cgColor)
    ctx.addPath(foldPath)
    ctx.setFillColor(NSColor(white: 0.90, alpha: 1.0).cgColor)
    ctx.fillPath()
    
    // Fold Face Gradient with Tint Matching Format Color
    ctx.addPath(foldPath)
    ctx.clip()
    
    let foldGradColors = [
        NSColor(white: 0.98, alpha: 1.0).cgColor,
        NSColor(white: 0.82, alpha: 1.0).cgColor
    ] as CFArray
    if let foldGrad = CGGradient(colorsSpace: colorSpace, colors: foldGradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(foldGrad,
                               start: CGPoint(x: foldStartX, y: pageTop),
                               end: CGPoint(x: pageRight, y: foldStartY),
                               options: [])
    }
    
    // Format Color Subtle Tint Overlay on Fold
    ctx.setFillColor(spec.topColor.withAlphaComponent(0.18).cgColor)
    ctx.fill(CGRect(x: foldStartX, y: foldStartY, width: foldSize, height: foldSize))
    
    // Fold Edge Highlight
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.7).cgColor)
    ctx.setLineWidth(2.0)
    ctx.strokeLineSegments(between: [
        CGPoint(x: foldStartX, y: foldStartY + 14),
        CGPoint(x: foldStartX, y: pageTop)
    ])
    ctx.strokeLineSegments(between: [
        CGPoint(x: foldStartX + 14, y: foldStartY),
        CGPoint(x: pageRight, y: foldStartY)
    ])
    
    // Fold Outer Outline
    ctx.addPath(foldPath)
    ctx.setStrokeColor(NSColor(white: 0.0, alpha: 0.12).cgColor)
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    
    ctx.restoreGState()
    
    // 7. Small UpackX watermark brand symbol in top left
    ctx.saveGState()
    let brandAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0.60, green: 0.65, blue: 0.72, alpha: 0.75),
        .kern: 2.0
    ]
    let brandText = NSAttributedString(string: "UPACKX", attributes: brandAttrs)
    brandText.draw(at: NSPoint(x: pageLeft + 36, y: pageTop - 46))
    ctx.restoreGState()
    
    NSGraphicsContext.restoreGraphicsState()
    
    return rep.representation(using: .png, properties: [:])
}

// Main logic
let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = projectDir.appendingPathComponent("Resources")
let tempIconsetsDir = projectDir.appendingPathComponent("build").appendingPathComponent("iconsets")

try? fileManager.removeItem(at: tempIconsetsDir)
try fileManager.createDirectory(at: tempIconsetsDir, withIntermediateDirectories: true)

let iconSizes: [(name: String, pixelSize: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

print("🎨 Generating \(formats.count) macOS Document Icons for UpackX...")

for spec in formats {
    let iconsetName = "\(spec.fileName).iconset"
    let iconsetURL = tempIconsetsDir.appendingPathComponent(iconsetName)
    let icnsURL = resourcesDir.appendingPathComponent("\(spec.fileName).icns")
    
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    
    print("  ▶ Creating iconset for \(spec.extensionLabel) (\(spec.fileName))...")
    
    for item in iconSizes {
        guard let pngData = renderIconBitmap(spec: spec, pixelSize: item.pixelSize) else {
            fputs("    ⚠️ Failed to render \(item.name) for \(spec.id)\n", stderr)
            continue
        }
        let fileURL = iconsetURL.appendingPathComponent(item.name)
        try pngData.write(to: fileURL)
    }
    
    // Compile iconset to icns using iconutil
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()
    
    if process.terminationStatus == 0 {
        print("    ✅ Generated \(icnsURL.lastPathComponent)")
    } else {
        fputs("    ❌ iconutil failed for \(spec.fileName) with code \(process.terminationStatus)\n", stderr)
        exit(1)
    }
}

// Clean temporary iconsets directory
try? fileManager.removeItem(at: tempIconsetsDir)

print("🎉 Successfully generated all \(formats.count) document icon sets in Resources/!")

