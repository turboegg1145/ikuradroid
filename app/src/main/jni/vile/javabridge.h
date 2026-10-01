/*! \file javabridge.h
 *  \brief Host UI <-> engine bridge.
 *
 * The engine's save/load handling calls this small interface, and each
 * platform answers it in the way that fits its UI:
 *
 *   Android  the Java slot dialog reads savegame files directly
 *            (SaveLoadDialog / SaveFileRepository), so the bridge says
 *            "an external UI took the request" and offers the savegame
 *            filename prefix (NativeID) plus a one-shot "save/load slot
 *            N" trigger.
 *
 *   iOS      there is no external slot UI: the games' own menus call
 *            EngineVN::EventGameDialog(VD_SAVE/VD_LOAD), and the bridge
 *            answers "no external UI", so the engine mounts its own
 *            StdSave/StdLoad widgets. Those write the savegame through
 *            the very code that knows the game state, which is less
 *            code and less to get wrong than mirroring the container
 *            format in a second UI.
 *
 *   desktop  no host UI either - the same answer as iOS.
 *
 * The trigger is an engine-thread affair: EventSave/EventLoad touch
 * widgets, parser state and audio, so it travels as an SDL_USEREVENT
 * that the ViLE::RunEngine pump consumes (the same handoff the engine
 * already uses for SDL_QUIT).
 */
#ifndef _JAVABRIDGE_H_
#define _JAVABRIDGE_H_

#include "engine/evn.h"

// event.user.code values pushed by BridgeSendSaveLoadEvent().
// Mirrored as constants in SaveLoadDialog.java - keep in sync.
#define VILE_JAVA_EVENT_LOAD            1
#define VILE_JAVA_EVENT_SAVE            2

// The engine instance currently driven by ViLE::RunEngine(), parked in
// a global so a host UI can reach it. Written only on the engine thread
// (set at RunEngine entry, cleared at exit) and read after a null
// check: the pointer swap is atomic on every supported ABI and
// NativeID() itself is stateless.
extern EngineVN *g_running_engine;

/*! \brief Filename prefix of the running engine's savegames
 *  \return NativeID() of the loaded engine, or an empty string when no
 *          engine is running (the caller falls back to a plain "save"
 *          prefix for a foreign save folder)
 *
 *  Safe to call from any thread. Android's JNI shim uses it; the iOS
 *  host does not need it, because the engine writes its own saves
 *  there.
 */
uString BridgeSavePrefix();

/*! \brief Asks the engine to save or load a slot (thread-safe push)
 *  \param Save True to save, false to load
 *  \param Slot Savegame index (0-39, mirroring the 5x8 native pages)
 *
 *  The event sits in the SDL queue until the engine pump drains it, so
 *  a tap arriving during a shutdown window is harmless: RunEngine
 *  flushes stale events before the next game starts.
 */
void BridgeSendSaveLoadEvent(bool Save,int Slot);

/*! \brief Asks the host UI to open its slot dialog
 *  \param Save True for the save dialog, false for the load dialog
 *  \return True when the request was delivered to an external UI, false
 *          when there is none (iOS, desktop) - the caller then mounts
 *          its native StdSave/StdLoad widget.
 *
 *  Must run on the engine thread: the caller is EventGameDialog, with
 *  the engine parked in g_running_engine. Host implementations only
 *  post the request, so nothing here blocks.
 */
bool BridgeRequestSaveLoadDialog(bool Save);

#endif
