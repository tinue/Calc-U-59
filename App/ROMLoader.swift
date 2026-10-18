import Foundation
import os

struct ModuleMetadata {
    var title: String = ""
    var id: String = ""
    var menuTitle: String = ""
}

/// Bundle access for the ROM text dumps (roms/calculator, roms/solid-state)
/// and cuecards.txt. Parsing and checks live in Shared/ (RomLoader,
/// ModuleCatalog); this only supplies the files.
struct ROMLoader {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calc-U-59", category: "ROMLoader")

    /// Text of a bundled resource by bare file name ("TMC0582.txt").
    static let bundleReader: TIResourceReader = { fileName in
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// cuecards.txt (roms/solid-state): module metadata and cue cards.
    static var cuecardsText: String {
        guard let text = bundleReader("cuecards.txt") else {
            logger.error("cuecards.txt not found in app bundle")
            return ""
        }
        return text
    }

    /// Metadata for all solid-state modules, in menu order.
    static func loadAllModuleMetadata() -> [ModuleMetadata] {
        TIFileFormats.allModuleMetadata(cuecardsText).map(ModuleMetadata.init)
    }
}

extension ModuleMetadata {
    init(_ m: TIModuleMetadata) {
        self.init(title: m.title, id: m.moduleID, menuTitle: m.menuTitle)
    }
}
