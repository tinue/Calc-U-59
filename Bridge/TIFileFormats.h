#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ formats the views use directly: the cue-card
// model, cuecards.txt's module list and the card pickers' file names. Type
// translation only — the formats live in Shared/ (CueCard, ModuleCatalog,
// CardFile); everything else goes through TISessionController.

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

@interface TIModuleMetadata : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *moduleID;
@property (nonatomic, readonly, copy) NSString *menuTitle;
@end

/// Returns a bundled resource's text by bare file name, or nil.
typedef NSString *_Nullable (^TIResourceReader)(NSString *fileName);

@interface TIFileFormats : NSObject

/// Card pickers list only these (.u59 / .bin in any case, not hidden).
+ (BOOL)isCardFileName:(NSString *)name;
/// ".U59" appended when the name has no extension.
+ (NSString *)withDefaultCardExtension:(NSString *)name;

// ── cuecards.txt ─────────────────────────────────────────────────────────────
+ (NSArray<TIModuleMetadata *> *)allModuleMetadata:(NSString *)cuecardsTxt;

@end

NS_ASSUME_NONNULL_END
