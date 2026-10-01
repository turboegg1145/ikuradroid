#  IkuraDroid on iOS

An iOS 14.0+ build of [ikuradroid](https://github.com/VienDesuPorting/ikuradroid), the
ViLE engine port for Ikura/Takajun style visual novels.

There is no App Store build and there never will be: the engine is GPLv3 and the
store's DRM is incompatible with it. The IPA this repository produces is
**unsigned**, meant for TrollStore or for re-signing with AltStore/Sideloadly.

##  Getting the IPA

The `.github/workflows/ios.yml` workflow builds one on every push to `ios-port`
(or on demand through *Actions → iOS IPA → Run workflow*). Download
`IkuraDroid-unsigned-ipa` from the run's artifacts.

##  Installing

| iOS | Installer | Notes |
| --- | --------- | ----- |
| 14.0 beta 2 – 16.6.1 | [TrollStore](https://github.com/opa334/TrollStore) | Permanent. Open the IPA in TrollStore, install, done. |
| 14.0 – 17.x | [AltStore](https://altstore.io) / [Sideloadly](https://sideloadly.io) | Re-signs every 7 days unless you pay for a developer account. |
| 14.0 – 17.x | `xcodebuild` / `ios-deploy` with your own certificate | For developing. |

iOS 14.4 (the version this port was asked for) is covered by both TrollStore and
the self-signing route.

##  Where the games go

`On My iPhone/iPad → IkuraDroid →` one folder per game, next to the `Saves`
folder:

```
IkuraDroid/
  Saves/               save files (40 slots per game, prefix "save")
  Divi-Dead/           a game folder: whatever the game ships
  .../default.ttf      optional - the app's own font is used otherwise
```

On the device that is the app's `Documents` directory; `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` are set, so the Files app can copy games in
and out. Android reads `/storage/emulated/0/Novels` directly because it has
`MANAGE_EXTERNAL_STORAGE`; iOS has no equivalent and no external storage at all,
which is why games live inside the app's own container.

The app's built-in `default.ttf` (the same file the Android app ships) is copied
into the game folder at launch if the game has no font of its own — the engine
looks for `default.ttf` in the game directory.

##  Running a game

Pick a folder in the library screen. The engine takes over the screen; the small
buttons in the top right corner map to the engine's own keys:

| Button | Key | What it does |
| ------ | --- | ------------ |
| 存 | F6 | Engine save dialog (`StdSave`) |
| 读 | F5 | Engine load dialog (`StdLoad`) |
| 退 | F9 | "Exit game?" - OK returns to the library |

Save and load use the engine's own dialogs (not a native iOS screen, as on
Android) because they read and write the savegame container through the code
that already knows the game state. Files land in `Saves/save000` … `save039`,
the same 40 slots the Android version shows.

##  How it is put together

```
ios/
  CMakeLists.txt          two targets: ikura_engine (static) and the app bundle
  main.m                  main() + SDL_SetMainReady() + UIApplicationMain
  IkuraAppDelegate.*      window, audio session, orientation policy
  IkuraGameLibrary.*      library screen (table view) + game folder discovery
  IkuraHost.*             runs a game, key injection, the in-game overlay
  tools/build-deps.sh     builds SDL2 / SDL2_image / SDL2_ttf / SDL2_mixer
```

The engine is compiled from `app/src/main/jni/vile` exactly as the NDK build
does it (same wildcard collection, same `-DVILE_ARCH_LINUX`), plus the vendored
SDL2_gfx sources. `vile.cpp`'s `main()` is renamed to `vile_engine_main()` so the
app keeps its own entry point.

**One game = one SDL session, on the main thread.** SDL's UIKit backend creates
windows with `makeKeyAndVisible` and pumps the Cocoa run loop, both of which are
main-thread work; that is why the engine is not run on a worker thread the way
Android runs it inside its separate `:game` process. The library screen is gone
for the duration of a game, and comes back when the engine returns and
`SDL_Quit()` has torn the SDL window down.

The overlay buttons are plain `UIButton`s added to the SDL window's own view
controller. A second `UIWindow` would not rotate with the game, and SDL only
allows one window per display.

##  Known gaps

* **Audio**: WAV, OGG (stb_vorbis), MP3 (minimp3) and FLAC (dr_flac) all work.
  MOD and MIDI do not — the Android build links libmodplug/libmikmod and
  timidity for those, and neither is in SDL2_mixer's own source tarball. A game
  whose music is `.mod`/`.mid` will be silent.
* **Images**: PNG and JPEG (stb) plus the formats SDL_image decodes itself
  (BMP/GIF/LBM/PCG/PNM/TGA/XCF/XPM/XV/QOI). WebP needs a libwebp build; add
  `-DSDL2IMAGE_WEBP=ON` to `ios/tools/build-deps.sh` plus libwebp in the same
  prefix if a game needs it.
* **Video**: MPEG-1 playback goes through the engine's own `pl_mpeg` decoder, so
  it works on iOS as-is.
* No iOS build of the Android-only native save screen: the engine's dialogs are
  used instead (see above).
