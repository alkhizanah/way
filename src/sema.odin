package main

import "core:fmt"
import "core:math"
import "core:strings"

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

type_to_string :: proc(s: ^Sema, type_id: Ir_Index, builder: ^strings.Builder) {
	type := s.ir.types[type_id]

	switch type.tag {
	case .Unsigned_Int:
		fmt.sbprintf(builder, "u%v", type.a)

	case .Signed_Int:
		fmt.sbprintf(builder, "s%v", type.a)

	case .Float:
		fmt.sbprintf(builder, "f%v", type.a)

	case .Untyped_Int:
		strings.write_string(builder, "<untyped int>")

	case .Untyped_Float:
		strings.write_string(builder, "<untyped float>")

	case .Bool:
		strings.write_string(builder, "bool")

	case .Void:
		strings.write_string(builder, "void")

	case .Type:
		strings.write_string(builder, "type")

	case .Pointer:
		strings.write_byte(builder, '*')
		type_to_string(s, type.a, builder)

	case .Function:
		strings.write_string(builder, "fn (")

		parameters_count := s.ir.extra[type.a]

		for i in 0 ..< parameters_count {
			if i > 0 do strings.write_string(builder, ", ")

			type_to_string(s, s.ir.extra[type.a + 1 + i], builder)
		}

		strings.write_string(builder, ") -> ")

		type_to_string(s, type.b, builder)
	}
}

type_to_string_temp :: proc(s: ^Sema, type_id: Ir_Index) -> string {
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, 32, context.temp_allocator)
	type_to_string(s, type_id, &builder)
	return strings.to_string(builder)
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

check_type_compatibility :: proc(s: ^Sema, position: Position, a: Ir_Index, b: Ir_Index) -> bool {
	// NOTE(yhya): Since types are interned then their indices should always be unique
	if a != b {
		sema_error(
			position,
			"incompatible types '%s' and '%s'",
			type_to_string_temp(s, a),
			type_to_string_temp(s, b),
		)

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

	case .Float:
		return analyze_float(s, result_type, node, position)

	case .True:
		return analyze_bool(s, result_type, true, position)

	case .False:
		return analyze_bool(s, result_type, false, position)

	case .Unsigned_Int_Type:
		return analyze_int_type(s, result_type, node, position, signed = false)

	case .Signed_Int_Type:
		return analyze_int_type(s, result_type, node, position, signed = true)

	case .Float16_Type:
		return analyze_float_type(s, result_type, 16, position)

	case .Float32_Type:
		return analyze_float_type(s, result_type, 32, position)

	case .Float64_Type:
		return analyze_float_type(s, result_type, 64, position)

	case .Bool_Type:
		return analyze_bool_type(s, result_type, position)

	case .Void_Type:
		return analyze_void_type(s, result_type, position)

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

		if result_type_id != IR_INVALID && !check_type_compatibility(s, position, local_type, result_type_id) do return IR_INVALID

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

		if result_type_id != IR_INVALID && !check_type_compatibility(s, position, binding_type, result_type_id) do return IR_INVALID

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

int_bits_needed :: proc(#any_int n: int, signed: bool) -> uint {
	return uint(math.ceil(math.log2(f64(n + (signed && (n > 0) ? 1 : 0)) + 1)))
}

float_can_fit :: proc($T: typeid, v: $A) -> bool {
	return f64(T(v)) == f64(v)
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

		can_fit: bool

		switch result_type.a {
		case 16:
			can_fit = float_can_fit(f16, v)
		case 32:
			can_fit = float_can_fit(f32, v)
		case 64:
			can_fit = float_can_fit(f64, v)
		case:
			unreachable()
		}

		if !can_fit {
			sema_error(position, "integer literal '%v' can not fit into an f%v", v, result_type.a)

			return IR_INVALID
		}

		return append_value(s, result_type_id, .Float, upper_bits, lower_bits)
	} else if !is_int_type(result_type) {
		sema_error(
			position,
			"did not expect an integer, expected '%s' value",
			type_to_string_temp(s, result_type_id),
		)

		return IR_INVALID
	}

	bits_needed := int_bits_needed(v, signed = result_type.tag == .Signed_Int)

	bits_available := uint(result_type.a)

	if bits_available < bits_needed {
		sema_error(
			position,
			"integer literal '%v' needs %v or more bits which the type '%v%v' does not have",
			v,
			bits_needed,
			result_type.tag == .Signed_Int ? 's' : 'u',
			bits_available,
		)
	}

	return append_value(s, result_type_id, .Int, upper_bits, lower_bits)
}

analyze_float :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	upper_bits := Ir_Index(node.a)
	lower_bits := Ir_Index(node.b)

	v := transmute(f64)(u64(upper_bits) << 32 | u64(lower_bits))
	vi := u64(v)

	if result_type_id == IR_INVALID {
		return append_value(
			s,
			intern_type(s, .Untyped_Float, 0, 0),
			.Float,
			upper_bits,
			lower_bits,
		)
	}

	result_type := s.ir.types[result_type_id]

	if is_int_type(result_type) {
		if v - f64(vi) != 0 {
			sema_error(
				position,
				"float literal '%v' can not transform to integer since it has decimal points",
				v,
			)

			return IR_INVALID
		}

		lower_bits = Ir_Index(vi)
		upper_bits = Ir_Index(vi >> 32)

		bits_needed := int_bits_needed(vi, signed = result_type.tag == .Signed_Int)

		bits_available := uint(result_type.a)

		if bits_available < bits_needed {
			sema_error(
				position,
				"integer literal '%v' needs %v or more bits which the type '%v%v' does not have",
				vi,
				bits_needed,
				result_type.tag == .Signed_Int ? 's' : 'u',
				bits_available,
			)
		}

		return append_value(s, result_type_id, .Int, upper_bits, lower_bits)
	} else if !is_float_type(result_type) {
		sema_error(
			position,
			"did not expect a float, expected '%s' value",
			type_to_string_temp(s, result_type_id),
		)

		return IR_INVALID
	}

	can_fit: bool

	switch result_type.a {
	case 16:
		can_fit = float_can_fit(f16, v)
	case 32:
		can_fit = float_can_fit(f32, v)
	case 64:
		can_fit = float_can_fit(f64, v)
	case:
		unreachable()
	}

	if !can_fit {
		sema_error(position, "float literal '%v' can not fit into an f%v", v, result_type.a)

		return IR_INVALID
	}

	return append_value(s, result_type_id, .Float, upper_bits, lower_bits)
}

analyze_bool :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	value: bool,
	position: Position,
) -> Ir_Index {
	bool_type := intern_type(s, .Bool, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, bool_type, result_type_id) do return IR_INVALID

	return append_value(s, bool_type, .Bool, Ir_Index(value), 0)
}

analyze_int_type :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	signed: bool,
) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, type_meta, result_type_id) do return IR_INVALID

	int_type := intern_type(s, signed ? .Signed_Int : .Unsigned_Int, Ir_Index(node.a), 0)

	return append_value(s, result_type_id, .Type, int_type, 0)
}

analyze_float_type :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	bit_width: u32,
	position: Position,
) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, type_meta, result_type_id) do return IR_INVALID

	float_type := intern_type(s, .Float, Ir_Index(bit_width), 0)

	return append_value(s, result_type_id, .Type, float_type, 0)
}

analyze_bool_type :: proc(s: ^Sema, result_type_id: Ir_Index, position: Position) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, type_meta, result_type_id) do return IR_INVALID

	bool_type := intern_type(s, .Bool, 0, 0)

	return append_value(s, result_type_id, .Type, bool_type, 0)
}

analyze_void_type :: proc(s: ^Sema, result_type_id: Ir_Index, position: Position) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, type_meta, result_type_id) do return IR_INVALID

	void_type := intern_type(s, .Void, 0, 0)

	return append_value(s, result_type_id, .Type, void_type, 0)
}
