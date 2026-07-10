#import "Compiler";
#import "String";


Register_Options :: struct {
  is_abstract: bool = false;
  is_runtime: bool = false;
  is_exposed: bool = true;
  is_virtual: bool = false;
}


register_class :: ($type: Type, options := Register_Options.{}) {

  // Has to be done in this order or boiler plate wont see our wrappers
  #insert #run insert_method_wrappers(type);
  #insert #run class_boilerplate(type);
  #insert #run generate_property_methods(type);
  #insert #run generate_register_methods(type);
  ti := cast(*Type_Info_Struct)type;
  name := new_string_name(ti.name);
  defer destroy(*name);
  member_name, base_name := #run find_base_name(type);
  parent_name := new_string_name(base_name);
  defer destroy(*parent_name);

  create_info := ClassCreationInfo6.{
    is_virtual = xx options.is_virtual,
    is_abstract = xx options.is_abstract,
    is_exposed = xx options.is_exposed,
    is_runtime = xx options.is_runtime,
    set_func = null,
    get_func = null,
    get_property_list_func = null,
    free_property_list_func = null,
    property_can_revert_func = null,
    property_get_revert_func = null,
    validate_property_func = null,
    notification_func = null,
    to_string_func = null,
    reference_func = null,
    unreference_func = null,
    create_instance_func = _create,
    free_instance_func = _free,
    recreate_instance_func = null,
    get_virtual_func = _get_virtual,
    get_virtual_call_data_func = null,
    call_virtual_with_data_func = null,
    class_userdata = null,
  };

  classdb_register_extension_class6(_library, *name, *parent_name, *create_info);
  #insert #run tprint("register_%_methods();\n", (cast(*Type_Info_Struct)type).name);
  register_properties(type);
}



find_base_name :: ($type: Type) -> name: string, type_name: string #compile_time {
  ti := cast(*Type_Info_Struct)type;
  for ti.members {
    if array_find(it.notes, "Base") {
      return it.name, (cast(*Type_Info_Struct)it.type).name;
    }
  }

  // TODO: Check there is only one
  assert(false, "The struct you want to register needs to have only one '#as' member");
  return "", "";
}

// Generates all base methods for a class
class_boilerplate :: ($type: Type) -> string #compile_time {
  b: String_Builder;
  ti : *Type_Info_Struct = xx type;
  type_name := ti.name;
  member_name, base_name := find_base_name(type);
  print_to_builder(*b, CREATE_FUNC, type_name, base_name, member_name);
  print_to_builder(*b, FREE_FUNC);
  print_to_builder(*b, "%", generate_get_virtual(ti.name));
  return builder_to_string(*b);
}


insert_method_wrappers :: ($type: Type) -> string {
  ti := cast(*Type_Info_Struct)type;
  builder: String_Builder;
  for ti.members {
    if it.type.type != .PROCEDURE then continue;
    proc : *Type_Info_Procedure = xx it.type;

    is_virtual := array_find(VIRTUALS, it.name);
    generate_ptr_wrapper_code(*builder, proc, it.name, ti.name, is_virtual);
    if is_virtual then continue;
    generate_call_wrapper_code(*builder, proc, it.name, ti.name);
  }
  return builder_to_string(*builder);
}



generate_get_virtual :: (class_name: string) -> string {
  b: String_Builder;
  print_to_builder(*b, "_get_virtual :: (p_class_userdata: *void, p_name: ConstStringNamePtr, p_hash: u32) -> ClassCallVirtual #c_call {\n");
  for VIRTUALS {
    print_to_builder(*b, "\t#if #exists(%1_%2_ptr_wrapper) if StringName_casecmp_to(p_name, new_string(\"%2\")) == 0 return %1_%2_ptr_wrapper;\n", class_name, it);
  }
  print_to_builder(*b, "\treturn null;\n};\n");
  return builder_to_string(*b);
}


/*
  Members that include a @export note must have get_/set_ functions. Either custom made by user or generated here
*/
generate_property_methods :: ($type : Type) -> string #compile_time {
  Prop :: struct { name: string; type: Type; };
  b: String_Builder;
  ti := cast(*Type_Info_Struct)type;
  props : [..]Prop;

  for member: ti.members {
    for member.notes {
    if it == "export" {
      array_add(*props, .{member.name, get_type(member.type) });
    }
    }
  }

  // second pass to see if gets and sets already exist
  set_prefix :: "set_";
  get_prefix :: "get_";

  for prop : props{
    has_set := false;
    has_get := false;

    for member: ti.members {
      if member.type.type != .PROCEDURE then continue;
      if member.name == join(set_prefix, prop.name) has_set = true;
      if member.name == join(get_prefix, prop.name) has_get = true;
    }

    if !has_set {
      print_to_builder(*b, "set_% :: (self: *%, p_%: %) {\n", prop.name, ti.name, prop.name, prop.type);
      print_to_builder(*b, "\tself.% = p_%;\n}\n", prop.name, prop.name);

      generate_accessor_call_wrapper(*b, ti.name, tprint("set_%", prop.name), prop.type, true);
      generate_accessor_ptr_wrapper (*b, ti.name, tprint("set_%", prop.name), prop.type, true);
    }

    if !has_get {
      print_to_builder(*b, "get_% :: (self: *%) -> % {\n", prop.name, ti.name, prop.type);
      print_to_builder(*b, "\treturn self.%;\n}\n", prop.name);

      generate_accessor_call_wrapper(*b, ti.name, tprint("get_%", prop.name), prop.type, false);
      generate_accessor_ptr_wrapper (*b, ti.name, tprint("get_%", prop.name), prop.type, false);
    }
  }
  code := builder_to_string(*b);
  return code;
}



generate_accessor_ptr_wrapper :: (b: *String_Builder, class_name: string, accessor_name: string, field_type: Type, is_setter: bool) #compile_time {
  print_to_builder(b, "%_%_ptr_wrapper :: (method_userdata: *void, p_instance: ClassInstancePtr, p_args: *ConstTypePtr, r_ret: TypePtr) -> void #c_call {\n", class_name, accessor_name);
  print_to_builder(b, "\tpush_context __context {\n");
  if is_setter {
    print_to_builder(b, "\t\t%(cast(*%) p_instance, (cast(*%) p_args[0]).*);\n", accessor_name, class_name, field_type);
  } else {
    print_to_builder(b, "\t\t(cast(*%) r_ret).* = %(cast(*%) p_instance);\n", field_type, accessor_name, class_name);
  }
  print_to_builder(b, "\t}\n}\n");
}

/*
  Used to generate wrapper calls only for procs that we generate. Can't use generate_call_wrapper_code for generated procs.
*/
generate_accessor_call_wrapper :: (b: *String_Builder, class_name: string, accessor_name: string, field_type: Type, is_setter: bool) #compile_time {
  print_to_builder(b, "%_%_call_wrapper :: (method_userdata: *void, p_instance: ClassInstancePtr, p_args: *ConstVariantPtr, p_argument_count: Int, r_return: VariantPtr, r_error: *CallError) -> void #c_call {\n", class_name, accessor_name);

  if is_setter {
    print_to_builder(b, "\t_args: []ConstVariantPtr = ---; _args.count = 1; _args.data = p_args;\n");
    print_to_builder(b, "\tpush_context __context {\n");
    print_to_builder(b, "\t\tv: %;\n", field_type);
    print_to_builder(b, "\t\tvariant_to(_args[0], *v);\n");
    print_to_builder(b, "\t\t%(cast(*%) p_instance, v);\n", accessor_name, class_name);
    print_to_builder(b, "\t}\n");
  } else {
    print_to_builder(b, "\tpush_context __context {\n");
    print_to_builder(b, "\t\tresult := %(cast(*%) p_instance);\n", accessor_name, class_name);
    print_to_builder(b, "\t\tvariant_from(r_return, *result);\n");
    print_to_builder(b, "\t}\n");
  }

  print_to_builder(b, "\tr_error.error = .OK;\n}\n");
}


generate_register_methods :: ($type: Type) -> string #compile_time {
  ti := cast(*Type_Info_Struct) type;
  b: String_Builder;

  print_to_builder(*b, "register_%_methods :: () {\n", ti.name);
  print_to_builder(*b, "    class_name := new_string_name(\"%\");\n", ti.name);
  print_to_builder(*b, "    defer destroy(*class_name);\n\n");

  for member: ti.members {
    is_export := false;
    for note: member.notes  if note == "export" { is_export = true; break; }
    if !is_export  continue;

    n := member.name;

    print_to_builder(*b, "    {\n");
    print_to_builder(*b, "        name := new_string_name(\"set_%\");  defer destroy(*name);\n", n);
    print_to_builder(*b, "        arg_name := new_string_name(\"p_%\"); defer destroy(*arg_name);\n", n);
    print_to_builder(*b, "        hint_str := new_string(\"\");        defer destroy(*hint_str);\n");
    print_to_builder(*b, "        arg: PropertyInfo;\n");
    print_to_builder(*b, "        arg_meta: ClassMethodArgumentMetadata = .NONE;\n");
    print_to_builder(*b, "        arg.type = .%;\n", jai_type_to_variant(member.type));
    print_to_builder(*b, "        arg.name = *arg_name;\n");
    print_to_builder(*b, "        arg.class_name = *class_name;\n");
    print_to_builder(*b, "        arg.hint_string = *hint_str;\n");
    print_to_builder(*b, "        arg.usage = 6;\n");
    print_to_builder(*b, "        info: ClassMethodInfo;\n");
    print_to_builder(*b, "        info.name = *name;\n");
    print_to_builder(*b, "        info.call_func    = %_set_%_call_wrapper;\n", ti.name, n);
    print_to_builder(*b, "        info.ptrcall_func = %_set_%_ptr_wrapper;\n",  ti.name, n);
    print_to_builder(*b, "        info.method_flags = 1;\n");
    print_to_builder(*b, "        info.has_return_value = xx false;\n");
    print_to_builder(*b, "        info.argument_count = 1;\n");
    print_to_builder(*b, "        info.arguments_info = *arg;\n");
    print_to_builder(*b, "        info.arguments_metadata = *arg_meta;\n");
    print_to_builder(*b, "        classdb_register_extension_class_method(_library, *class_name, *info);\n");
    print_to_builder(*b, "    }\n");

    print_to_builder(*b, "    {\n");
    print_to_builder(*b, "        name := new_string_name(\"get_%\"); defer destroy(*name);\n", n);
    print_to_builder(*b, "        hint_str := new_string(\"\");       defer destroy(*hint_str);\n");
    print_to_builder(*b, "        ret_name := new_string_name(\"\");       defer destroy(*ret_name);\n");
    print_to_builder(*b, "        ret: PropertyInfo;\n");
    print_to_builder(*b, "        ret.type = .%;\n", jai_type_to_variant(member.type));
    print_to_builder(*b, "        ret.name = *ret_name;\n");
    print_to_builder(*b, "        ret.class_name = *class_name;\n");
    print_to_builder(*b, "        ret.hint_string = *hint_str;\n");
    print_to_builder(*b, "        ret.usage = 6;\n");
    print_to_builder(*b, "        info: ClassMethodInfo;\n");
    print_to_builder(*b, "        info.name = *name;\n");
    print_to_builder(*b, "        info.call_func    = %_get_%_call_wrapper;\n", ti.name, n);
    print_to_builder(*b, "        info.ptrcall_func = %_get_%_ptr_wrapper;\n",  ti.name, n);
    print_to_builder(*b, "        info.method_flags = 1;\n");
    print_to_builder(*b, "        info.has_return_value = xx true;\n");
    print_to_builder(*b, "        info.return_value_info = *ret;\n");
    print_to_builder(*b, "        info.argument_count = 0;\n");
    print_to_builder(*b, "        classdb_register_extension_class_method(_library, *class_name, *info);\n");
    print_to_builder(*b, "    }\n");
  }

  print_to_builder(*b, "}\n");
  code := builder_to_string(*b);
  print("=== register_%_methods ===\n%\n", ti.name, code);
  return code;
}


register_properties :: ($type: Type) {
  ti := cast(*Type_Info_Struct)type;
  class_name := new_string_name(ti.name);
  defer destroy(*class_name);
  for member: ti.members {
    for member.notes {
      if it == {
        case "export";
          prop_info : PropertyInfo;
          prop_info.type = jai_type_to_variant(member.type);
          prop_name := new_string_name(member.name);
          defer destroy(*prop_name);
          prop_info.name = *prop_name;
          prop_info.class_name = *class_name;
          prop_info.hint = 0;

          hint_str := new_string("");
          prop_info.hint_string = *hint_str;
          defer destroy(*hint_str);
          prop_info.usage = 6;

          setter := new_string_name(tprint("set_%", member.name));
          defer destroy(*setter);
          getter := new_string_name(tprint("get_%", member.name));
          defer destroy(*getter);
          classdb_register_extension_class_property(_library, *class_name, *prop_info, *setter, *getter);
      case "signal";
        value_ptr := *ti.constant_storage[member.offset_into_constant_storage];
        proc_type := (cast(*Type) value_ptr).*;
        sig := cast(*Type_Info_Procedure) proc_type;
        arg_count := sig.argument_types.count;
        args: [..]PropertyInfo;
        arg_names: [..]StringName;
        hint_names: [..]String;

        array_resize(*args, arg_count);
        array_resize(*arg_names, arg_count);
        array_resize(*hint_names, arg_count);

        defer array_free(args);
        defer { for * arg_names destroy(it); array_free(arg_names); }
        defer { for * hint_names destroy(it); array_free(hint_names); }

        for sig.argument_types {
          print("argument_types");
          print("  arg % type-tag %\n", it_index, it.type);
          arg_names[it_index] = new_string_name("");
          hint_names[it_index] = new_string("");
          args[it_index].type = jai_type_to_variant(it);
          args[it_index].name = *arg_names[it_index];
          args[it_index].class_name = *class_name;
          args[it_index].hint = 0;
          args[it_index].hint_string = *hint_names[it_index];
        }

        signal_name := new_string_name(member.name);
        defer destroy(*signal_name);
        data := ifx arg_count > 0 then args.data else null;
        print("  signal about to register, arg_count %\n", arg_count);
        classdb_register_extension_class_signal(_library, *class_name, *signal_name, data, arg_count);
      }
    }
  }
}



construct :: ($T: Type) -> *T {
  class_sn := new_string_name((cast(*Type_Info_Struct) T).name);
  defer destroy(*class_sn);
  obj := classdb_construct_object(*class_sn);
  return cast(*T) object_get_instance_binding(obj, _library, *binding_callbacks);
}





