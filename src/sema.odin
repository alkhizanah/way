package main

import "core:fmt"
import "core:math"

Sema_Global_Binding_State :: enum {
	Hoisted,
	In_Progress,
	Analyzed,
}

Sema_Global_Binding :: struct {
	syntax:   ^Ast_Binding,
	value:    Ir_Index,
	state:    Sema_Global_Binding_State,
	constant: bool,
}

Sema_Local_Binding :: struct {
	position: Position,
	pointer:  Ir_Index,
	constant: bool,
}

Scope :: struct {
	parent: ^Scope,
	locals: map[string]Sema_Local_Binding,
}

scope_lookup :: proc(s: ^Scope, name: string) -> (Sema_Local_Binding, bool) {
	s := s

	for s != nil {
		if local, ok := s.locals[name]; ok {
			return local, ok
		}

		s = s.parent
	}

	return {}, false
}

Sema :: struct {
	ast:     ^Ast,
	ir:      Ir,
	scope:   Scope,
	globals: map[string]Sema_Global_Binding,
}

sema_error :: proc(position: Position, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: semantic error: ", position.file_path, position.line, position.column)
	fmt.eprintfln(format, args = args)
}

// NOTE(yhya): This is a naive O(n) algorithm for interning, if intern_type is a hotspot in the future
//			   We can replace it with a custom hash map, but I will not do it currently
intern_type :: proc(s: ^Sema, tag: Ir_Type_Tag, a: Ir_Index, b: Ir_Index) -> Ir_Index {
	type := Ir_Type {
		tag = tag,
		a   = a,
		b   = b,
	}

	retry: for other, index in s.ir.types {
		if type.tag != other.tag do continue retry

		if type.tag == .Function {
			return_type := type.b
			other_return_type := other.b

			if return_type != other_return_type do continue retry

			parameter_types_len := s.ir.extra[type.a]
			other_parameter_types_len := s.ir.extra[other.a]

			if parameter_types_len != other_parameter_types_len do continue retry

			parameter_types_base := type.a + 1
			other_parameter_types_base := other.a + 1

			for i in 0 ..< parameter_types_len {
				if s.ir.extra[parameter_types_base + i] !=
				   s.ir.extra[other_parameter_types_base + i] {
					continue retry
				}
			}

			return Ir_Index(index)
		} else if type == other {
			return Ir_Index(index)
		}
	}

	index := Ir_Index(len(s.ir.types))

	append(&s.ir.types, type)

	return index
}

append_value :: proc(
	s: ^Sema,
	type: Ir_Index,
	tag: Ir_Value_Tag,
	a: Ir_Index,
	b: Ir_Index,
) -> Ir_Index {
	value := Ir_Value {
		type = type,
		tag  = tag,
		a    = a,
		b    = b,
	}

	index := Ir_Index(len(s.ir.values))

	append(&s.ir.values, value)

	return index
}

value_as_type :: proc(s: ^Sema, position: Position, value_id: Ir_Index) -> Ir_Index {
	value := s.ir.values[value_id]

	if value.tag == .Type {
		return value.a
	} else {
		sema_error(position, "expected a type")

		return IR_INVALID
	}
}

pointer_value_child_type :: proc(s: ^Sema, pointer: Ir_Index) -> Ir_Index {
	pointer_type := s.ir.types[s.ir.values[pointer].type]
	assert(pointer_type.tag == .Pointer)
	return pointer_type.a
}

check_type_compatibility :: proc(position: Position, a: Ir_Index, b: Ir_Index) -> bool {
	// NOTE(yhya): Since types are interned then their indices should always be unique
	if a != b {
		sema_error(position, "incompatible types")

		return false
	}

	return true
}

analyze :: proc(s: ^Sema) -> bool {
	hoist_global_bindings(s, s.ast.global_constants[:], constant = true) or_return
	hoist_global_bindings(s, s.ast.global_variables[:], constant = false) or_return

	for _, &binding in s.globals {
		if binding.state == .Analyzed do continue

		analyze_global_binding(s, &binding) or_return
	}

	return true
}

hoist_global_bindings :: proc(s: ^Sema, bindings: []Ast_Binding, constant: bool) -> bool {
	for &binding in bindings {
		if existing, ok := s.globals[binding.name.value]; ok {
			sema_error(
				binding.name.position,
				"'%s' already defined, first defined at %v:%v:%v",
				binding.name.value,
				existing.syntax.name.position.file_path,
				existing.syntax.name.position.line,
				existing.syntax.name.position.column,
			)

			return false
		}

		s.globals[binding.name.value] = {
			state    = .Hoisted,
			syntax   = &binding,
			value    = IR_INVALID,
			constant = constant,
		}
	}

	return true
}

analyze_global_binding :: proc(s: ^Sema, binding: ^Sema_Global_Binding) -> bool {
	binding.state = .In_Progress

	explicit_type := IR_INVALID

	if binding.syntax.type != AST_INVALID {
		type_meta := intern_type(s, .Type, 0, 0)
		type_value := analyze_expr(s, type_meta, binding.syntax.type)

		if type_value == IR_INVALID do return false

		explicit_type = value_as_type(s, binding.syntax.name.position, type_value)

		if explicit_type == IR_INVALID do return false
	}

	if binding.syntax.value == AST_INVALID {
		assert(explicit_type != IR_INVALID)

		binding.value = append_value(s, explicit_type, .Zero, 0, 0)
	} else {
		binding.value = analyze_expr(s, explicit_type, binding.syntax.value)

		if binding.value == IR_INVALID do return false
	}

	if !binding.constant {
		initializer := s.ir.values[binding.value]

		initializer_type := s.ir.types[initializer.type]

		if initializer_type.tag == .Untyped_Int {
			sema_error(
				binding.syntax.name.position,
				"please specify a type for your integer variable, the compiler can't decide on its own",
			)

			return false
		} else if initializer_type.tag == .Untyped_Float {
			sema_error(
				binding.syntax.name.position,
				"please specify a type for your float variable, the compiler can't decide on its own",
			)

			return false
		}

		index := Ir_Index(len(s.ir.globals))

		append(&s.ir.globals, Ir_Global{name = binding.syntax.name, value = binding.value})

		binding.value = append_value(s, initializer.type, .Global, index, 0)
	}

	binding.state = .Analyzed

	return true
}

analyze_expr :: proc(s: ^Sema, result_type: Ir_Index, node_id: Ast_Index) -> Ir_Index {
	node := s.ast.nodes[node_id]
	position := s.ast.positions[node_id]

	#partial switch node.tag {
	case .Identifier:
		return analyze_identifier(s, result_type, node, position)

	case .Int:
		return analyze_int(s, result_type, node, position)

	case .Unsigned_Int_Type:
		return analyze_int_type(s, result_type, node, position, signed = false)

	case .Signed_Int_Type:
		return analyze_int_type(s, result_type, node, position, signed = true)

	case:
		sema_error(position, "unhandled expression")

		return IR_INVALID
	}
}

analyze_identifier :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	name := string(s.ast.strings[node.a:][:node.b])

	if local, ok := scope_lookup(&s.scope, name); ok {
		local_type := pointer_value_child_type(s, local.pointer)

		if result_type_id != IR_INVALID && !check_type_compatibility(position, local_type, result_type_id) do return IR_INVALID

		return append_value(s, local_type, .Load, local.pointer, 0)
	}

	if binding, ok := &s.globals[name]; ok {
		if binding.state == .In_Progress {
			sema_error(position, "cyclic reference because of using '%s'", name)

			return IR_INVALID
		} else if binding.state == .Hoisted && !analyze_global_binding(s, binding) {
			return IR_INVALID
		}

		assert(binding.state == .Analyzed)

		binding_type := s.ir.values[binding.value].type

		if result_type_id != IR_INVALID && !check_type_compatibility(position, binding_type, result_type_id) do return IR_INVALID

		return binding.value
	}

	sema_error(position, "undeclared name: %s", name)

	return IR_INVALID
}

is_float_type :: proc(type: Ir_Type) -> bool {
	#partial switch type.tag {
	case .Float:
		fallthrough

	case .Untyped_Float:
		return true

	case:
		return false
	}
}

is_int_type :: proc(type: Ir_Type) -> bool {
	#partial switch type.tag {
	case .Unsigned_Int:
		fallthrough

	case .Signed_Int:
		fallthrough

	case .Untyped_Int:
		return true

	case:
		return false
	}
}

bits_needed_for_float :: proc(n: f64) -> uint {
	return uint(math.ceil(math.log2(n + 1)))
}

bits_needed_for_int :: proc(#any_int n: int, signed: bool) -> uint {
	return bits_needed_for_float(f64(n)) + (signed && (n > 0) ? 1 : 0)
}


analyze_int :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	upper_bits := Ir_Index(node.a)
	lower_bits := Ir_Index(node.b)

	v := u64(upper_bits) << 32 | u64(lower_bits)
	vf := f64(v)

	if result_type_id == IR_INVALID {
		return append_value(s, intern_type(s, .Untyped_Int, 0, 0), .Int, upper_bits, lower_bits)
	}

	result_type := s.ir.types[result_type_id]

	if is_float_type(result_type) {
		bvf := transmute(u64)vf

		lower_bits = Ir_Index(bvf)
		upper_bits = Ir_Index(bvf >> 32)

		return append_value(s, result_type_id, .Float, upper_bits, lower_bits)
	} else if !is_int_type(result_type) {
		sema_error(position, "did not expect an integer")

		return IR_INVALID
	}

	bits_needed := bits_needed_for_int(v, signed = result_type.tag == .Signed_Int)

	bits_available := uint(result_type.a)

	if bits_available < bits_needed {
		sema_error(
			position,
			"integer literal needs %v or more bits to keep the same information but the type only has %v bits",
			bits_needed,
			bits_available,
		)
	}

	return append_value(s, result_type_id, .Int, upper_bits, lower_bits)
}

analyze_int_type :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	signed: bool,
) -> Ir_Index {
	result_type_id := result_type_id

	if result_type_id == IR_INVALID {
		result_type_id = intern_type(s, .Type, 0, 0)
	} else {
		result_type := s.ir.types[result_type_id]

		if result_type.tag != .Type {
			sema_error(position, "did not expect a type in here")

			return IR_INVALID
		}
	}

	int_type := intern_type(s, signed ? .Signed_Int : .Unsigned_Int, Ir_Index(node.a), 0)

	return append_value(s, result_type_id, .Type, int_type, 0)
}
