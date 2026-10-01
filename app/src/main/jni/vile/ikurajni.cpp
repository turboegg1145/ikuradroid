/*
 * IkuraDroid - host entry points for the native save/load UI.
 *
 * The platform UI parses the savegame files directly from disk (no
 * native calls in the read path, see SaveLoadDialog.java and
 * ios/ikuradroid/IkuraSaveSlots.mm). What it cannot do on its own is
 * ask the engine which filename prefix the current game's saves use
 * (NativeID, e.g. "Crescendo", "Critical") and perform the actual
 * save/load: EventSave/EventLoad must run on the engine thread.
 *
 * Both needs are served by javabridge.cpp (BridgeSavePrefix /
 * BridgeSendSaveLoadEvent). This file only carries the thin per
 * platform wrappers:
 *
 *   - Android: the JNI methods SDLActivity declares and calls.
 *   - iOS:     plain C functions, declared in ios/ikuradroid/
 *              IkuraEngine.h and called from Objective-C++.
 */

#include "javabridge.h"

#ifdef __ANDROID__

#include <jni.h>
#include <stdint.h>

/*! \brief Filename prefix of the running engine's savegames
 *  \return NativeID of the loaded engine, or an empty string when no
 *          engine is running (the caller falls back to the old
 *          F5/F6 hotkey path)
 */
extern "C" JNIEXPORT jstring JNICALL
Java_org_libsdl_app_SDLActivity_nativeGetSavePrefix(JNIEnv *env, jclass)
{
        return env->NewStringUTF(BridgeSavePrefix().c_str());
}

/*! \brief Asks the engine to save or load a slot (thread-safe push)
 *  \param Mode VILE_JAVA_EVENT_LOAD or VILE_JAVA_EVENT_SAVE
 *  \param Slot Savegame index (0-39, mirroring the 5x8 native pages)
 */
extern "C" JNIEXPORT void JNICALL
Java_org_libsdl_app_SDLActivity_nativeSendSaveLoadEvent(JNIEnv *, jclass,
                                                       jint Mode, jint Slot)
{
        BridgeSendSaveLoadEvent(Mode == VILE_JAVA_EVENT_SAVE, (int)Slot);
}

#endif /* __ANDROID__ */
