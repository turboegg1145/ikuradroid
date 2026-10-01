/*
 *  main.m - the app's entry point.
 *
 *  This is deliberately *not* SDL's entry point. SDL's own UIKit glue
 *  (src/video/uikit/SDL_uikitappdelegate.m) runs the application's
 *  main() from its UIApplicationDelegate and makes SDL the owner of the
 *  process: when that main() returns, the app is over. This app has to
 *  come up as an ordinary UIKit program instead - library screen first,
 *  one game at a time - so it supplies its own delegate and hands the
 *  main thread to the engine only while a game is being played.
 *
 *  That is still SDL's supported arrangement: a game's whole SDL session
 *  (SDL_Init, window, renderer, event pumping, SDL_Quit) happens on the
 *  main thread inside IkuraHost, exactly where SDL's UIKit backend
 *  expects to be - see ios/IkuraHost.mm.
 */

#import <UIKit/UIKit.h>

/* SDL.h ends by including SDL_main.h, which turns main() into SDL_main()
 * on iOS (include/SDL_main.h: `#if defined(SDL_MAIN_NEEDED) ||
 * defined(SDL_MAIN_AVAILABLE)  #define main SDL_main`). SDL_MAIN_HANDLED
 * is the documented way to keep our own entry point. */
#define SDL_MAIN_HANDLED 1
#include <SDL.h>

#import "IkuraAppDelegate.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		/* SDL_SetMainReady() sets the flag SDL_InitSubSystem() checks
		 * before it does anything (src/SDL.c:113, and
		 * "Application didn't initialize properly, did you include
		 * SDL_main.h ..." at :217). SDL's delegate calls it right
		 * before running the application's main; since this app
		 * supplies its own entry point, it calls it here. */
		SDL_SetMainReady();

		return UIApplicationMain(argc, argv, nil,
					 NSStringFromClass(
						[IkuraAppDelegate class]));
	}
}
