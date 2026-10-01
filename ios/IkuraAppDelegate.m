/*
 *  IkuraAppDelegate.m - brings the library up and keeps the app's audio
 *  session in a state the engine can use.
 *
 *  A game is played by calling IkuraHost from the main thread (see
 *  IkuraHost.h); nothing in this delegate has to coordinate that, because
 *  the library screens are not live while a game runs.
 */

#import <AVFoundation/AVFoundation.h>

#import "IkuraAppDelegate.h"
#import "IkuraGameLibrary.h"
#import "IkuraHost.h"

@implementation IkuraAppDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	/* The engine opens audio devices with SDL_mixer/CoreAudio. Setting
	 * the category and activating the session once, here, is the same
	 * thing SDL's own delegate does (SDL_uikitappdelegate.m); the
	 * engine's SDL_OpenAudioDevice then just works. Playback because
	 * the games play music and voices and must not obey the ring
	 * switch. */
	AVAudioSession *session = [AVAudioSession sharedInstance];
	NSError *error = nil;
	[session setCategory:AVAudioSessionCategoryPlayback error:&error];
	if (error) {
		NSLog(@"[IkuraDroid] could not set the audio session category: %@", error);
	}
	error = nil;
	[session setActive:YES error:&error];
	if (error) {
		NSLog(@"[IkuraDroid] could not activate the audio session: %@", error);
	}

	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [IkuraLibrary makeRootViewController];
	[self.window makeKeyAndVisible];

	return YES;
}

- (void)restoreLibraryWindow
{
	[self.window makeKeyAndVisible];
}

/* The library is portrait; SDL's window (which SDL sets up full screen for
 * the game) has to follow SDL_HINT_ORIENTATIONS, which IkuraHost sets to
 * landscape around a game. UIKit consults this before the window's own
 * view controller, so ask that controller rather than guessing - SDL turns
 * the hint into its supportedInterfaceOrientations. */
- (UIInterfaceOrientationMask)application:(UIApplication *)application
	supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
	if (window == self.window) {
		return UIInterfaceOrientationMaskPortrait;
	}
	UIViewController *root = window.rootViewController;
	if (root != nil) {
		return [root supportedInterfaceOrientations];
	}
	return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
