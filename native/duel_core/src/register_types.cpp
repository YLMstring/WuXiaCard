#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "duel_native_compact_kernel.h"

using namespace godot;

// GDExtension 只注册一个纯数据内核类。Godot 场景通过该类提交紧凑状态并取得
// 转换事件；规则逻辑不会注册成 Node，也不依赖场景生命周期。
void initialize_duel_native_module(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DuelNativeCompactKernel);
}

void uninitialize_duel_native_module(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT duel_native_library_init(
	GDExtensionInterfaceGetProcAddress get_proc_address,
	GDExtensionClassLibraryPtr library,
	GDExtensionInitialization *initialization
) {
	GDExtensionBinding::InitObject init_object(
		get_proc_address,
		library,
		initialization
	);
	init_object.register_initializer(initialize_duel_native_module);
	init_object.register_terminator(uninitialize_duel_native_module);
	init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
}
