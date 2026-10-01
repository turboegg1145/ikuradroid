/*
 *  IkuraAppDelegate.h - the app's UIKit delegate.
 *
 *  See IkuraHost.h for how a game is started; this header is what the
 *  delegate and the host share.
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IkuraAppDelegate : UIResponder <UIApplicationDelegate>

/// The library window. SDL builds a window of its own on top of it for
/// the duration of a game, so this one is what the user sees before and
/// after.
@property (nonatomic, strong) UIWindow *window;

/// Brings the library window back to the front once a game is over
/// (SDL's window was key while the game ran, and it is destroyed with
/// the game's SDL session).
- (void)restoreLibraryWindow;

@end

NS_ASSUME_NONNULL_END
