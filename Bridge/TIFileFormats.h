#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ file formats: cue cards, state files, card files,
// ti58c.mem, ROM text dumps and cuecards.txt. Type translation only — the
// formats live in Shared/ (CueCard, StateFile, CardFile, ConstantMemory,
// RomLoader, ModuleCatalog).

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
+ (NSString *)expandMathTokens:(NSString *)input;
+ (NSString *)invisibleMarker;
@end

/// One KEYSTROKES event (Shared/StateFile.hpp KeystrokeEvent::Kind order:
/// 0 key, 1 toggleTrace, 2 wait, 3 waitFullSpeed, 4 trace, 5 fullSpeed,
/// 6 regularSpeed, 7 zeroElapseTime, 8 reportElapseTime).
@interface TIKeystrokeEvent : NSObject
@property (nonatomic, readonly) NSInteger kind;
@property (nonatomic, readonly) uint8_t code;
@property (nonatomic, readonly) double seconds;
@property (nonatomic, readonly, copy, nullable) NSString *traceName;
@end

@interface TIRegisterValue : NSObject
@property (nonatomic, readonly) NSInteger regNum;
@property (nonatomic, readonly, copy) NSData *nibbles;   ///< 16 bytes
@property (nonatomic, readonly) BOOL isHidden;
@end

@interface TIStateFileResult : NSObject
@property (nonatomic, readonly) NSInteger partitionMaxStep;
@property (nonatomic, readonly) BOOL partitionWasExplicit;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *programStepAddrs;
@property (nonatomic, readonly, copy) NSData *programStepKeycodes;  ///< parallel to programStepAddrs
@property (nonatomic, readonly, copy) NSArray<TIRegisterValue *> *registers;
@property (nonatomic, readonly, copy) NSArray<TIKeystrokeEvent *> *keystrokes;
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
@property (nonatomic, readonly, copy) NSString *sort;
@property (nonatomic, readonly, copy) NSString *moduleID;
@property (nonatomic, readonly, copy) NSString *menuTitle;
@property (nonatomic, readonly) NSInteger menuSort;
@end

@interface TIModuleCards : NSObject
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, TICueCard *> *cards;
@property (nonatomic, readonly) TIModuleMetadata *metadata;
@end

/// Returns a bundled resource's text by bare file name, or nil.
typedef NSString *_Nullable (^TIResourceReader)(NSString *fileName);

@interface TIFileFormats : NSObject

// ── Cue cards ────────────────────────────────────────────────────────────────
+ (void)cueCard:(TICueCard *)card parseLine:(NSString *)line;
/// templateKind -1 = no "Template:" line.
+ (NSArray<NSString *> *)encodeCueCard:(TICueCard *)card template:(NSInteger)templateKind;

// ── State files ──────────────────────────────────────────────────────────────
+ (TIStateFileResult *)parseStateFile:(NSString *)text maxStepAddr:(NSInteger)maxStepAddr
                 allowHiddenRegisters:(BOOL)allowHidden;
/// Target model (MachineModel raw value) and SKIP-RESET, read before parsing.
+ (NSInteger)prescanStateFile:(NSString *)text currentModel:(NSInteger)current skipReset:(BOOL *_Nullable)skipReset;

// ── Card files and ti58c.mem ─────────────────────────────────────────────────
+ (TICardFile *)decodeCardFile:(NSData *)raw fileName:(NSString *)fileName;
+ (NSString *)encodeCardText:(NSData *)bank cueCard:(nullable TICueCard *)cueCard;
+ (NSString *)encodeConstantMemory:(NSData *)ram cueCard:(nullable TICueCard *)cueCard;
+ (nullable TIConstantMemory *)decodeConstantMemory:(NSString *)text;

// ── ROM text dumps and cuecards.txt ──────────────────────────────────────────
/// 6144 13-bit words, little-endian uint16. nil + error on failure.
+ (nullable NSData *)loadRomForModel:(NSInteger)model reader:(TIResourceReader)reader
                               error:(NSError *_Nullable *_Nullable)error;
/// 64 × 16 constant nibbles. nil + error on failure.
+ (nullable NSData *)loadConstantsForModel:(NSInteger)model reader:(TIResourceReader)reader
                                     error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSData *)loadModuleRom:(NSString *)romFile reader:(TIResourceReader)reader;
+ (NSArray<TIModuleMetadata *> *)allModuleMetadata:(NSString *)cuecardsTxt;
+ (nullable NSString *)moduleRomFile:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID;
+ (TIModuleCards *)moduleCards:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID;

@end

NS_ASSUME_NONNULL_END
