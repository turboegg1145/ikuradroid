/*
 *  IkuraGameLibrary.m - the library screen.
 *
 *  Playing a game is one synchronous call into IkuraHost - the engine owns
 *  the main thread for as long as the game lasts (see ios/IkuraHost.h) -
 *  so the only thing this screen has to do is get out of the way first and
 *  refresh afterwards.
 *
 *  The UI is deliberately plain UIKit built in code: the app is compiled
 *  by a command line CMake build with no asset catalog and no storyboard,
 *  so everything it draws is here in source.
 */

#import "IkuraGameLibrary.h"
#import "IkuraHost.h"

NSString *const IkuraSaveDirectoryName = @"Saves";

NSURL *IkuraDocumentsDirectory(void)
{
	NSURL *url = [[NSFileManager defaultManager]
		URLsForDirectory:NSDocumentDirectory
		      inDomains:NSUserDomainMask][0];
	[[NSFileManager defaultManager] createDirectoryAtURL:url
				 withIntermediateDirectories:YES
						  attributes:nil
						       error:NULL];
	return url;
}

/* Both screens are built here, so they are declared before the class that
 * uses them (the library screen presents the cover, the cover is what the
 * library world looks like while the engine has the main thread). */
@interface LibraryViewController : UITableViewController
@end

/// Shown between picking a game and the engine's first frame.
@interface LoadingViewController : UIViewController
@end

NSURL *IkuraSaveDirectory(void)
{
	NSURL *url = [IkuraDocumentsDirectory()
		URLByAppendingPathComponent:IkuraSaveDirectoryName isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:url
				 withIntermediateDirectories:YES
						  attributes:nil
						       error:NULL];
	return url;
}

@implementation IkuraLibrary

+ (UIViewController *)makeRootViewController
{
	return [[UINavigationController alloc]
		initWithRootViewController:[[LibraryViewController alloc] init]];
}

+ (BOOL)installFontIfNeededInGameDirectory:(NSURL *)directory
{
	NSURL *target = [directory URLByAppendingPathComponent:@"default.ttf"];
	if ([[NSFileManager defaultManager] fileExistsAtPath:target.path]) {
		return YES;
	}
	NSURL *source = [[NSBundle mainBundle] URLForResource:@"default"
					       withExtension:@"ttf"];
	if (source == nil) {
		return NO;
	}
	NSError *error = nil;
	if (![[NSFileManager defaultManager] copyItemAtURL:source
						    toURL:target
						    error:&error]) {
		NSLog(@"[IkuraDroid] could not install the game font: %@", error);
		return NO;
	}
	return YES;
}

+ (NSArray<NSURL *> *)gameFolders
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray<NSURL *> *contents = [files contentsOfDirectoryAtURL:IkuraDocumentsDirectory()
				  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
						     options:NSDirectoryEnumerationSkipsHiddenFiles
						       error:NULL];
	if (contents == nil) {
		contents = @[];
	}
	NSMutableArray<NSURL *> *games = [NSMutableArray array];
	for (NSURL *url in contents) {
		if ([url.lastPathComponent isEqualToString:IkuraSaveDirectoryName]) {
			continue;
		}
		NSNumber *isDirectory = nil;
		if ([url getResourceValue:&isDirectory
				   forKey:NSURLIsDirectoryKey
				    error:NULL] && isDirectory.boolValue) {
			[games addObject:url];
		}
	}
	[games sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
	}];
	return games;
}

@end

#pragma mark - library screen

@implementation LibraryViewController {
	NSArray<NSURL *> *_games;
	UIRefreshControl *_refresh;
	UILabel *_emptyLabel;
	/// Set from the moment a game is picked until the engine has returned:
	/// while it is set, this screen is covered and the main thread belongs
	/// to the engine.
	BOOL _launching;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.title = @"IkuraDroid";
	self.navigationItem.rightBarButtonItem = self.editButtonItem;
	self.tableView.tableFooterView = [[UIView alloc] init];
	[self.tableView registerClass:[UITableViewCell class]
	       forCellReuseIdentifier:@"game"];

	_emptyLabel = [[UILabel alloc] init];
	_emptyLabel.text = @"No games yet.\n\n"
		"Copy a game folder into this app's Documents folder with the "
		"Files app or Finder, then pull down to refresh.";
	_emptyLabel.numberOfLines = 0;
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.textColor = [UIColor secondaryLabelColor];

	_refresh = [[UIRefreshControl alloc] init];
	[_refresh addTarget:self
		     action:@selector(reloadGames)
	   forControlEvents:UIControlEventValueChanged];
	self.tableView.refreshControl = _refresh;

	[[NSNotificationCenter defaultCenter] addObserver:self
						selector:@selector(reloadGames)
						    name:UIApplicationDidBecomeActiveNotification
						  object:nil];

	[self reloadGames];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	_emptyLabel.frame = CGRectInset(self.tableView.bounds, 32.0, 0.0);
	self.tableView.backgroundView = _emptyLabel;
	self.tableView.backgroundView.hidden = (_games.count > 0);
}

- (void)reloadGames
{
	_games = [IkuraLibrary gameFolders];
	[_refresh endRefreshing];
	[self.tableView reloadData];
	self.tableView.backgroundView.hidden = (_games.count > 0);
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView
	numberOfRowsInSection:(NSInteger)section
{
	return (NSInteger)_games.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
	 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"game"
							       forIndexPath:indexPath];
	cell.textLabel.text = _games[(NSUInteger)indexPath.row].lastPathComponent;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView
	didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self launchGameAtDirectory:_games[(NSUInteger)indexPath.row]];
}

- (void)  tableView:(UITableView *)tableView
 commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
  forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle != UITableViewCellEditingStyleDelete) {
		return;
	}
	NSError *error = nil;
	if (![[NSFileManager defaultManager] removeItemAtURL:_games[(NSUInteger)indexPath.row]
						       error:&error]) {
		UIAlertController *alert =
			[UIAlertController alertControllerWithTitle:@"Could not delete"
							    message:error.localizedDescription
						     preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK"
							  style:UIAlertActionStyleDefault
							handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	NSMutableArray<NSURL *> *games = [_games mutableCopy];
	[games removeObjectAtIndex:(NSUInteger)indexPath.row];
	_games = games;
	[tableView deleteRowsAtIndexPaths:@[indexPath]
			 withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - launch

/* Runs one game. The engine takes over the main thread inside
 * IkuraHost.runGame, so the cover has to be on screen first and the call
 * has to happen after this run loop turn - otherwise nothing would be
 * drawn at all until the engine's first frame is committed. */
- (void)launchGameAtDirectory:(NSURL *)directory
{
	if (_launching) {
		return;
	}
	_launching = YES;

	[IkuraLibrary installFontIfNeededInGameDirectory:directory];

	LoadingViewController *cover = [[LoadingViewController alloc] init];
	cover.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:cover
			   animated:NO
			 completion:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			int status = [IkuraHost runGameInDirectory:directory.path
						     saveDirectory:IkuraSaveDirectory().path];

			[self dismissViewControllerAnimated:NO completion:^{
				self->_launching = NO;
				[self reloadGames];
				if (status != 0) {
					[self reportEngineFailure:status
							     game:directory.lastPathComponent];
				}
			}];
		});
	}];
}

- (void)reportEngineFailure:(int)status game:(NSString *)game
{
	NSString *log = [[IkuraSaveDirectory()
		URLByAppendingPathComponent:@"ikuradroid_log.txt"] path];
	NSString *message = [NSString stringWithFormat:
		@"The engine stopped with status %d.\n\nThe log is %@", status, log];
	UIAlertController *alert =
		[UIAlertController alertControllerWithTitle:
			[NSString stringWithFormat:@"“%@” did not start", game]
						    message:message
					     preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK"
						  style:UIAlertActionStyleDefault
						handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - cover shown while the engine starts

@implementation LoadingViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor blackColor];

	UIActivityIndicatorView *spinner =
		[[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	spinner.color = [UIColor whiteColor];
	[spinner startAnimating];
	spinner.translatesAutoresizingMaskIntoConstraints = NO;

	UILabel *label = [[UILabel alloc] init];
	label.text = @"Starting…";
	label.textColor = [UIColor whiteColor];
	label.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:spinner];
	[self.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:12.0],
	]];
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

@end
