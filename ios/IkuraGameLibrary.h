/*
 *  IkuraGameLibrary.h - the game library: where the games are, and how
 *  the engine is told about them.
 *
 *  The Android app scans the folder it can reach through
 *  MANAGE_EXTERNAL_STORAGE (/storage/emulated/0/Novels). iOS has no shared
 *  filesystem, so the equivalent is the app's own Documents directory,
 *  which the Files app and Finder can write into because the bundle sets
 *  UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace (see
 *  ios/ikura_ios_Info.plist.in).
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Folder the engine is fed as Cfg::Path::save; also holds the engine log.
extern NSString *const IkuraSaveDirectoryName;

/// Where the game folders live inside the app container.
NSURL *IkuraDocumentsDirectory(void);

/// The savegame directory.
NSURL *IkuraSaveDirectory(void);

@interface IkuraLibrary : NSObject

/// Root view controller of the app: the game library.
+ (UIViewController *)makeRootViewController;

/// Copies the game font shipped inside the bundle into a game folder when
/// the game has none of its own - the same thing GameFontInstaller does on
/// Android. (The host falls back to the bundled copy as well, so this is
/// only about what the game's own dialogs will render with.)
+ (BOOL)installFontIfNeededInGameDirectory:(NSURL *)directory;

/// Every folder in the documents directory is a candidate game, just like
/// Android treats every folder under the novels path.
+ (NSArray<NSURL *> *)gameFolders;

@end

NS_ASSUME_NONNULL_END
