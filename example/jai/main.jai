#import "Basic";

#import "godot-jai-bindings";
#import "Math";
#load "helpers.jai";


// Initialization code (could be automated)

#program_export
jai_entry :: (p_get_proc_address: InterfaceGetProcAddress, p_library: ClassLibraryPtr, r_initialization: *Initialization) -> Bool #c_call {
    r_initialization.userdata = *__context;
    r_initialization.initialize = initialize;
    r_initialization.deinitialize = deinitialize;
    push_context __context {
        register_library(p_library);
        load_all_procedures(p_get_proc_address);
    }
    return 1;
}

initialize :: (data: *void, level: InitializationLevel) #c_call {
    push_context cast(*#Context)data {
        if level != .INITIALIZATION_SCENE return;
        register_class(Player);
        register_class(Inventory);
        register_class(Item);
    }
}

deinitialize :: (data: *void, level: InitializationLevel) #c_call {
    push_context cast(*#Context)data {
    }
}

Player :: struct {
    using #as base: Node2D; @Base // @Base to mark this member as its' base class
    inventory: *Inventory;

    speed: float64; @export;
    player_name: string; @export;
    pos: Vector2; @export

    hit :: #type (amount: int); @signal

    get_speed :: (self: *Player) -> float64 {
        print_to_godot("uncomment this to see it wont auto gen this and u can do custom things here");
        return self.speed;
    }


    _enter_tree :: (self: *Player) {
        print_to_godot("Hello from jai!");
    }

    set_speed :: (self: *Player, p_speed: float64) {
        print_to_godot(tprint("set_speed on % to %", cast(*void) self, p_speed));
        self.speed = p_speed;
    }

    _ready :: (self: *Player) {
        a: Vector2 = .{1, 2};
        print_to_godot(tprint("custom pos set to %", self.pos));

        c := self.pos + a;
        print_to_godot(tprint("custom pos addition overload from math %", c));


        print_to_godot(tprint("ready player one. Speed is %", self.speed));
        // print("% %\n", size_of(Vector2), size_of(math.Vector2));
        // self.player_name = "Jon Snow";
        self.inventory = construct(Inventory);
        self.inventory.size = 8;
        Node_add_child(self, self.inventory, true, .INTERNAL_MODE_DISABLED);

        avatar := get_node_as(Sprite2D, self, "Avatar");

        avatar_pos := Node2D_get_global_position(*avatar);
        print_to_godot(tprint("sprite pos = %, %", avatar_pos.x, avatar_pos.y));

        tex := Sprite2D_get_texture(*avatar);
        fake_avatar := get_node(self, "Thisdoesntexist");

        if !is_valid(fake_avatar) {
          print_to_godot("fake node found");
        }
    }

    _input :: (self: *Player, event: InputEvent) {
        if InputEvent_is_action_pressed(*event, "ui_accept", false) && self.inventory {
            print_to_godot(tprint("inv: %", self.inventory.size));
            Node_queue_free(self.inventory);
            self.inventory = null;

            item := construct(Item);
            print_to_godot(tprint("after construct: %", RefCounted_get_reference_count(item)));
            item.item_name = "Sword";
            name_variant := call(item, "get_item_name");
            gd_name: string;
            variant_to(*name_variant, *gd_name);
            print_to_godot(tprint("item name via godot = %", gd_name));
            print_to_godot(tprint("before unref: %", RefCounted_get_reference_count(item)));
            freed := unref(item);

            print_to_godot(tprint("freed:  %", freed));
            print_to_godot(tprint("freed: %, count after: %", freed, RefCounted_get_reference_count(item)));
        }
    }

}


Inventory :: struct {
  using #as base : Node2D; @Base
  size : u8;

_ready :: (self: *Inventory) {
  // direct call
  print_to_godot("ready players inventory");
  parent := Node_get_parent(self);
  player := as(Player, *parent);
  speed := player.speed;
  print_to_godot(tprint("parent speed = %", speed));

  // godot call
  speed_variant := call(player, "get_speed");
  speed2: float64;
  variant_to(*speed_variant, *speed2);
  print_to_godot(tprint("parent speed from gdcall = %", speed2));

  emit(player, "hit", 21);
  }
}

Item :: struct {
  using #as base: Resource; @Base
  item_name : string; @export;
}

to_variant :: (val: float) -> Variant {
    result: Variant = ---;
    variant_from_float(*result, *val);
    return result;
}
