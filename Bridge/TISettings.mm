#import "TISettings.h"
#import "BridgeConvert.h"
#include "../Shared/SettingsKeys.hpp"

namespace s = cu59::settings;

namespace {
std::optional<int> opt(NSNumber* n) { return n ? std::optional<int>(n.intValue) : std::nullopt; }
}

@implementation TISettings

+ (NSString *)startupModelKey { return @(s::kStartupModel); }
+ (NSString *)lastUsedModelKey { return @(s::kLastUsedModel); }
+ (NSString *)solidStateModuleIDKey { return @(s::kSolidStateModuleID); }
+ (NSString *)traceMaxFileSizeMBKey { return @(s::kTraceMaxFileSizeMB); }
+ (NSString *)ledFontStyleKey { return @(s::kLedFontStyle); }

+ (NSInteger)startupLastUsed { return s::kStartupLastUsed; }
+ (NSInteger)defaultTraceMaxMB { return s::kDefaultTraceMaxMB; }
+ (NSInteger)defaultLedFontStyle { return s::kDefaultLedFontStyle; }

+ (NSInteger)resolveStartupModel:(NSNumber *)stored lastUsed:(NSNumber *)lastUsed {
    return static_cast<NSInteger>(s::resolveStartupModel(opt(stored), opt(lastUsed)));
}

+ (NSInteger)resolveTraceMaxMB:(NSNumber *)stored { return s::resolveTraceMaxMB(opt(stored)); }

+ (NSString *)resolveModuleID:(NSString *)stored {
    return ns(s::resolveModuleID(stored ? std::optional<std::string>(cpp(stored)) : std::nullopt));
}

@end
