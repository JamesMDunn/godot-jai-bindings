#import "Basic";
// This file contains code written by hand to facilitate API usage

_library: ClassLibraryPtr;
__context : #Context;

register_library :: (lib: ClassLibraryPtr) {
    _library = lib;
}

// --------
// fn ptr loading

load_all_procedures :: (p_get_proc_address: InterfaceGetProcAddress) {
    load_interface_functions(p_get_proc_address);
    load_all_methods();
    load_all_utility_functions();
}

load_all_methods :: () {
    load_all_destructors();
    load_variant_constructors();
}

load_single_utility_func :: (name: string, hash: int) -> PtrUtilityFunction {
    str_name: StringName;
    string_name_new_with_utf8_chars_and_len(*str_name, name.data, name.count);
    defer string_name_destroy(*str_name);

    return variant_get_ptr_utility_function(*str_name, hash);
}

// --------
// Conversion
Basic :: #import "Basic";


new_string_name :: (str: string) -> StringName #no_context {
    result: StringName;
    string_name_new_with_utf8_chars_and_len(*result, str.data, str.count);
    return result;
}

new_string :: (str: string) -> String #no_context {
    result : String = ---;
    string_new_with_utf8_chars_and_len(*result, str.data, str.count);
    return result;
}

jai_string_from_gd :: (str: String) -> string {
  data: [..]u8;
  defer array_free(data);
  // first pass to get size of the String
  data_len := string_to_utf8_chars(*str, null, 0);

  array_resize(*data, data_len);
  string_to_utf8_chars(*str, data.data, data_len);
  view := to_string(data.data, data.count);
  return copy_string(view);
}


// --------
// Utils

print_to_godot :: (str: string) #c_call {
    push_context __context {
        s : String;
        string_new_with_utf8_chars(*s, str.data);
        defer destroy(*s);
        arg: Variant;
        variant_from_string(xx *arg, xx *s);
        defer variant_destroy(*arg);
        args := ConstVariantPtr.[ *arg ];
        gd_print(null, args.data, args.count);
    }
}


unref :: (obj: *$T) -> bool {
  freed := RefCounted_unreference(obj);
  return freed;
}


// Any
to_variant :: (value: Any) -> Variant {
  result: Variant;
  ti := value.type;

  if ti.type == {
    case .INTEGER;
      v := (cast(*s64) value.value_pointer).*;
      variant_from_int(xx *result, xx *v);
    case .FLOAT;
      info := cast(*Type_Info_Float) ti;
      v: float64;
      if info.runtime_size == 4  v = (cast(*float32) value.value_pointer).*;
      else  v = (cast(*float64) value.value_pointer).*;
      variant_from_float(xx *result, xx *v);
    case .BOOL;
      v := (cast(*bool) value.value_pointer).*;
      variant_from_float(xx *result, xx *v);
    case .STRING;
      s := (cast(*string) value.value_pointer).*;
      gs := new_string(s);
      defer destroy(*gs);
      variant_from_string(xx *result, xx *gs);
    case .STRUCT;
      info := cast(*Type_Info_Struct) ti;
      v := value.value_pointer;
      has_private := false;
      for info.members {
          if it.name == "__private" {
              has_private = true;
              break;
          }
      }
      if has_private {
          handle := cast(*Object) v;
          variant_from_object(xx *result, xx *handle.__private);
      } else {
        assert(false, "to_variant: builtin struct % not handled yet", info.name);
      }
    case .POINTER;
        info := cast(*Type_Info_Pointer) ti;
        pointee := info.pointer_to;

        obj_ptr := (cast(**void) value.value_pointer).*;

        handle := cast(*Object)obj_ptr;
        variant_from_object(xx *result, xx *handle.__private);
    case;
      assert(false, "to_variant: unhandled type %", ti.type);
  }
  return result;
}



jai_type_to_variant :: (ti: *Type_Info) -> VariantType {
  if ti.type == {
    case .FLOAT; return .FLOAT;
    case .INTEGER; return .INT;
    case .BOOL; return .BOOL;
    case .STRING; return .STRING;
    case .STRUCT;
      if ti == type_info(StringName)  return .STRING_NAME;
      if ti == type_info(Vector2) return .VECTOR2;
      if ti == type_info(Vector3) return .VECTOR3;
  }
  return .NIL;
}


is_valid :: (handle: $T) -> bool {
    return handle.__private != null;
}

make_node_path :: (path: string) -> NodePath {
  gstr := new_string(path);
  defer destroy(*gstr);
  result : NodePath;
  con := variant_get_ptr_constructor(.NODE_PATH, 2);
  args := *void.[*gstr];
  con(cast(*void) *result, args.data);
  return result;
}

ensure_in_tree :: (self: *$T) {
  if !Node_is_inside_tree(self) {
    engine := get_singleton(Engine, "Engine");
    main_loop := Engine_get_main_loop(*engine);
    tree: SceneTree;
    tree.__private = main_loop.__private;
    if is_valid(tree) {
      root := SceneTree_get_root(*tree);
      Object_call_deferred(*root, "add_child", self);
    }
  }
}


get_node :: (self: *$T, path: string) -> Node {
  np := make_node_path(path);
  defer destroy(*np);
  return Node_get_node(self, np);
}

get_node_as :: ($R: Type, self: *$T, path: string) -> R {
  node := get_node(self, path);
  result: R;
  result.__private = node.__private;
  return result;
}

// lookup cast for jai instances
as :: ($T: Type, node: *Object) -> *T {
  return cast(*T) object_get_instance_binding(node.__private, _library, *binding_callbacks);
}

// downcast meant for godot objects
cast_to :: ($R: Type, obj: *$T) -> R {
    result: R;
    result.__private = obj.__private;
    return result;
}

cast_checked :: ($R: Type, obj: *$T) -> R {
    result: R;
    class_name := (cast(*Type_Info_Struct) R).name;
    if Object_is_class(obj, class_name) {
        result.__private = obj.__private;
    }
    return result;
}

get_prop :: ($T: Type, obj: *Object, property: string) -> T {
    // returns a variant
    v := Object_get(obj, property);
    result: T;
    // unwrap variant
    variant_to(cast(ConstVariantPtr)*v, *result);
    return result;
}

set_prop :: (obj: *Object, property: string, value: $T) {
    v: Variant;
    variant_from(*v, *value);
    Object_set(obj, property, v);
}

call :: (obj: *$T, method: string, args: ..Any) -> Variant {
  variant_args: [..]Variant;
  variant_ptrs: [..]*Variant;
  gd_string_buffer: [..]String;
  defer { for * gd_string_buffer destroy(it); array_free(gd_string_buffer); }

  method_str := new_string_name(method);

  defer destroy(*method_str);

  obj_variant: Variant;
  create_variant_from_obj(obj, *obj_variant);
  defer variant_destroy(cast(VariantPtr) *obj_variant);

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

create_variant_from_obj :: (obj: *$T, variant: *Variant) {
  variant_from_object(cast(UninitializedVariantPtr)variant, cast(TypePtr)*obj.__private);
}


// binding required wip
callable :: (obj: *$T, method: string) -> Callable {
  obj_variant: Variant;
  create_variant_from_obj(obj, *obj_variant);
  defer variant_destroy(cast(VariantPtr) *obj_variant);
  return Callable_create(obj_variant, method);
}

CallableUserdata :: struct {
    obj:  *void;
    proc: *void;
}

custom_call :: (ud: *void, p_args: *ConstVariantPtr, p_argument_count: Int, r_return: VariantPtr, r_error: *CallError) #c_call {
    push_context __context {
      print_to_godot("custom_call fired");
      data := cast(*CallableUserdata) ud;
      handler := cast(#type (self: *void)) data.proc;
      handler(data.obj);
    }
    r_error.error = .OK;
}

custom_free :: (ud: *void) #c_call {
    push_context __context {
      free(cast(*CallableUserdata) ud);
    }
}

// no binding req. Can use freely
callable_mp :: (obj: *$T, handler: (self: *T)) -> Callable {
    ud := New(CallableUserdata);
    ud.obj  = obj;
    ud.proc = cast(*void) handler;

    info: CallableCustomInfo2;
    info.callable_userdata = ud;
    info.call_func = custom_call;
    info.free_func = custom_free;

    result: Callable;
    callable_custom_create2(cast(UninitializedTypePtr) *result, *info);
    return result;
}



emit :: (obj: *$T, signal: string, args: ..Any) {
  all : [..]Any;
  signal_str := new_string_name(signal);
  defer destroy(*signal_str);
  defer array_free(all);
  array_add(*all, signal_str);
  for args array_add(*all, it);
  call(obj, "emit_signal", ..all);
}


get_singleton :: ($T: Type, name: string) -> T {
    name_sn := new_string_name(name);
    defer destroy(*name_sn);
    obj_ptr := global_get_singleton(cast(ConstStringNamePtr) *name_sn);
    result: T;
    result.__private = obj_ptr;
    return result;
}

// handwritten variant overloads

variant_to :: (src: ConstVariantPtr, dst: *string) {
  gd: String;
  variant_to_string(cast(TypePtr) *gd, cast(VariantPtr) src);
  defer destroy(*gd);
  free (dst.*);
  dst.* = jai_string_from_gd(gd);
}

variant_from :: (dst: VariantPtr, src: *string) {
  new_str := ifx src.data && src.count > 0 then new_string(src.*) else new_string("");
  defer destroy(*new_str);
  variant_from_string(cast(UninitializedVariantPtr) dst, cast(TypePtr)*new_str);
}


//String
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
  variant_to_bool(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *bool) {
  variant_from_bool(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}


// Vector2
variant_to :: (src: ConstVariantPtr, dst: *Vector2) {
    variant_to_vector2(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *Vector2) {
    variant_from_vector2(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
}

// Vector3
variant_to :: (src: ConstVariantPtr, dst: *Vector3) {
    variant_to_vector3(cast(TypePtr) dst, cast(VariantPtr) src);
}
variant_from :: (dst: VariantPtr, src: *Vector3) {
    variant_from_vector3(cast(UninitializedVariantPtr) dst, cast(TypePtr) src);
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
  object_set_instance_binding(result.%3.__private, _library, result, *binding_callbacks);
  return result.%3.__private;
};
__END

FREE_FUNC :: #string __END
_free :: (data: *void, self: *void) #c_call {
  mem_free(self);
};
__END


VIRTUALS :: string.["_process", "_enter_tree", "_ready", "_physics_process", "_unhandled_input", "_input"];




binding_callbacks :: InstanceBindingCallbacks.{
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
    append(builder, "(cast(*");
    print_type_to_builder(builder, proc.return_types[0]);
    append(builder, ") r_ret).* = ");
  }
  print_to_builder(builder, "%.%(cast(*%) p_instance", class_name, proc_name, class_name);
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

  print_to_builder(builder, "%_%_call_wrapper :: (method_userdata: *void, p_instance: ClassInstancePtr, p_args: *ConstTypePtr, p_argument_count: Int, r_return: VariantPtr, r_error: *CallError) -> void #c_call {\n", class_name, proc_name);

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





