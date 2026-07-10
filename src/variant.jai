// handwritten variant overloads


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

create_variant_from_obj :: (obj: *$T, variant: *Variant) {
  variant_from_object(cast(UninitializedVariantPtr)variant, cast(TypePtr)*obj.__private);
}
