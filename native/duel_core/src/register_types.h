#pragma once

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// GDExtension 的最小注册入口；具体规则接口集中在 DuelNativeCompactKernel。
void initialize_duel_native_module(ModuleInitializationLevel level);
void uninitialize_duel_native_module(ModuleInitializationLevel level);
