import Foundation

#if os(macOS)
import AppKit
#endif

enum AppInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDisplayString: String {
        "Version: \(marketingVersion) (\(buildNumber))"
    }

    // Mirrors text from appstore/metadata/subtitle.txt
    static let subtitle = "Calc-U-59 Calculator Emulation"

    // Condensed from appstore/metadata/description.txt
    static let aboutSummary = "Cycle-accurate TI-59, TI-58, and TI-58C emulation with magnetic cards, paper tape printer, preset state files, and debugger tools."

    // Mirrors URLs from appstore/metadata/*.txt
    static let marketingURL = "https://github.com/tinue/Calc-U-59"
    static let supportURL = "https://github.com/tinue/Calc-U-59/issues"
    static let privacyURL = "https://github.com/tinue/Calc-U-59/blob/main/PRIVACY.md"
}

#if os(macOS)
extension AppInfo {
    static var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .version: "\(marketingVersion) (\(buildNumber))",
            .credits: aboutCredits
        ]
    }

    private static var aboutCredits: NSAttributedString {
        let text = NSMutableAttributedString()

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered
        ]

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: centered
        ]

        text.append(NSAttributedString(string: "\(subtitle)\n", attributes: subtitleAttrs))
        text.append(NSAttributedString(string: "\(aboutSummary)\n\n", attributes: bodyAttrs))

        text.append(linkLine(title: "GitHub", urlString: marketingURL, paragraph: centered))
        text.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        text.append(linkLine(title: "Support", urlString: supportURL, paragraph: centered))
        text.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        text.append(linkLine(title: "Privacy", urlString: privacyURL, paragraph: centered))

        return text
    }

    private static func linkLine(title: String, urlString: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        guard let url = URL(string: urlString) else {
            return NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: paragraph
            ])
        }

        return NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .link: url,
            .paragraphStyle: paragraph
        ])
    }
}
#endif