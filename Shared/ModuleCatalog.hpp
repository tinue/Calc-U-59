#pragma once
#include "CueCard.hpp"
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// roms/solid-state/cuecards.txt: one section per Solid State Software module
// (MODULE-ID first, then MODULE-TITLE / -SORT / -MENU-TITLE / -MENU-SORT /
// -ROM), followed by "CUECARD: n" blocks — the cue card for library program n.
// '#' starts a comment.

namespace cu59 {

struct ModuleMetadata {
    std::string title;
    std::string sort;
    std::string id;
    std::string menuTitle;
    int menuSort = 0;
};

/// Every module's metadata in menu order (MODULE-MENU-SORT, file order on ties).
std::vector<ModuleMetadata> allModuleMetadata(std::string_view cuecardsTxt);

/// The MODULE-ROM file name for a module ID (e.g. "ML" → "TMC0541.txt").
std::optional<std::string> moduleRomFile(std::string_view cuecardsTxt, std::string_view moduleID);

struct ModuleCards {
    std::map<int, CueCardContent> cards;  ///< library program number → cue card
    ModuleMetadata metadata;
};

/// Cue cards and metadata of one module.
ModuleCards moduleCards(std::string_view cuecardsTxt, std::string_view moduleID);

} // namespace cu59
