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


  // TODO can clean this up with to_variant(any)
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
// TODO need to support args. Might move to metaprogramming this
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
