package main

import "core:encoding/ansi"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:reflect"
import "core:mem"
import "core:time"
import "core:slice"
import "core:sys/linux"


widget_ids: struct {
    root_list,
    log_entries,
    config,
    : int
}

@(private="file")
buffer: [1024 * 1024]byte
@(private="file")
buffer_ptr := 0

@(private="file")
print :: proc(args: ..any) {
    buffer_ptr += len(fmt.bprint(buffer[buffer_ptr:], ..args))
}

@(private="file")
printf :: proc(format: string, args: ..any) {
    buffer_ptr += len(fmt.bprintf(buffer[buffer_ptr:], format, ..args))
}

@(private="file")
printfln :: proc(format: string, args: ..any) {
    buffer_ptr += len(fmt.bprintfln(buffer[buffer_ptr:], format, ..args))
}

@(private="file") start_time: time.Time

inspector_start :: proc() {
    start_time = time.now()

    widget_tree = make([dynamic]Widget, 1, 100)

    widget_ids.root_list = inspector_add_widget(Widget{
        data = Widget_Raw_List{}
    }, 0)

    widget_ids.log_entries = inspector_add_widget(Widget{
        data = Widget_List{
            header = "Log",
            collapsed = false,
            max_items = 20,
        }
    }, widget_ids.root_list)

    widget_ids.config = inspector_create_tree(
        Struct_Tag_Info{name = "Config"},
        &config,
        typeid_of(type_of(config)),
        widget_ids.root_list,
    )
}

inspector_add_widget :: proc(widget: Widget, parent: int) -> int {
    id := len(widget_tree)
    if len(garbage_ids) > 0 do id = pop(&garbage_ids)
    widget := widget
    widget.id = id
    widget.parent = parent
    if parent != 0 {
        parent_widget := &widget_tree[parent]
        append(&parent_widget.children, id)
    }
    if id >= len(widget_tree) {
        append(&widget_tree, widget)
    } else {
        widget_tree[id] = widget
    }
    return id
}

Struct_Tag_Info :: struct {
    name: Maybe(string),
    editable: bool,
    button: bool,
    default: Maybe(string),
}

parse_struct_field :: proc(tag: reflect.Struct_Tag) -> (info: Struct_Tag_Info) {
    for part in strings.split(string(tag), ",", allocator=context.temp_allocator) {
        if strings.has_prefix(part, "name=") {
            info.name = strings.trim_prefix(part, "name=")
        } else if strings.has_prefix(part, "editable") {
            info.editable = true
        } else if strings.has_prefix(part, "default=") {
            info.default = strings.trim_prefix(part, "default=")
        } else if strings.has_prefix(part, "button") {
            info.button = true
        }
    }

    return info
}

inspector_create_tree :: proc(tag: Struct_Tag_Info, ptr: rawptr, T: typeid, parent: int) -> int {
    info := type_info_of(T)

    if default, present := tag.default.?; present {
        if reflect.is_boolean(info) {
            (cast(^bool)ptr)^ = strconv.parse_bool(default) or_else panic("Invalid boolean value")
        } else if reflect.are_types_identical(info, type_info_of(int)) {
            (cast(^int)ptr)^ = strconv.parse_int(default) or_else panic("Invalid integer value")
        } else if reflect.are_types_identical(info, type_info_of(f32)) {
            (cast(^f32)ptr)^ = strconv.parse_f32(default) or_else panic("Invalid float value")
        } else if reflect.is_string(info) {
            (cast(^string)ptr)^ = strings.clone(default)
        } else {
            fmt.panicf("Unsupported default value for type %v", info)
        }
    }

    if reflect.is_struct(info) {
        id := inspector_add_widget(Widget{
            data = Widget_List{
                header = tag.name.? or_else "struct",
                collapsed = false,
            }
        }, parent)

        for field in reflect.struct_fields_zipped(T) {
            tag := parse_struct_field(field.tag)
            if tag.name == nil do tag.name = field.name
            inspector_create_tree(
                tag,
                rawptr(cast(uintptr)ptr + field.offset),
                field.type.id,
                id,
            )
        }

        return id
    } else if reflect.is_enum(info) && tag.editable {
        id := inspector_add_widget(Widget{
            data = Widget_Select{
                name = tag.name.? or_else "enum",
                value = any{data = ptr, id = T},
            }
        }, parent)

        return id
    } else if reflect.is_boolean(info) && tag.button {
        id := inspector_add_widget(Widget{
            data = Widget_Button{
                name = tag.name.? or_else "button",
                value = cast(^bool)ptr,
            }
        }, parent)

        return id
    } else if reflect.is_boolean(info) && tag.editable {
        id := inspector_add_widget(Widget{
            data = Widget_Toggle{
                name = tag.name.? or_else "toggle",
                value = cast(^bool)ptr,
            }
        }, parent)

        return id
    } else {
        id := inspector_add_widget(Widget{
            data = Widget_View{
                name = tag.name.? or_else "value",
                value = any{data = ptr, id = T},
            }
        }, parent)

        return id
    }
}

terminal_width: int = 45
frame: u64 = 0

log :: proc(format: string, args: ..any) {
    inspector_info(fmt.tprintf(format, ..args))
}

inspector_info :: proc(message: string) {
    inspector_add_widget(Widget{
        data = Widget_Tagged_Text{
            ansi_tag_deco = ansi.CSI + ansi.FG_GREEN + ansi.SGR + ansi.CSI + ansi.BOLD + ansi.SGR,
            tag = "INFO",
            ansi_text_deco = ansi.CSI + ansi.FG_GREEN + ansi.SGR,
            text = strings.clone(message),
        }
    }, widget_ids.log_entries)
}

inspector_warning :: proc(message: string) {
    inspector_add_widget(Widget{
        data = Widget_Tagged_Text{
            ansi_tag_deco = ansi.CSI + ansi.FG_YELLOW + ansi.SGR + ansi.CSI + ansi.BOLD + ansi.SGR,
            tag = "WARNING",
            ansi_text_deco = ansi.CSI + ansi.FG_YELLOW + ansi.SGR,
            text = strings.clone(message),
        }
    }, widget_ids.log_entries)
}

inspector_error :: proc(message: string) {
    inspector_add_widget(Widget{
        data = Widget_Tagged_Text{
            ansi_tag_deco = ansi.CSI + ansi.FG_RED + ansi.SGR + ansi.CSI + ansi.BOLD + ansi.SGR,
            tag = "ERROR",
            ansi_text_deco = ansi.CSI + ansi.FG_RED + ansi.SGR,
            text = strings.clone(message),
        }
    }, widget_ids.log_entries)
}

inspector_inc_frame :: proc() {
    frame += 1
}

Widget_Base :: struct {
    parent: int,
    id: int,
    children: [dynamic]int,
    tag: bool,
    deleted: bool,
}

Widget_Text :: struct {
    text: string,
    ansi_deco: string,
}

Widget_Tagged_Text :: struct {
    ansi_tag_deco: string,
    tag: string,
    ansi_text_deco: string,
    text: string,
}

Widget_List :: struct {
    header: string,
    collapsed: bool,
    max_items: int,
}

Widget_Raw_List :: struct {}

Widget_Toggle :: struct {
    name: string,
    value: ^bool,
}

Widget_Button :: struct {
    name: string,
    value: ^bool,
}

Widget_Select :: struct {
    name: string,
    value: any,
}

Widget_View :: struct {
    name: string,
    value: any,
}

Widget_Data :: union {
    Widget_Text,
    Widget_Tagged_Text,
    Widget_List,
    Widget_Toggle,
    Widget_Button,
    Widget_Raw_List,
    Widget_View,
    Widget_Select,
}

Widget :: struct {
    using base: Widget_Base,
    data: Widget_Data,
}

@(private="file") selection: int = 1
@(private="file") widget_tree: [dynamic]Widget
@(private="file") garbage_ids: [dynamic]int
@(private="file") selection_order: [dynamic]int
@(private="file") align_buffer: [1024]byte

inspector_render_widget :: proc(id: int, level: int) {
    width := terminal_width - level * 2
    for i := 0; i < level; i += 1 {
        print("  ")
    }

    base_deco :: #force_inline proc(id: int) -> string {
        if id == selection {
            return ansi.CSI + ansi.RESET + ansi.SGR + ansi.CSI + ansi.BG_BLUE + ansi.SGR
        }
        return ansi.CSI + ansi.RESET + ansi.SGR
    }

    end_line :: #force_inline proc(id: int) -> string {
        if id == selection {
            return ansi.CSI + ansi.RESET + ansi.SGR + ansi.CSI + ansi.BG_BLUE + ansi.SGR + 
                ansi.CSI + "60" + ansi.CHA + "\n" + ansi.CSI + ansi.RESET + ansi.SGR
        }
        return ansi.CSI + ansi.RESET + ansi.SGR + ansi.CSI + "60" + ansi.CHA + "\n" 
    }

    str :: proc(text: string, width: int, padding: int = 0) -> string {
        for i in 0..<width do align_buffer[i] = ' '
        width := width - padding
        if len(text) <= width {
            mem.copy(&align_buffer, raw_data(text), len(text))
        } else {
            now := time.now()
            diff := time.diff(start_time, now)
            diff_ms := cast(u64)time.duration_milliseconds(diff) / 50
            tick := int(diff_ms % u64(len(text) - width + 60))
            start := tick - 30
            end := start + width
            if start <= 0 {
                mem.copy(&align_buffer, raw_data(text[:width]), width)
            } else if end >= len(text) {
                mem.copy(&align_buffer, raw_data(text[len(text) - width:]), width)
            } else {
                mem.copy(&align_buffer, raw_data(text[start:end]), width)
            }
        }
        return transmute(string)align_buffer[:width + padding]
    }

    print(base_deco(id))

    widget := &widget_tree[id]
    if widget.deleted do return

    switch &w in widget.data {
        case Widget_Text:
            printf("%s%s%s", w.ansi_deco, str(w.text, width), end_line(id))
            assert(len(widget.children) == 0)
        case Widget_List:
            if w.max_items != 0 && len(widget.children) > w.max_items {
                remove_range(&widget.children, 0, len(widget.children) - w.max_items)
            }
            if w.collapsed {
                printf("> %s%s", str(w.header, width - 2), end_line(id))
            } else {
                printf("- %s%s", str(w.header, width - 2), end_line(id))
                for i in widget.children {
                    inspector_render_widget(i, level + 1)
                }
            }
        case Widget_Raw_List:
            for i in widget.children {
                inspector_render_widget(i, level)
            }
        case Widget_Tagged_Text:
            printf(
                "%s[%s]%s %s%s%s",
                w.ansi_tag_deco,
                w.tag,
                base_deco(id),
                w.ansi_text_deco,
                str(w.text, width - 3 - len(w.tag), 2),
                end_line(id),
            )
            assert(len(widget.children) == 0)
        case Widget_Toggle:
            value_str := w.value^ ? "ON" : "OFF"

            printf(
                "%s%s%s%s%s",
                base_deco(id),
                str(w.name, width - len(value_str), 2),
                w.value^ ? ansi.CSI + ansi.FG_GREEN + ansi.SGR : ansi.CSI + ansi.FG_RED + ansi.SGR,
                value_str,
                end_line(id),
            )
        case Widget_Button:
            printf(
                "%s[PRESS] %s%s",
                base_deco(id),
                str(w.name, width - 8),
                end_line(id),
            )
        case Widget_View:
            value_repr := fmt.tprint(w.value)

            printf(
                "%s%s%s%s",
                base_deco(id),
                str(w.name, width - len(value_repr), 2),
                value_repr,
                end_line(id),
            )
        case Widget_Select:
            value_repr := fmt.tprint(w.value)

            printf(
                "%s%s%s%s",
                base_deco(id),
                str(w.name, width - len(value_repr), 2),
                value_repr,
                end_line(id),
            )
    }
}

inspector_recompute_selection_order :: proc(id: int, result: ^[dynamic]int) {
    widget := widget_tree[id]
    if widget.deleted do return

    switch w in widget.data {
        case Widget_Text:
        case Widget_Tagged_Text:
        case Widget_List:
            append(result, id)
            if !w.collapsed {
                for i in widget.children {
                    inspector_recompute_selection_order(i, result)
                }
            }
        case Widget_Raw_List:
            for i in widget.children {
                inspector_recompute_selection_order(i, result)
            }
        case Widget_Toggle:
            append(result, id)
        case Widget_View:
            append(result, id)
        case Widget_Select:
            append(result, id)
        case Widget_Button:
            append(result, id)
    }
}

inspector_selection_index :: proc() -> int {
    if len(selection_order) == 0 {
        return -1
    }

    index := -1
    for v, i in selection_order {
        if v == selection {
            index = i
            break
        }
    }

    return index
}

inspector_selection_down :: proc() {
    index := inspector_selection_index()

    if index == -1 {
        selection = selection_order[0]
    } else {
        index += 1
        if index >= len(selection_order) do return
        selection = selection_order[index]
    }
}

inspector_selection_up :: proc() {
    index := inspector_selection_index()

    if index == -1 {
        selection = selection_order[0]
    } else {
        index -= 1
        if index < 0 do return
        selection = selection_order[index]
    }
}

inspector_action :: proc(value: int) {
    index := inspector_selection_index()
    if index == -1 do return

    widget := &widget_tree[selection]
    #partial switch &w in widget.data {
        case Widget_List:
            w.collapsed = !w.collapsed
        case Widget_Toggle:
            w.value^ = !w.value^
        case Widget_Button:
            w.value^ = true
        case Widget_Select:
            fields := reflect.enum_fields_zipped(w.value.id)
            current := (cast(^int)w.value.data)^
            current_index := -1
            for field, i in fields {
                if int(field.value) == current {
                    current_index = i
                    break
                }
            }
            if current_index == -1 do return
            value := value == 0 ? 1 : value
            current_index = (current_index + value) %% len(fields)
            (cast(^int)w.value.data)^ = int(fields[current_index].value)
    }
}

update_widget_tags :: proc(id: int) {
    widget := &widget_tree[id]
    widget.tag = true
    for child in widget.children {
        update_widget_tags(child)
    }
}

inspector_render :: proc() {
    printf(ansi.CSI + "1;1" + ansi.CUP + ansi.CSI + ansi.ED)
    inspector_render_widget(1, 0)

    fmt.printfln("%s", buffer[:buffer_ptr])
    buffer_ptr = 0

    for &widget, i in widget_tree {
        widget.tag = false
    }
    update_widget_tags(1)

    for i in 1..<len(widget_tree) {
        if !widget_tree[i].tag {
            append(&garbage_ids, i)
            widget_tree[i].deleted = true
        }
    }

    clear(&selection_order)
    inspector_recompute_selection_order(1, &selection_order)
}
