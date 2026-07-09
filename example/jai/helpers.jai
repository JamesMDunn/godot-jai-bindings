// --------
// Class registration
#import "String";


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


construct :: ($type: Type) -> *type {
  class_sn := new_string_name((cast(*Type_Info_Struct) type).name);
  defer destroy(*class_sn);
  obj := classdb_construct_object(*class_sn);
  return cast(*type) object_get_instance_binding(obj, _library, *dummy_callbacks);
}

CREATE_FUNC :: #string __END
_create :: (data: *void, p_notify_postinitialize: Bool) -> *void #c_call {
  result : *%1 = xx mem_alloc(size_of(%1));
  base_name := new_string_name("%2");
  defer destroy(*base_name);
  result.%3.__private = classdb_construct_object(*base_name);
  name := new_string_name("%1");
  defer destroy(*name);
  object_set_instance(result.%3.__private, *name, result);
  object_set_instance_binding(result.%3.__private, _library, result, *dummy_callbacks);
  return result.%3.__private;
};
__END

FREE_FUNC :: #string __END
_free :: (data: *void, self: *void) #c_call {
  mem_free(self);
};
__END


VIRTUALS :: string.["_process", "_enter_tree", "_ready", "_physics_process", "_unhandled_input", "_input"];

generate_get_virtual :: (class_name: string) -> string {
  b: String_Builder;
  print_to_builder(*b, "_get_virtual :: (p_class_userdata: *void, p_name: ConstStringNamePtr, p_hash: u32) -> ClassCallVirtual #c_call {\n");
  for VIRTUALS {
    print_to_builder(*b, "\t#if #exists(%1_%2_ptr_wrapper) if StringName_casecmp_to(p_name, new_string(\"%2\")) == 0 return %1_%2_ptr_wrapper;\n", class_name, it);
  }
  print_to_builder(*b, "\treturn null;\n};\n");
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

register_class :: ($type: Type) {

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
    is_virtual = xx false,
    is_abstract = xx false,
    is_exposed = xx true,
    is_runtime = xx true,
    set_func = null,
    get_func = null,
    get_property_list_func = null,
    free_property_list_func = null,
    property_can_revert_func = null,
    property_get_revert_func = null,
    validate_property_func = null,
    notification_func = null,
    to_string_func = null, // GDExample_to_string,
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

// register_methods:: ($type: Type) {
//   ti := cast(*Type_Info_Struct)type;
//   class_name := new_string_name(ti.name);
//   defer destroy(*class_name);
//
//   for member: ti.members {
//     for member.notes {
//       if it == "export" {
//         prop_name := new_string_name(member.name);
//         set_method_info : ClassMethodInfo;
//         setter := new_string_name(tprint("set_%", member.name));
//         defer destroy(*setter);
//
//         set_arg_info: PropertyInfo;
//         //TODO hardcoded variant type
//         set_arg_info.type = .FLOAT;
//         arg_name := new_string_name(tprint("p_%", member.name));
//         defer destroy(*arg_name);
//         set_arg_info.name = *arg_name;
//         set_arg_info.class_name = *class_name;
//         set_arg_info.hint = 6;
//         set_hint_str := new_string("");
//         set_arg_info.hint_string = *set_hint_str;
//         set_arg_info.usage = 6;
//         defer destroy(*set_hint_str);
//
//
//         set_info: ClassMethodInfo;;
//         set_info.name = *setter;
//         set_info.call_func = #insert -> string { return tprint("%_set_%_call_wrapper", ti.name, prop_name); } ;
//         set_info.ptrcall_func = tprint("%_set_%_ptr_wrapper", class_name, prop_name);
//
//
//         get_method_info : ClassMethodInfo;
//         defer destroy(*prop_name);
//
//         getter := new_string_name(tprint("get_%", member.name));
//         defer destroy(*getter);
//
//       }
//     }
//   }
// }

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
    print_to_builder(*b, "        arg.type = .FLOAT;\n");                 // TODO: per-type
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
    print_to_builder(*b, "        ret.type = .FLOAT;\n");
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
          prop_info.type = .FLOAT;
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
        sig := cast(*Type_Info_Procedure) member.type;
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
          arg_names[it_index] = new_string_name("");
          hint_names[it_index] = new_string("");
          args[it_index].type = .INT;
          args[it_index].name = *arg_names[it_index];
          args[it_index].class_name = *class_name;
          args[it_index].hint = 0;
          args[it_index].hint_string = *hint_names[it_index];
        }

        signal_name := new_string_name(member.name);
        defer destroy(*signal_name);
        data := ifx arg_count > 0 then args.data else null;
        classdb_register_extension_class_signal(_library, *class_name, *signal_name, data, arg_count);
      }
    }
  }
}

dummy_callbacks :: InstanceBindingCallbacks.{
  create_callback = (p_token: *void, p_instance: *void) -> *void #c_call {
    return null;
  },
  free_callback = (p_token: *void, p_instance: *void, p_binding: *void) #c_call {

  },
  reference_callback = (p_token: *void, p_binding: *void, p_reference: Bool) -> Bool #c_call {
    return xx true;
  },
};

#import "Compiler";
generate_wrapper :: (call := #caller_code) -> string #expand {
  code := compiler_get_nodes(call);
  assert(code.kind == .IDENT, "Please pass a function name to the macro.");
  ti := code.type;
  assert(ti.type == .PROCEDURE, "Please pass a function name to the macro.");
  code_ident: *Code_Ident = xx code;

  return generate_ptr_wrapper_code(xx ti, code_ident.name);
}

generate_ptr_wrapper_code :: (builder : *String_Builder, proc: *Type_Info_Procedure, proc_name: string, class_name: string, is_virtual: bool) #compile_time {
  if proc.return_types.count > 1 {
    assert(false, "Multiple return values aren't supported!");
  }

  is_const := false; // @TODO
  arg_count := ifx is_const then proc.argument_types.count else proc.argument_types.count - 1;

  sig := ifx is_virtual
    then "%_%_ptr_wrapper :: (p_instance: ClassInstancePtr, p_args: *ConstTypePtr, r_ret: TypePtr) -> void #c_call {\n"
    else "%_%_ptr_wrapper :: (method_userdata: *void, p_instance: ClassInstancePtr, p_args: *ConstTypePtr, r_ret: TypePtr) -> void #c_call {\n";
  print_to_builder(builder, sig, class_name, proc_name);
  if arg_count > 0 {
    print_to_builder(builder, "\targs : []*void = ---;\n");
    print_to_builder(builder, "\targs.count = %;\n", arg_count);
    print_to_builder(builder, "\targs.data = p_args;\n");
  }
  print_to_builder(builder, "\tpush_context __context {\n");
  append(builder, "\t\t");
  if proc.return_types.count == 1 {
    print_to_builder(builder,"r_ret = ");
  }
  print_to_builder(builder, "%.%(p_instance", class_name, proc_name); // (cast(*float)args[0]).*);"
  if arg_count > 0 {
    start := 1;
    for start..proc.argument_types.count - 1 {
      append(builder, ", (cast(*");
      print_type_to_builder(builder, proc.argument_types[it]);
      append(builder, ")");
      print_to_builder(builder, "args[%]).*", it - 1);
    }
  }
  print_to_builder(builder, ");\n");
  print_to_builder(builder, "\t}\n");

  if proc.return_types.count == 0 {
    print_to_builder(builder, "\tr_ret = null;\n");
  }

  print_to_builder(builder, "}\n");
}

generate_call_wrapper_code :: (builder : *String_Builder, proc: *Type_Info_Procedure, proc_name: string, class_name: string) #compile_time {
  if proc.return_types.count > 1 {
    assert(false, "Multiple return values aren't supported!");
  }

  arg_count := proc.argument_types.count - 1;

  print_to_builder(builder, "%_%_call_wrapper :: (method_userdata: *void, p_instance: ClassInstancePtr, p_args: *ConstTypePtr, p_argument_count: Int, r_ret: VariantPtr, r_error: *CallError) -> void #c_call {\n", class_name, proc_name);

  print_to_builder(builder, "\tif p_argument_count != % {\n", arg_count);
  print_to_builder(builder, "\t\tr_error.error = .ERROR_TOO_FEW_ARGUMENTS; \n");
  print_to_builder(builder, "\t\tr_error.expected = %;\n", arg_count);
  print_to_builder(builder, "\t\treturn;\n\t}\n");

  if arg_count > 0 {
    print_to_builder(builder, "\t_args: []ConstVariantPtr = ---;\n");
    print_to_builder(builder, "\t_args.count = %;\n", arg_count);
    print_to_builder(builder, "\t_args.data  = p_args;\n");
  }


  print_to_builder(builder, "\tpush_context __context {\n");

  // decode variant arg into a typed local

  for arg_i: 0..arg_count - 1 {
    print_to_builder(builder, "\t\targ%: ", arg_i);
    print_type_to_builder(builder, proc.argument_types[arg_i + 1]);
    print_to_builder(builder, ";\n");
    print_to_builder(builder, "\t\tvariant_to(_args[%], *arg%);\n", arg_i, arg_i);
  }

  append(builder, "\t\t");
  if proc.return_types.count == 1 {
    append(builder, "result := ");
  }
  print_to_builder(builder, "%.%(cast(*%) p_instance", class_name, proc_name, class_name);
  for arg_i: 0..arg_count-1 {
    print_to_builder(builder, ", arg%", arg_i);
  }
  print_to_builder(builder, ");\n");

  if proc.return_types.count == 1 {
    print_to_builder(builder, "\t\tvariant_from(r_return, *result);\n");
  }

  print_to_builder(builder, "\t}\n");
  print_to_builder(builder, "\tr_error.error = .OK;\n");
  print_to_builder(builder, "}\n");

}

as :: ($T: Type, node: *Node) -> *T {
  return cast(*T) object_get_instance_binding(node.__private, _library, *dummy_callbacks);
}

call :: (obj: *$T, method: string, args: ..Any) -> Variant {
  private_ptr := obj.__private;
  variant_args: [..]Variant;
  variant_ptrs: [..]*Variant;
  gd_string_buffer: [..]String;
  defer { for * gd_string_buffer destroy(it); array_free(gd_string_buffer); }

  method_str := new_string_name(method);

  defer destroy(*method_str);

  obj_variant: Variant;
  variant_from_object(cast(UninitializedVariantPtr)*obj_variant, cast(TypePtr)*private_ptr);

  r_variant: Variant;
  r_error: CallError;

  array_resize(*variant_args, args.count);
  array_resize(*variant_ptrs, args.count);

  defer array_free(variant_args);
  defer array_free(variant_ptrs);


  for arg: args {
    if arg.type.type == {
		  case .FLOAT;
		    variant_from(*variant_args[it_index], cast(*float64)arg.value_pointer);
		    variant_ptrs[it_index] = *variant_args[it_index];
      case .INTEGER;
        variant_from(*variant_args[it_index], cast(*s64)arg.value_pointer);
        variant_ptrs[it_index] = *variant_args[it_index];
      case .BOOL;
        variant_from(*variant_args[it_index], cast(*bool)arg.value_pointer);
        variant_ptrs[it_index] = *variant_args[it_index];
      case .STRING;
        jai_str := (cast(*string)arg.value_pointer).*;
        array_add(*gd_string_buffer, new_string(jai_str));
        gd := *gd_string_buffer[gd_string_buffer.count - 1];
        variant_from(*variant_args[it_index], gd);
        variant_ptrs[it_index] = *variant_args[it_index];
      case .STRUCT;
        if arg.type == type_info(StringName) {
          variant_from(*variant_args[it_index], cast(*StringName)arg.value_pointer);
          variant_ptrs[it_index] = *variant_args[it_index];
        }
    }
  }

  call_internal(*obj_variant, *method_str, cast(*ConstVariantPtr)variant_ptrs.data, variant_args.count, *r_variant, *r_error);
  return r_variant;
}

call_internal :: (obj: VariantPtr, p_method: ConstStringNamePtr, p_args: *ConstVariantPtr, p_argument_count: Int, r_return: UninitializedVariantPtr, r_error: *CallError) {
  variant_call(obj, p_method, p_args, p_argument_count, r_return, r_error);
}



emit :: (obj: *$T, signal: string, args: ..Any) {
  all : [..]Any;
  signal_str := new_string_name(signal);
  defer destroy(*signal_str);
  defer array_free(all);
  array_add(*all, signal_str);
  for args array_add(*all, it);
  call(obj, "emit_signal", ..all);
  // private_ptr := obj.__private;
  // name := new_string_name(signal);
  // defer destroy(*name);

  // variant_args : [..Variant];
  // variant_ptrs: [..]*Variant;

  // r_error: CallError;

  // array_resize(*variant_args, args.count);
  // array_resize(*variant_ptrs, args.count);

  // defer array_free(variant_args);
  // defer array_free(variant_ptrs);

  // for arg: args {
  //   if arg.type.type == {
  //     case .FLOAT;   variant_from(*variant_args[it_index], cast(*float64) arg.value_pointer);
  //     case .INTEGER; variant_from(*variant_args[it_index], cast(*s64) arg.value_pointer);
  //     case .BOOL;    variant_from(*variant_args[it_index], cast(*bool) arg.value_pointer);
  //   }
  //   variant_ptrs[it_index] = *variant_args[it_index];
  // }

  // Object_emit_signal(private_ptr,
}




// handwritten variant overloads

variant_to :: (src: ConstVariantPtr, dst: *String) {
  variant_to_string(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *String) {
  variant_from_string(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}

// StringName
variant_to :: (src: ConstVariantPtr, dst: *StringName) {
  variant_to_string_name(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *StringName) {
  variant_from_string_name(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}

// floats
variant_to :: (src: ConstVariantPtr, dst: *float64) {
  variant_to_float(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *float64) {
  variant_from_float(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}

// ints
variant_to :: (src: ConstVariantPtr, dst: *s64) {
  variant_to_int(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *s64) {
  variant_from_int(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}


// bool
variant_to :: (src: ConstVariantPtr, dst: *bool) {
  variant_to_float(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *bool) {
  variant_from_float(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}



