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

// lookup cast meant for jai instances
get_instance :: ($T: Type, node: *Object) -> *T {
  return cast(*T) object_get_instance_binding(node.__private, _library, *binding_callbacks);
}


get_node :: (self: *$T, path: string) -> Node {
  np := make_node_path(path);
  defer destroy(*np);
  return Node_get_node(self, np);
}

// get a Godot node as a Godot R
get_node_as :: ($R: Type, self: *$T, path: string) -> R {
  node := get_node(self, path);
  result: R;
  result.__private = node.__private;
  return result;
}

get_singleton :: ($T: Type, name: string) -> T {
    name_sn := new_string_name(name);
    defer destroy(*name_sn);
    obj_ptr := global_get_singleton(cast(ConstStringNamePtr) *name_sn);
    result: T;
    result.__private = obj_ptr;
    return result;
}


unref :: (obj: *$T) -> bool {
  freed := RefCounted_unreference(obj);
  return freed;
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


is_valid :: (handle: $T) -> bool {
    return handle.__private != null;
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
