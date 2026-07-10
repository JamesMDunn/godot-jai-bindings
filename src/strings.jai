
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
