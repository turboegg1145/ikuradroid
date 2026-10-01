/*
 *  IkuraHost.mm - running the engine, on iOS, the way SDL wants it.
 *
 *  One game is one SDL session, and the whole session - SDL_Init, the
 *  window, the renderer, the event pump, SDL_Quit - happens on the main
 *  thread inside +runGameInDirectory:saveDirectory:. SDL's UIKit backend
 *  is a main-thread library (it creates UIWindows and runs the run loop
 *  from inside UIkit_PumpEvents), and SDL's own app delegate runs the
 *  application's main() on the main thread for exactly this reason, so
 *  this is the arrangement the engine was written against - not a
 *  compromise.
 *
 *  The consequence is that the host's own UI is not live while a game
 *  runs: UIKit work queued on the main queue is only serviced from the
 *  run loop spins the engine's event pump performs. That is enough for
 *  three small buttons (below), which is all the host adds on top of the
 *  game - save/load/exit are the engine's own dialogs, driven by the
 *  F5/F6/F9 keys.
 */

#import "IkuraHost.h"
#import "IkuraAppDelegate.h"

/* SDL.h pulls in SDL_main.h, which renames main() to SDL_main() on iOS;
 * SDL_MAIN_HANDLED keeps this file (and ios/main.m) out of that. */
#define SDL_MAIN_HANDLED 1
#include <SDL.h>

#include <string>
#include <vector>

#import <QuartzCore/QuartzCore.h>

/* The engine's main(), renamed at compile time for this target only
 * (ios/CMakeLists.txt: set_source_files_properties(vile.cpp PROPERTIES
 * COMPILE_DEFINITIONS "main=vile_engine_main")). It is C++ - no
 * extern "C" - so the name matches the mangled symbol in vile.o. */
int vile_engine_main(int argc, char **argv);

#pragma mark - in-game overlay

/* SDL's window owns every touch in the game area - that is how the games
 * receive their input. A container view must therefore only accept the
 * touches that land on the buttons it carries. */
@interface IkuraPassthroughView : UIView
@end

@implementation IkuraPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	UIView *hit = [super hitTest:point withEvent:event];
	return (hit == self) ? nil : hit;
}

@end

@interface IkuraOverlayViewController : UIViewController
@end

@implementation IkuraOverlayViewController

- (UIButton *)buttonWithTitle:(NSString *)title key:(int)sdlKey
{
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9]
		     forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
	button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
	button.layer.cornerRadius = 6.0;
	button.layer.borderWidth = 1.0;
	button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
	button.tag = sdlKey;
	[button addTarget:self
		   action:@selector(keyPressed:)
	 forControlEvents:UIControlEventTouchUpInside];
	[button.widthAnchor constraintEqualToConstant:44.0].active = YES;
	[button.heightAnchor constraintEqualToConstant:30.0].active = YES;
	return button;
}

/* The buttons push the same keys a hardware keyboard would; the engine's
 * own dialogs are what actually save, load and quit (engine/ebase.cpp:
 * EventHostKeyDown -> F5 = load, F6 = save, F9 = exit). */
- (void)keyPressed:(UIButton *)sender
{
	[IkuraHost pushKey:(int)sender.tag];
}

- (void)loadView
{
	self.view = [[IkuraPassthroughView alloc] initWithFrame:CGRectZero];
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
				     UIViewAutoresizingFlexibleHeight;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
		[self buttonWithTitle:@"存" key:SDLK_F6],
		[self buttonWithTitle:@"读" key:SDLK_F5],
		[self buttonWithTitle:@"退" key:SDLK_F9],
	]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.spacing = 6.0;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:stack];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6.0],
		[stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
						    constant:-6.0],
	]];
}

@end

/* Top-right of the game picture, below the notch/dynamic island. */
static IkuraOverlayViewController *gOverlayController = nil;
static UIView *gOverlayView = nil;

/* SDL builds its UIWindow for the game; the overlay lives inside that
 * window's own view hierarchy so that it rotates with the game and
 * disappears with it when the session ends. SDL does not hand out the
 * window through a public API, but the class is a stable part of its
 * UIKit backend (src/video/uikit/SDL_uikitwindow.m). */
static UIWindow *IkuraSDLWindow(void)
{
	for (UIWindow *window in [UIApplication sharedApplication].windows) {
		if ([NSStringFromClass([window class]) isEqualToString:@"SDL_uikitwindow"]) {
			return window;
		}
	}
	return nil;
}

static void IkuraAttachOverlay(void)
{
	if (gOverlayView != nil) {
		return;
	}
	UIWindow *window = IkuraSDLWindow();
	UIView *host = window.rootViewController.view;
	if (host == nil) {
		NSLog(@"[IkuraDroid] SDL window is not ready; the in-game buttons stay hidden");
		return;
	}
	gOverlayController = [[IkuraOverlayViewController alloc] init];
	gOverlayView = gOverlayController.view;
	gOverlayView.frame = host.bounds;
	[host addSubview:gOverlayView];
}

static void IkuraRemoveOverlay(void)
{
	[gOverlayView removeFromSuperview];
	gOverlayView = nil;
	gOverlayController = nil;
}

/* SDL_AddEventWatch() reports every event as it is queued, which is the
 * earliest reliable moment at which the game's window exists (the engine
 * creates it with SDL_WINDOW_SHOWN, so SDL reports SDL_WINDOWEVENT_SHOWN).
 * The UIKit part is deferred to the main queue: it must not run inside
 * SDL's event handling, and the engine's next event pump drains the main
 * queue a frame later anyway. */
static int SDLCALL IkuraWindowShown(void *userdata, SDL_Event *event)
{
	(void)userdata;
	if (event->type != SDL_WINDOWEVENT ||
	    event->window.event != SDL_WINDOWEVENT_SHOWN) {
		return 1;
	}
	SDL_DelEventWatch(IkuraWindowShown, NULL);
	dispatch_async(dispatch_get_main_queue(), ^{
		IkuraAttachOverlay();
	});
	return 1;
}

@implementation IkuraHost

+ (int)runGameInDirectory:(NSString *)gameDirectory
	    saveDirectory:(NSString *)saveDirectory
{
	NSAssert([NSThread isMainThread],
		 @"the engine owns the entire SDL session and must run on the main thread");

	NSFileManager *files = [NSFileManager defaultManager];
	if (![files changeCurrentDirectoryPath:gameDirectory]) {
		NSLog(@"[IkuraDroid] cannot enter %@", gameDirectory);
		return -1;
	}

	/* The game's own font wins; the copy shipped in the app bundle is the
	 * fallback. (The Android port does the same thing from Java: it copies
	 * its bundled default.ttf into the game folder before launching.) */
	NSString *font = [gameDirectory stringByAppendingPathComponent:@"default.ttf"];
	if (![files fileExistsAtPath:font]) {
		NSString *bundled = [[NSBundle mainBundle] pathForResource:@"default"
								   ofType:@"ttf"];
		if (bundled != nil) {
			font = bundled;
		}
	}

	/* The C strings handed to the engine have to stay alive: std::string
	 * storage owns them. reserve() up front so that no later push_back can
	 * reallocate and leave argv() pointing at freed memory. */
	std::vector<std::string> storage;
	storage.reserve(16);
	std::vector<char *> argv;
	argv.reserve(16);
	auto add = [&](NSString *value) {
		storage.push_back(value.UTF8String);
		argv.push_back(const_cast<char *>(storage.back().c_str()));
	};

	add(@"ikuradroid");
	add(@"--cwd");
	add(gameDirectory);
	add(@"--game");
	add(gameDirectory);
	add(@"--save");
	add(saveDirectory);
	add(@"--fontface");
	add(font);
	argv.push_back(NULL);

	/* The games are landscape and the library screen is portrait (see
	 * IkuraAppDelegate). SDL asks UIKit for its mask while it creates the
	 * window, so the hint has to be set before the engine runs. */
	SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

	/* SDL ignores UIKit's touch and key events until this is on
	 * (SDL_uikitevents.m: UIKit_PumpEvents returns immediately while the
	 * pump is disabled); SDL's own delegate turns it on around the
	 * application's main() and off again when it returns. */
	SDL_AddEventWatch(IkuraWindowShown, NULL);
	SDL_iPhoneSetEventPump(SDL_TRUE);

	int status = vile_engine_main((int)argv.size() - 1, argv.data());

	SDL_iPhoneSetEventPump(SDL_FALSE);
	SDL_DelEventWatch(IkuraWindowShown, NULL);
	IkuraRemoveOverlay();

	/* The engine quit SDL, so the game's window is gone; leave the working
	 * directory wherever the library screens expect it and bring their
	 * window back to the front. */
	NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
	if (bundlePath != nil) {
		[files changeCurrentDirectoryPath:bundlePath];
	}
	[(IkuraAppDelegate *)[[UIApplication sharedApplication] delegate] restoreLibraryWindow];

	return status;
}

+ (void)pushKey:(int)sdlKeycode
{
	SDL_Event event;
	SDL_zero(event);
	event.type = SDL_KEYDOWN;
	event.key.state = SDL_PRESSED;
	event.key.keysym.sym = (SDL_Keycode)sdlKeycode;
	SDL_PushEvent(&event);

	SDL_zero(event);
	event.type = SDL_KEYUP;
	event.key.state = SDL_RELEASED;
	event.key.keysym.sym = (SDL_Keycode)sdlKeycode;
	SDL_PushEvent(&event);
}

@end
