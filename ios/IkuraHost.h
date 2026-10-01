/*
 *  IkuraHost.h - the whole iOS host interface.
 *
 *  One game is played by one call to +runGameInDirectory:saveDirectory:
 *  on the main thread: the engine then owns the process until the player
 *  leaves the game, and the next call starts the next game.
 *
 *  Why the main thread: SDL's UIKit backend is a main-thread library - it
 *  builds UIWindows in its event-pumping code, makes them key, and pumps
 *  the UIKit run loop in place - so the main thread is where SDL expects
 *  the application's main() to run. See ios/IkuraHost.mm.
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IkuraHost : NSObject

/// Runs one game to completion. `gameDirectory` holds the game's files
/// (the engine is chdir()ed into it), `saveDirectory` receives the save
/// files and the engine log. Returns the engine's exit status.
+ (int)runGameInDirectory:(NSString *)gameDirectory
	    saveDirectory:(NSString *)saveDirectory;

/// Queues one key press on the engine's event queue. Used by the in-game
/// overlay, which drives the engine's own dialogs with the F5/F6/F9 keys
/// (load / save / exit) exactly like a hardware keyboard would.
+ (void)pushKey:(int)sdlKeycode;

@end

NS_ASSUME_NONNULL_END
