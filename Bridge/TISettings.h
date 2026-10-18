#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift face of Shared/SettingsKeys.hpp: the settings both apps store, their
/// defaults and how a stored value resolves. Type translation only.
@interface TISettings : NSObject

@property (class, readonly) NSString *startupModelKey;
@property (class, readonly) NSString *lastUsedModelKey;
@property (class, readonly) NSString *solidStateModuleIDKey;
@property (class, readonly) NSString *traceMaxFileSizeMBKey;
@property (class, readonly) NSString *ledFontStyleKey;

@property (class, readonly) NSInteger startupLastUsed;
@property (class, readonly) NSInteger defaultTraceMaxMB;
@property (class, readonly) NSInteger defaultLedFontStyle;

/// MachineModel raw value: the stored startup model if valid, else the last used, else TI-59.
+ (NSInteger)resolveStartupModel:(nullable NSNumber *)stored lastUsed:(nullable NSNumber *)lastUsed;
+ (NSInteger)resolveTraceMaxMB:(nullable NSNumber *)stored;
+ (NSString *)resolveModuleID:(nullable NSString *)stored;

@end

NS_ASSUME_NONNULL_END
