// adv80s_mp4：GDExtension の入り口（段階70）。
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "adv_mf_writer.h"

using namespace godot;

static void initialize_adv80s_mp4(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AdvMfWriter);
}

static void uninitialize_adv80s_mp4(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT adv80s_mp4_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_adv80s_mp4);
	init_obj.register_terminator(uninitialize_adv80s_mp4);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
