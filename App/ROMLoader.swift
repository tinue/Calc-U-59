import Foundation
import os

struct ModuleMetadata {
    var title: String = ""
    var sort: String = ""
    var id: String = ""
    var menuTitle: String = ""
    var menuSort: Int = 0
}

/// Bundle access for the ROM text dumps (roms/calculator, roms/solid-state)
/// and cuecards.txt. Parsing and checks live in Shared/RomLoader.cpp and
/// Shared/ModuleCatalog.cpp; this only supplies the files.
struct ROMLoader {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calc-U-59", category: "ROMLoader")

    /// Text of a bundled resource by bare file name ("TMC0582.txt").
    private static let bundleReader: TIResourceReader = { fileName in
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

    /// The model's 6144 13-bit ROM words as little-endian UInt16 data.
    static func load(model: MachineModel) throws -> Data {
        try TIFileFormats.loadRom(forModel: model.rawValue, reader: bundleReader)
    }

    /// The model's 64 × 16 constant nibbles.
    static func loadConstants(model: MachineModel) throws -> Data {
        try TIFileFormats.loadConstants(forModel: model.rawValue, reader: bundleReader)
    }

    /// Metadata for all solid-state modules, in menu order.
    static func loadAllModuleMetadata() -> [ModuleMetadata] {
        TIFileFormats.allModuleMetadata(cuecardsText).map(ModuleMetadata.init)
    }

    /// Library image of the module with the given ID.
    static func loadModuleLibrary(moduleID: String) -> Data? {
        guard let file = TIFileFormats.moduleRomFile(cuecardsText, moduleID: moduleID) else {
            logger.error("No MODULE-ROM entry found for module ID \(moduleID, privacy: .public)")
            return nil
        }
        guard let data = TIFileFormats.loadModuleRom(file, reader: bundleReader) else {
            logger.error("Failed to load solid-state ROM \(file, privacy: .public)")
            return nil
        }
        return data
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
        self.init(title: m.title, sort: m.sort, id: m.moduleID, menuTitle: m.menuTitle, menuSort: m.menuSort)
    }
}
