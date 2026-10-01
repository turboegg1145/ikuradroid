/*
 * IkuraDroid - host UI <-> engine bridge.
 *
 * The save/load slot menu lives in the platform UI (a Java activity on
 * Android, a UIKit view controller on iOS) and drives the engine
 * through two entry points only: it asks for the savegame filename
 * prefix of the running engine, and it pushes an SDL_USEREVENT when the
 * user picked a slot. Both are implemented here, so the callers (the
 * JNI shim in ikurajni.cpp and the iOS host in ios/ikuradroid/
 * IkuraEngine.mm) stay trivial.
 */

#include "javabridge.h"

#include <SDL.h>
#include <stdint.h>

/* Parked by ViLE::RunEngine(), see javabridge.h. */
EngineVN *g_running_engine=0;

uString BridgeSavePrefix(){
	if(g_running_engine){
		return g_running_engine->NativeID();
	}
	return uString("");
}

void BridgeSendSaveLoadEvent(bool Save,int Slot){
	SDL_Event event;
	SDL_zero(event);
	event.type=SDL_USEREVENT;
	event.user.code=Save?VILE_JAVA_EVENT_SAVE:VILE_JAVA_EVENT_LOAD;
	event.user.data1=(void *)(intptr_t)Slot;
	SDL_PushEvent(&event);
}

#if defined(__ANDROID__)

#include <jni.h>
#include <SDL_system.h>

bool BridgeRequestSaveLoadDialog(bool Save){
	bool retval=false;
	JNIEnv *env=(JNIEnv*)SDL_AndroidGetJNIEnv();
	if(env){
		jclass cls=env->FindClass("org/libsdl/app/SDLActivity");
		if(cls){
			jmethodID mid=env->GetStaticMethodID(cls,
							"openSaveLoadFromEngine","(Z)V");
			if(mid){
				env->CallStaticVoidMethod(cls,mid,
								Save?JNI_TRUE:JNI_FALSE);
				retval=true;
			}
			env->DeleteLocalRef(cls);
		}
		if(env->ExceptionCheck()){
			// A broken bridge must never wedge the engine:
			// log the pending exception and drop it
			env->ExceptionDescribe();
			env->ExceptionClear();
			retval=false;
		}
	}
	return retval;
}

#elif defined(VILE_IOS)

/* iOS keeps the engine's own StdSave/StdLoad dialogs.
 *
 * Android replaced them because a touch keyboard-less phone has no
 * F5/F6 to reach them; iOS has no such problem - the app puts Save and
 * Load buttons in its overlay and they push the same F6/F5 keys
 * (see IkuraEngine.mm). Keeping the native dialog means the save slots
 * are the engine's own, so they are written by the very code that
 * knows the game state, and the app does not have to mirror the
 * savegame container format.
 *
 * Returning false is the contract for "no external UI": the caller in
 * EngineVN::EventGameDialog() mounts StdSave/StdLoad instead. */
bool BridgeRequestSaveLoadDialog(bool Save){
	(void)Save;
	return false;
}

#else

bool BridgeRequestSaveLoadDialog(bool Save){
	// Host builds have no external UI - the caller keeps its native
	// StdSave/StdLoad dialog.
	(void)Save;
	return false;
}

#endif
