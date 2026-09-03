class CustomBindingGeneratorHooks:
    """Project-local fixes for generated godot-cpp bindings."""

    def alter_engine_class_header(self, class_api, lines):
        return lines

    def alter_engine_class_source(self, class_api, lines):
        return lines

    def alter_global_constants(self, api, lines):
        return lines

    def alter_utility_functions_header(self, api, lines):
        return lines

    def alter_utility_functions_source(self, api, lines):
        return lines

    def alter_builtin_class_header(self, builtin_api, lines):
        return lines

    def alter_builtin_class_source(self, builtin_api, lines):
        if builtin_api.get("name") != "Dictionary":
            return lines

        signature = "Dictionary &Dictionary::operator=(Dictionary &&p_other) {"
        try:
            signature_index = lines.index(signature)
        except ValueError:
            return lines

        constructor_index = -1
        for index in range(signature_index + 1, min(signature_index + 8, len(lines))):
            if "_call_builtin_constructor" in lines[index]:
                constructor_index = index
                break
        if constructor_index < 0:
            return lines
        if any(
            "_method_bindings.destructor(&opaque);" in lines[index]
            for index in range(signature_index + 1, constructor_index)
        ):
            return lines

        lines.insert(constructor_index, "\t_method_bindings.destructor(&opaque);")
        return lines
