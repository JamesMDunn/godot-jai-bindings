#import "Basic";

#import "godot-jai-bindings";
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
    }
}

deinitialize :: (data: *void, level: InitializationLevel) #c_call {
    push_context cast(*#Context)data {
    }
}

Player :: struct {
    using #as base: Node2D; @Base // @Base to mark this member as its' base class
    inventory: *Inventory;

    speed: float32; @export;

    // get_speed :: (self: *Player) -> float32 {
    //     return self.speed;
    // }

    
    hit :: (self: *Player) {

    } @signal

    _enter_tree :: (self: *Player) {
        print_to_godot("Hello from jai!");
    }

    _ready :: (self: *Player) {
        print_to_godot("ready player one");
        self.inventory = construct(Inventory);
        self.inventory.size = 8;
        Node_add_child(self, self.inventory, true, .INTERNAL_MODE_DISABLED);
    }

    _input :: (self: *Player, event: InputEvent) {
        action := new_string_name("ui_accept");
        defer destroy(*action);
        if InputEvent_is_action_pressed(*event, action, false, false) && self.inventory {  
            print_to_godot(tprint("inv: %", self.inventory.size));
            Node_queue_free(self.inventory);
            self.inventory = null;
        }
    }

}


Inventory :: struct {
    using #as base : Node2D; @Base
    size : u8;

    _ready :: (self: *Inventory) {
        print_to_godot("ready players inventory");
    }
}


to_variant :: (val: float) -> Variant {
    result: Variant = ---;
    variant_from_float(*result, *val);
    return result;
}
