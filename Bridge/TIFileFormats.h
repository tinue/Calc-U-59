#import <Foundation/Foundation.h>
#import "TI59MachineWrapper.h"

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ file formats: cue cards, state files, card files,
// ti58c.mem and cuecards.txt. Type translation only — the
// formats live in Shared/ (CueCard, StateFile, CardFile, ConstantMemory,
// ModuleCatalog).

/// A cue card (Shared/CueCard.hpp). Enum-valued properties use the C++
/// enumerator order: template 0 CueCard, 1 MagnetCard, 2 SolidStateCard;
/// align 0 left, 1 center, 2 right; style 0 none, 1 button; color 0 black,
/// 1 pencil, 2 sharpie.
@interface TICueCard : NSObject
@property (nonatomic) NSInteger templateKind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSNumber *bankLeft;
@property (nonatomic, copy, nullable) NSNumber *bankRight;
@property (nonatomic, copy) NSString *cardID;
/// [A′,B′,C′,D′,E′, A,B,C,D,E] — always 10 entries.
@property (nonatomic, copy) NSArray<NSString *> *labels;
@property (nonatomic, copy) NSString *row1;
@property (nonatomic) NSInteger row1Align;
@property (nonatomic, copy) NSString *row2;
@property (nonatomic) NSInteger row2Align;
@property (nonatomic, copy) NSString *row2R;
@property (nonatomic) NSInteger row2RAlign;
@property (nonatomic) NSInteger style;
@property (nonatomic) NSInteger color;

+ (TICueCard *)ml01Default;
@end

/// A parsed state file. Partition, program and registers are not exposed:
/// they go back to Shared/StateApplier through applyState:to:model:.
@interface TIStateFileResult : NSObject
@property (nonatomic, readonly) BOOL hasKeystrokes;
@property (nonatomic, readonly, nullable) TICueCard *cueCard;
@property (nonatomic, readonly, copy, nullable) NSString *solidStateModuleID;
@property (nonatomic, readonly, copy, nullable) NSNumber *printerConnected;  ///< BOOL
@property (nonatomic, readonly) NSInteger model;      ///< MachineModel raw value, -1 = not given
@property (nonatomic, readonly) BOOL skipReset;
@property (nonatomic, readonly, copy) NSArray<NSString *> *errors;
@end

@interface TICardFile : NSObject
@property (nonatomic, readonly, copy, nullable) NSData *data;   ///< bank image; nil on error
@property (nonatomic, readonly, nullable) TICueCard *cueCard;
@property (nonatomic, readonly) BOOL isText;
@property (nonatomic, readonly, copy) NSString *error;          ///< empty on success
@end

@interface TIConstantMemory : NSObject
@property (nonatomic, readonly, copy) NSData *ram;              ///< 1920 bytes
@property (nonatomic, readonly, nullable) TICueCard *cueCard;
@end

@interface TIModuleMetadata : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *moduleID;
@property (nonatomic, readonly, copy) NSString *menuTitle;
@end

@interface TIModuleCards : NSObject
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, TICueCard *> *cards;
@property (nonatomic, readonly) TIModuleMetadata *metadata;
@end

/// Returns a bundled resource's text by bare file name, or nil.
typedef NSString *_Nullable (^TIResourceReader)(NSString *fileName);

@interface TIFileFormats : NSObject

// ── State files ──────────────────────────────────────────────────────────────
+ (TIStateFileResult *)parseStateFile:(NSString *)text maxStepAddr:(NSInteger)maxStepAddr
                 allowHiddenRegisters:(BOOL)allowHidden;
/// Why `result` can't be applied to `model`, or nil (Shared/StateApplier.hpp).
+ (nullable NSString *)partitionErrorFor:(TIStateFileResult *)result model:(NSInteger)model;
/// Write a parsed file into the machine (full load / SKIP-RESET load). Run on
/// the emulation queue with the run loop stopped.
+ (void)applyState:(TIStateFileResult *)result to:(TI59MachineWrapper *)machine model:(NSInteger)model;
+ (void)applySkipResetState:(TIStateFileResult *)result to:(TI59MachineWrapper *)machine model:(NSInteger)model;
/// Target model (MachineModel raw value) and SKIP-RESET, read before parsing.
+ (NSInteger)prescanStateFile:(NSString *)text currentModel:(NSInteger)current skipReset:(BOOL *_Nullable)skipReset;

// ── Card files and ti58c.mem ─────────────────────────────────────────────────
+ (TICardFile *)decodeCardFile:(NSData *)raw fileName:(NSString *)fileName;
+ (NSString *)encodeCardText:(NSData *)bank cueCard:(nullable TICueCard *)cueCard;
+ (NSString *)encodeConstantMemory:(NSData *)ram cueCard:(nullable TICueCard *)cueCard;
+ (nullable TIConstantMemory *)decodeConstantMemory:(NSString *)text;
/// Card pickers list only these (.u59 / .bin in any case, not hidden).
+ (BOOL)isCardFileName:(NSString *)name;
/// ".U59" appended when the name has no extension.
+ (NSString *)withDefaultCardExtension:(NSString *)name;

// ── cuecards.txt ─────────────────────────────────────────────────────────────
+ (NSArray<TIModuleMetadata *> *)allModuleMetadata:(NSString *)cuecardsTxt;
+ (nullable NSString *)moduleRomFile:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID;
+ (TIModuleCards *)moduleCards:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID;

@end

NS_ASSUME_NONNULL_END
