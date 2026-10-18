import Foundation
import os

struct ModuleMetadata {
    var title: String = ""
    var id: String = ""
    var menuTitle: String = ""
}

/// Bundle access for the ROM text dumps (roms/calculator, roms/solid-state)
/// and cuecards.txt. Parsing and checks live in Shared/RomLoader.cpp and
/// Shared/ModuleCatalog.cpp; this only supplies the files.
struct ROMLoader {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calc-U-59", category: "ROMLoader")

    /// Text of a bundled resource by bare file name ("TMC0582.txt").
    static let bundleReader: TIResourceReader = { fileName in
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static var cuecardsText: String {
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

    /// The ROM file (MODULE-ROM) of the module with the given ID.
    static func moduleRomFile(moduleID: String) -> String? {
        guard let file = TIFileFormats.moduleRomFile(cuecardsText, moduleID: moduleID) else {
            logger.error("No MODULE-ROM entry found for module ID \(moduleID, privacy: .public)")
            return nil
        }
        return file
    }

    /// Per-program cue cards (program number → card) and metadata of one module.
    static func loadModuleCardsAndMetadata(moduleID: String) -> ([Int: CueCardContent], ModuleMetadata) {
        let mc = TIFileFormats.moduleCards(cuecardsText, moduleID: moduleID)
        var cards: [Int: CueCardContent] = [:]
        for (n, card) in mc.cards { cards[n.intValue] = CueCardContent(card) }
        return (cards, ModuleMetadata(mc.metadata))
    }
}

extension ModuleMetadata {
    init(_ m: TIModuleMetadata) {
        self.init(title: m.title, id: m.moduleID, menuTitle: m.menuTitle)
    }
}
