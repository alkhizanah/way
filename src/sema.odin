package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"

Sema_Global_Binding :: struct {
	syntax:   ^Ast_Binding,
	value:    Ir_Index,
	constant: bool,
	state:    enum {
		Hoisted,
		In_Progress,
		Analyzed,
	},
}

Sema_Local_Binding :: struct {
	position: Position,
	value:    Ir_Index,
	constant: bool,
}

Scope :: struct {
	parent: ^Scope,
	locals: map[string]Sema_Local_Binding,
}

make_scope :: proc(parent: ^Scope) -> Scope {
	return {parent = parent, locals = make(map[string]Sema_Local_Binding)}
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

scope_add :: proc(s: ^Scope, name: string, value: Ir_Index, constant: bool, position: Position) {
	s.locals[name] = {
		value    = value,
		constant = constant,
		position = position,
	}
}

Sema :: struct {
	ast:      ^Ast,
	ir:       Ir,
	globals:  map[string]Sema_Global_Binding,
	function: Ir_Index,
	block:    Ir_Index,
	scope:    Scope,
}

sema_init :: proc(s: ^Sema, ast: ^Ast) {
	s.ast = ast
	s.function = IR_INVALID
	s.block = IR_INVALID
	s.scope = make_scope(nil)
	s.globals = make(map[string]Sema_Global_Binding)
}

sema_error :: proc(position: Position, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: semantic error: ", position.file_path, position.line, position.column)
	fmt.eprintfln(format, args = args)
}

sema_redeclaration_error :: proc(
	position: Position,
	existing_position: Position,
	redeclared_name: string,
) {
	sema_error(
		position,
		"'%s' is already declared, first declaration is at %v:%v:%v",
		redeclared_name,
		existing_position.file_path,
		existing_position.line,
		existing_position.column,
	)
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

	case .Single_Pointer:
		strings.write_byte(builder, '*')
		type_to_string(s, type.a, builder)

	case .Multi_Pointer:
		strings.write_string(builder, "[*]")
		type_to_string(s, type.a, builder)

	case .Slice:
		strings.write_string(builder, "[]")
		type_to_string(s, type.a, builder)

	case .Array:
		fmt.sbprintf(builder, "[%v]", type.b)
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

unchecked_value_as_type :: proc(s: ^Sema, value_id: Ir_Index) -> Ir_Index {
	return s.ir.values[value_id].a
}

append_value_with_struct :: proc(s: ^Sema, value: Ir_Value) -> Ir_Index {
	index := Ir_Index(len(s.ir.values))

	append(&s.ir.values, value)

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

	return append_value_with_struct(s, value)
}

append_instruction :: proc(
	s: ^Sema,
	tag: Ir_Instruction_Tag,
	a: Ir_Index,
	b: Ir_Index,
) -> Ir_Index {
	instruction := Ir_Instruction {
		tag = tag,
		a   = a,
		b   = b,
	}

	function := &s.ir.functions[s.function]

	block := &function.blocks[s.block]

	index := Ir_Index(len(block.instructions))

	append(&block.instructions, instruction)

	return index
}

is_const_value :: proc(s: ^Sema, value_id: Ir_Index) -> bool {
	value := s.ir.values[value_id]

	switch value.tag {
	case .Int, .Float, .Bool, .Zero, .Null, .Type, .Function, .String:
		return true

	case .Negate, .Bool_Not, .Bit_Not:
		return is_const_value(s, value.a)

	case .Add,
	     .Sub,
	     .Mul,
	     .Div,
	     .Mod,
	     .Bit_Or,
	     .Bit_Xor,
	     .Bit_And,
	     .Bit_Shl,
	     .Bit_Shr,
	     .Eql,
	     .Neq,
	     .Lt,
	     .Gt,
	     .Lte,
	     .Gte:
		return is_const_value(s, value.a) && is_const_value(s, value.b)

	case .Global, .Alloca, .Load, .Get_Element_Ptr, .Call, .Parameter:
		return false
	}

	return false
}

can_fit_into_int_type :: proc(position: Position, v: $T, desired_type: Ir_Type) -> bool {
	bits_available := uint(desired_type.a)

	when intrinsics.type_is_float(T) {
		if v < 0 && desired_type.tag != .Signed_Int {
			sema_error(
				position,
				"negative value '%v' can not fit into unsigned type 'u%v'",
				v,
				bits_available,
			)

			return false
		}

		if v - T(u64(v)) != 0 {
			sema_error(
				position,
				"'%v' can not fit into '%v%v' since it has decimal points",
				v,
				desired_type.tag == .Signed_Int ? 's' : 'u',
				bits_available,
			)

			return false
		}
	}

	helper :: proc(n: $T, signed: bool) -> uint {
		return uint(math.ceil(math.log2(f64(n + ((signed && (n > 0)) ? 1 : 0)) + 1)))
	}

	bits_needed := helper(v, signed = desired_type.tag == .Signed_Int)

	if bits_available < bits_needed {
		sema_error(
			position,
			"'%v' needs %v or more bits which the type '%v%v' does not have",
			v,
			bits_needed,
			desired_type.tag == .Signed_Int ? 's' : 'u',
			bits_available,
		)

		return false
	}

	return true
}

can_fit_into_float_type :: proc(position: Position, v: $T, desired_type: Ir_Type) -> bool {
	can_fit: bool

	helper :: proc($T: typeid, v: $A) -> bool {
		return f64(T(v)) == f64(v)
	}

	switch desired_type.a {
	case 16:
		can_fit = helper(f16, v)
	case 32:
		can_fit = helper(f32, v)
	case 64:
		can_fit = helper(f64, v)
	case:
		unreachable()
	}

	if !can_fit {
		sema_error(position, "'%v' can not fit into 'f%v'", v, desired_type.a)

		return false
	}

	return true
}

can_cast_untyped_value :: proc(
	s: ^Sema,
	position: Position,
	value_id: Ir_Index,
	desired_type_id: Ir_Index,
) -> bool {
	value := s.ir.values[value_id]
	value_type := s.ir.types[value.type]
	desired_type := s.ir.types[desired_type_id]

	if value_type.tag == .Untyped_Int {
		if !is_int_type(desired_type) {
			sema_error(
				position,
				"untyped integer can not cast into '%v'",
				type_to_string_temp(s, desired_type_id),
			)

			return false
		}

		if desired_type.tag == .Untyped_Int do return true

		if value.tag != .Int do return true

		v := extract_int_value(value)

		return can_fit_into_int_type(position, v, desired_type)
	} else if value_type.tag == .Untyped_Float {
		if !is_float_type(desired_type) {
			sema_error(
				position,
				"untyped float can not cast into '%v'",
				type_to_string_temp(s, desired_type_id),
			)

			return false
		}

		if desired_type.tag == .Untyped_Float do return true

		if value.tag != .Float do return true

		v := extract_float_value(value)

		return can_fit_into_float_type(position, v, desired_type)
	}

	return true
}

append_int_value :: proc(s: ^Sema, type: Ir_Index, value: u64) -> Ir_Index {
	upper_bits := Ir_Index(value >> 32)
	lower_bits := Ir_Index(value)

	return append_value(s, type, .Int, upper_bits, lower_bits)
}

extract_int_value :: proc(container: $T) -> u64 {
	upper_bits := u64(container.a)
	lower_bits := u64(container.b)

	return (upper_bits << 32) | lower_bits
}

append_float_value :: proc(s: ^Sema, type: Ir_Index, value: f64) -> Ir_Index {
	value_reinterpreted := transmute(u64)value

	upper_bits := Ir_Index(value_reinterpreted >> 32)
	lower_bits := Ir_Index(value_reinterpreted)

	return append_value(s, type, .Float, upper_bits, lower_bits)
}

extract_float_value :: proc(container: $T) -> f64 {
	upper_bits := u64(container.a)
	lower_bits := u64(container.b)

	return transmute(f64)((upper_bits << 32) | lower_bits)
}

check_type_compatibility :: proc(s: ^Sema, position: Position, a: Ir_Index, b: Ir_Index) -> bool {
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
			sema_redeclaration_error(
				binding.name.position,
				existing.syntax.name.position,
				binding.name.value,
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

		explicit_type = unchecked_value_as_type(s, type_value)
	}

	if binding.syntax.value == AST_INVALID {
		assert(explicit_type != IR_INVALID)

		binding.value = append_value(s, explicit_type, .Zero, 0, 0)
	} else {
		binding.value = analyze_expr(
			s,
			explicit_type,
			binding.syntax.value,
			binding.syntax.name.value,
		)

		if binding.value == IR_INVALID do return false
	}

	if !is_const_value(s, binding.value) {
		sema_error(binding.syntax.name.position, "initializer is not a constant value")

		return false
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

analyze_expr :: proc(
	s: ^Sema,
	result_type: Ir_Index,
	node_id: Ast_Index,
	name: Maybe(string) = nil,
) -> Ir_Index {
	node := s.ast.nodes[node_id]
	position := s.ast.positions[node_id]

	#partial switch node.tag {
	case .Identifier:
		return analyze_identifier(s, result_type, node, position)

	case .String:
		return analyze_string(s, result_type, node, position)

	case .Int:
		return analyze_int(s, result_type, node, position)

	case .Float:
		return analyze_float(s, result_type, node, position)

	case .True:
		return analyze_bool(s, result_type, true, position)

	case .False:
		return analyze_bool(s, result_type, false, position)

	case .Function:
		return analyze_function(s, result_type, node, position, name)

	case .Call:
		return analyze_call(s, result_type, node, position)

	case .Bool_Not:
		return analyze_bool_not(s, result_type, node, position)

	case .Bit_Not:
		return analyze_bit_not(s, result_type, node, position)

	case .Negate:
		return analyze_negate(s, result_type, node, position)

	case .Add:
		return analyze_arithmetic_operation(s, result_type, node, position, .Add)

	case .Sub:
		return analyze_arithmetic_operation(s, result_type, node, position, .Sub)

	case .Mul:
		return analyze_arithmetic_operation(s, result_type, node, position, .Mul)

	case .Div:
		return analyze_arithmetic_operation(s, result_type, node, position, .Div)

	case .Mod:
		return analyze_arithmetic_operation(s, result_type, node, position, .Mod)

	case .Bit_Or:
		return analyze_bitwise_operation(s, result_type, node, position, .Bit_Or)

	case .Bit_Xor:
		return analyze_bitwise_operation(s, result_type, node, position, .Bit_Xor)

	case .Bit_And:
		return analyze_bitwise_operation(s, result_type, node, position, .Bit_And)

	case .Bit_Shl:
		return analyze_bitwise_operation(s, result_type, node, position, .Bit_Shl)

	case .Bit_Shr:
		return analyze_bitwise_operation(s, result_type, node, position, .Bit_Shr)

	case .Eql:
		return analyze_equality_operation(s, result_type, node, position, .Eql)

	case .Neq:
		return analyze_equality_operation(s, result_type, node, position, .Neq)

	case .Lt:
		return analyze_ordering_operation(s, result_type, node, position, .Lt)

	case .Lte:
		return analyze_ordering_operation(s, result_type, node, position, .Lte)

	case .Gt:
		return analyze_ordering_operation(s, result_type, node, position, .Gt)

	case .Gte:
		return analyze_ordering_operation(s, result_type, node, position, .Gte)

	case .Unsigned_Int_Type:
		return analyze_primitive_type(s, result_type, position, .Unsigned_Int, Ir_Index(node.a))

	case .Signed_Int_Type:
		return analyze_primitive_type(s, result_type, position, .Signed_Int, Ir_Index(node.a))

	case .Float16_Type:
		return analyze_primitive_type(s, result_type, position, .Float, 16)

	case .Float32_Type:
		return analyze_primitive_type(s, result_type, position, .Float, 32)

	case .Float64_Type:
		return analyze_primitive_type(s, result_type, position, .Float, 64)

	case .Bool_Type:
		return analyze_primitive_type(s, result_type, position, .Bool)

	case .Void_Type:
		return analyze_primitive_type(s, result_type, position, .Void)

	case .Function_Type:
		return analyze_function_type(s, result_type, node, position)

	case:
		sema_error(position, "unhandled expression: %v", node.tag)

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
		if local.constant {
			local_value := s.ir.values[local.value]
			local_type_id := local_value.type
			local_type := s.ir.types[local_type_id]

			if result_type_id != IR_INVALID {
				if is_untyped_type(local_type) {
					if !can_cast_untyped_value(s, position, local.value, result_type_id) {
						return IR_INVALID
					}

					local_value.type = result_type_id

					return append_value_with_struct(s, local_value)
				}

				if !check_type_compatibility(s, position, local_type_id, result_type_id) {
					return IR_INVALID
				}
			}

			return local.value
		} else {
			pointer_type := s.ir.types[s.ir.values[local.value].type]

			assert(pointer_type.tag == .Single_Pointer)

			local_type := pointer_type.a

			if result_type_id != IR_INVALID {
				if !check_type_compatibility(s, position, local_type, result_type_id) {
					return IR_INVALID
				}
			}

			return append_value(s, local_type, .Load, local.value, 0)
		}

	}

	if binding, ok := &s.globals[name]; ok {
		if binding.state == .In_Progress {
			sema_error(position, "cyclic reference because of using '%s'", name)

			return IR_INVALID
		} else if binding.state == .Hoisted && !analyze_global_binding(s, binding) {
			return IR_INVALID
		}

		assert(binding.state == .Analyzed)

		binding_value := s.ir.values[binding.value]
		binding_type := s.ir.types[binding_value.type]

		if result_type_id != IR_INVALID {
			if is_untyped_type(binding_type) {
				if !can_cast_untyped_value(s, position, binding.value, result_type_id) {
					return IR_INVALID
				}

				binding_value.type = result_type_id

				return append_value_with_struct(s, binding_value)
			}

			if !check_type_compatibility(s, position, binding_value.type, result_type_id) {
				return IR_INVALID
			}
		}

		return binding.value
	}

	sema_error(position, "undeclared name: %s", name)

	return IR_INVALID
}

analyze_string :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	u8_type := intern_type(s, .Unsigned_Int, 8, 0)
	string_type := intern_type(s, .Slice, u8_type, 0)

	if result_type_id != IR_INVALID &&
	   !check_type_compatibility(s, position, string_type, result_type_id) {
		return IR_INVALID
	}

	index := len(s.ir.strings)

	append(&s.ir.strings, ..s.ast.strings[node.a:][:node.b])

	count := node.b

	return append_value(s, string_type, .String, Ir_Index(index), Ir_Index(count))
}

analyze_int :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	v := extract_int_value(node)

	if result_type_id == IR_INVALID {
		return append_int_value(s, intern_type(s, .Untyped_Int, 0, 0), v)
	}

	result_type := s.ir.types[result_type_id]

	if is_float_type(result_type) {
		if !can_fit_into_float_type(position, v, result_type) do return IR_INVALID

		return append_float_value(s, result_type_id, f64(v))
	} else if !is_int_type(result_type) {
		sema_error(
			position,
			"did not expect an integer, expected '%s' value",
			type_to_string_temp(s, result_type_id),
		)

		return IR_INVALID
	}

	if !can_fit_into_int_type(position, v, result_type) do return IR_INVALID

	return append_int_value(s, result_type_id, v)
}

analyze_float :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	v := extract_float_value(node)

	if result_type_id == IR_INVALID {
		return append_float_value(s, intern_type(s, .Untyped_Float, 0, 0), v)
	}

	result_type := s.ir.types[result_type_id]

	if is_int_type(result_type) {
		if !can_fit_into_int_type(position, v, result_type) do return IR_INVALID

		return append_int_value(s, result_type_id, u64(v))
	} else if !is_float_type(result_type) {
		sema_error(
			position,
			"did not expect a float, expected '%s' value",
			type_to_string_temp(s, result_type_id),
		)

		return IR_INVALID
	}

	if !can_fit_into_float_type(position, v, result_type) do return IR_INVALID

	return append_float_value(s, result_type_id, v)
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

analyze_bool_not :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	bool_type := intern_type(s, .Bool, 0, 0)

	if result_type_id != IR_INVALID && !check_type_compatibility(s, position, bool_type, result_type_id) do return IR_INVALID

	value := analyze_expr(s, bool_type, node.b)

	if value == IR_INVALID do return IR_INVALID

	return append_value(s, bool_type, .Bool_Not, value, 0)
}

analyze_bit_not :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	if result_type_id != IR_INVALID && !is_int_type(s.ir.types[result_type_id]) {
		sema_error(
			position,
			"did not expect an integer, expected '%s' value",
			type_to_string_temp(s, result_type_id),
		)

		return IR_INVALID
	}

	value := analyze_expr(s, result_type_id, node.b)

	if value == IR_INVALID do return IR_INVALID

	value_type_id := s.ir.values[value].type

	value_type := s.ir.types[value_type_id]

	if is_untyped_type(value_type) {
		sema_error(position, "bitwise not can not work on untyped values")

		return IR_INVALID
	}

	if !is_int_type(value_type) {
		sema_error(
			position,
			"expected an integer value, but got '%s' value",
			type_to_string_temp(s, value_type_id),
		)

		return IR_INVALID
	}

	return append_value(s, value_type_id, .Bit_Not, value, 0)
}

analyze_negate :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	if result_type_id != IR_INVALID {
		result_type := s.ir.types[result_type_id]

		if !is_int_type(result_type) && !is_float_type(result_type) {
			sema_error(
				position,
				"did not expect a number, expected '%s' value",
				type_to_string_temp(s, result_type_id),
			)

			return IR_INVALID
		}
	}

	value_id := analyze_expr(s, result_type_id, node.b)

	if value_id == IR_INVALID do return IR_INVALID

	value_type_id := s.ir.values[value_id].type

	value_type := s.ir.types[value_type_id]

	if !is_int_type(value_type) && !is_float_type(value_type) {
		sema_error(
			position,
			"expected a number value, but got '%s' value",
			type_to_string_temp(s, value_type_id),
		)

		return IR_INVALID
	}

	if !is_float_type(value_type) && value_type.tag != .Signed_Int {
		sema_error(position, "can not negate an unsigned value")

		return IR_INVALID
	}

	return append_value(s, value_type_id, .Negate, value_id, 0)
}

perform_arithmetic_operation :: proc(
	s: ^Sema,
	position: Position,
	op_tag: Ir_Value_Tag,
	lhs_id: Ir_Index,
	rhs_id: Ir_Index,
) -> Ir_Index {
	lhs := s.ir.values[lhs_id]
	rhs := s.ir.values[rhs_id]

	lhs_type_id := lhs.type
	rhs_type_id := rhs.type

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	if lhs.tag == .Int && rhs.tag == .Int {
		lhs := extract_int_value(lhs)
		rhs := extract_int_value(rhs)

		result: u64

		#partial switch op_tag {
		case .Add:
			result = lhs + rhs

		case .Sub:
			result = lhs - rhs

		case .Mul:
			result = lhs * rhs

		case .Div:
			result = lhs / rhs

		case .Mod:
			result = lhs % rhs
		}

		return append_int_value(s, lhs_type_id, result)
	} else if lhs.tag == .Float && rhs.tag == .Float {
		lhs := extract_float_value(lhs)
		rhs := extract_float_value(rhs)

		result: f64

		#partial switch op_tag {
		case .Add:
			result = lhs + rhs

		case .Sub:
			result = lhs - rhs

		case .Mul:
			result = lhs * rhs

		case .Div:
			result = lhs / rhs

		case .Mod:
			unreachable()
		}

		return append_float_value(s, lhs_type_id, result)
	} else {
		return append_value(s, lhs_type_id, op_tag, lhs_id, rhs_id)
	}
}

unify_binary_types :: proc(
	s: ^Sema,
	position: Position,
	lhs_id: ^Ir_Index,
	rhs_id: ^Ir_Index,
) -> (
	lhs_type_id: Ir_Index,
	rhs_type_id: Ir_Index,
	ok: bool,
) {
	lhs := s.ir.values[lhs_id^]
	rhs := s.ir.values[rhs_id^]

	lhs_type_id = lhs.type
	rhs_type_id = rhs.type

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	if is_untyped_type(lhs_type) && !is_untyped_type(rhs_type) {
		if !can_cast_untyped_value(s, position, lhs_id^, rhs_type_id) do return {}, {}, false

		lhs.type = rhs_type_id

		lhs_id^ = append_value_with_struct(s, lhs)

		return rhs_type_id, rhs_type_id, true
	} else if is_untyped_type(rhs_type) && !is_untyped_type(lhs_type) {
		if !can_cast_untyped_value(s, position, rhs_id^, lhs_type_id) do return {}, {}, false

		rhs.type = lhs_type_id

		rhs_id^ = append_value_with_struct(s, rhs)

		return lhs_type_id, lhs_type_id, true
	} else if is_untyped_type(lhs_type) && is_untyped_type(rhs_type) {
		if lhs_type.tag == .Untyped_Float || rhs_type.tag == .Untyped_Float {
			uf := intern_type(s, .Untyped_Float, 0, 0)

			if lhs.tag == .Int {
				lhs_id^ = append_float_value(s, uf, f64(extract_int_value(lhs)))
			}

			if rhs.tag == .Int {
				rhs_id^ = append_float_value(s, uf, f64(extract_int_value(rhs)))
			}

			return uf, uf, true
		}

		return lhs_type_id, rhs_type_id, true
	}

	if !check_type_compatibility(s, position, lhs_type_id, rhs_type_id) do return {}, {}, false

	return lhs_type_id, rhs_type_id, true
}

analyze_arithmetic_operation :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	op_tag: Ir_Value_Tag,
) -> Ir_Index {
	if result_type_id != IR_INVALID {
		result_type := s.ir.types[result_type_id]

		if !is_int_type(result_type) && !is_float_type(result_type) {
			sema_error(
				position,
				"did not expect a number, expected '%s' value",
				type_to_string_temp(s, result_type_id),
			)

			return IR_INVALID
		}
	}

	lhs_id := analyze_expr(s, result_type_id, node.a)
	rhs_id := analyze_expr(s, result_type_id, node.b)

	if lhs_id == IR_INVALID || rhs_id == IR_INVALID do return IR_INVALID

	lhs_type_id, rhs_type_id, ok := unify_binary_types(s, position, &lhs_id, &rhs_id)

	if !ok do return IR_INVALID

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	if !is_int_type(lhs_type) && !is_float_type(lhs_type) {
		sema_error(
			position,
			"expected a number value, but got '%s' value",
			type_to_string_temp(s, lhs_type_id),
		)

		return IR_INVALID
	}

	if !is_int_type(rhs_type) && !is_float_type(rhs_type) {
		sema_error(
			position,
			"expected a number value, but got '%s' value",
			type_to_string_temp(s, rhs_type_id),
		)

		return IR_INVALID
	}

	if op_tag == .Mod && (is_float_type(lhs_type) || is_float_type(rhs_type)) {
		sema_error(position, "operation '%%' can only performed on integers")

		return IR_INVALID
	}

	return perform_arithmetic_operation(s, position, op_tag, lhs_id, rhs_id)
}

analyze_bitwise_operation :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	op_tag: Ir_Value_Tag,
) -> Ir_Index {
	if result_type_id != IR_INVALID {
		result_type := s.ir.types[result_type_id]

		if !is_int_type(result_type) {
			sema_error(
				position,
				"did not expect an integer, expected '%s' value",
				type_to_string_temp(s, result_type_id),
			)

			return IR_INVALID
		}
	}

	lhs_id := analyze_expr(s, result_type_id, node.a)
	rhs_id := analyze_expr(s, result_type_id, node.b)

	if lhs_id == IR_INVALID || rhs_id == IR_INVALID do return IR_INVALID

	lhs_type_id, rhs_type_id, ok := unify_binary_types(s, position, &lhs_id, &rhs_id)

	if !ok do return IR_INVALID

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	if !is_int_type(lhs_type) {
		sema_error(
			position,
			"expected an integer value, but got '%s' value",
			type_to_string_temp(s, lhs_type_id),
		)

		return IR_INVALID
	}

	if !is_int_type(rhs_type) {
		sema_error(
			position,
			"expected an integer value, but got '%s' value",
			type_to_string_temp(s, rhs_type_id),
		)

		return IR_INVALID
	}

	return append_value(s, lhs_type_id, op_tag, lhs_id, rhs_id)
}


analyze_equality_operation :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	op_tag: Ir_Value_Tag,
) -> Ir_Index {
	if result_type_id != IR_INVALID {
		result_type := s.ir.types[result_type_id]

		if result_type.tag != .Bool {
			sema_error(
				position,
				"did not expect a boolean, expected '%s' value",
				type_to_string_temp(s, result_type_id),
			)

			return IR_INVALID
		}
	}

	bool_type := intern_type(s, .Bool, 0, 0)

	lhs_id := analyze_expr(s, IR_INVALID, node.a)
	rhs_id := analyze_expr(s, IR_INVALID, node.b)

	if lhs_id == IR_INVALID || rhs_id == IR_INVALID do return IR_INVALID

	lhs_type_id, rhs_type_id, ok := unify_binary_types(s, position, &lhs_id, &rhs_id)

	if !ok do return IR_INVALID

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	can_perform_equality :: proc(type: Ir_Type) -> bool {
		switch (type.tag) {
		case .Unsigned_Int,
		     .Signed_Int,
		     .Untyped_Int,
		     .Untyped_Float,
		     .Float,
		     .Bool,
		     .Single_Pointer,
		     .Multi_Pointer:
			return true

		case .Slice, .Array, .Type, .Function, .Void:
			return false

		case:
			return false
		}
	}

	if !can_perform_equality(lhs_type) {
		sema_error(
			position,
			"can not perform equality operation on '%s' value",
			type_to_string_temp(s, lhs_type_id),
		)

		return IR_INVALID
	}

	if !can_perform_equality(rhs_type) {
		sema_error(
			position,
			"can not perform equality operation on '%s' value",
			type_to_string_temp(s, rhs_type_id),
		)

		return IR_INVALID
	}

	return append_value(s, bool_type, op_tag, lhs_id, rhs_id)
}

analyze_ordering_operation :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	op_tag: Ir_Value_Tag,
) -> Ir_Index {
	if result_type_id != IR_INVALID {
		result_type := s.ir.types[result_type_id]

		if result_type.tag != .Bool {
			sema_error(
				position,
				"did not expect a boolean, expected '%s' value",
				type_to_string_temp(s, result_type_id),
			)

			return IR_INVALID
		}
	}

	bool_type := intern_type(s, .Bool, 0, 0)

	lhs_id := analyze_expr(s, IR_INVALID, node.a)
	rhs_id := analyze_expr(s, IR_INVALID, node.b)

	if lhs_id == IR_INVALID || rhs_id == IR_INVALID do return IR_INVALID

	lhs_type_id, rhs_type_id, ok := unify_binary_types(s, position, &lhs_id, &rhs_id)

	if !ok do return IR_INVALID

	lhs_type := s.ir.types[lhs_type_id]
	rhs_type := s.ir.types[rhs_type_id]

	if !is_int_type(lhs_type) && !is_float_type(lhs_type) {
		sema_error(
			position,
			"expected a number value, but got '%s' value",
			type_to_string_temp(s, lhs_type_id),
		)

		return IR_INVALID
	}

	if !is_int_type(rhs_type) && !is_float_type(rhs_type) {
		sema_error(
			position,
			"expected a number value, but got '%s' value",
			type_to_string_temp(s, rhs_type_id),
		)

		return IR_INVALID
	}

	return append_value(s, bool_type, op_tag, lhs_id, rhs_id)
}

analyze_primitive_type :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	position: Position,
	tag: Ir_Type_Tag,
	a: Ir_Index = 0,
	b: Ir_Index = 0,
) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID &&
	   !check_type_compatibility(s, position, type_meta, result_type_id) {
		return IR_INVALID
	}

	return append_value(s, type_meta, .Type, intern_type(s, tag, a, b), 0)
}

analyze_function_type :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	type_meta := intern_type(s, .Type, 0, 0)

	if result_type_id != IR_INVALID &&
	   !check_type_compatibility(s, position, type_meta, result_type_id) {
		return IR_INVALID
	}

	parameters_node := s.ast.nodes[node.a]

	parameter_nodes_base := parameters_node.a
	parameter_nodes_len := parameters_node.b

	parameter_types := make([dynamic]Ir_Index)

	defer delete(parameter_types)

	if parameters_node.tag == .Function_Named_Parameters {
		seen := make(map[string]Position)
		defer delete(seen)

		for i in 0 ..< parameter_nodes_len {
			parameter_name_node_id := s.ast.extra[parameter_nodes_base + i * 2]

			parameter_name_node := s.ast.nodes[parameter_name_node_id]
			parameter_name_position := s.ast.positions[parameter_name_node_id]

			parameter_name := string(s.ast.strings[parameter_name_node.a:][:parameter_name_node.b])

			if existing_position, ok := seen[parameter_name]; ok {
				sema_redeclaration_error(
					parameter_name_position,
					existing_position,
					parameter_name,
				)

				return IR_INVALID
			} else {
				seen[parameter_name] = parameter_name_position
			}

			parameter_type_node_id := s.ast.extra[parameter_nodes_base + i * 2 + 1]

			parameter_type_value := analyze_expr(s, type_meta, parameter_type_node_id)

			if parameter_type_value == IR_INVALID do return IR_INVALID

			append(&parameter_types, unchecked_value_as_type(s, parameter_type_value))
		}
	} else {
		for i in 0 ..< parameter_nodes_len {
			parameter_type_value := analyze_expr(
				s,
				type_meta,
				s.ast.extra[parameter_nodes_base + i],
			)

			if parameter_type_value == IR_INVALID do return IR_INVALID

			append(&parameter_types, unchecked_value_as_type(s, parameter_type_value))
		}
	}

	parameters_index := len(s.ir.extra)

	append(&s.ir.extra, Ir_Index(len(parameter_types)))
	append(&s.ir.extra, ..parameter_types[:])

	return_type_value := analyze_expr(s, type_meta, node.b)

	if return_type_value == IR_INVALID do return IR_INVALID

	function_type := intern_type(
		s,
		.Function,
		Ir_Index(parameters_index),
		unchecked_value_as_type(s, return_type_value),
	)

	return append_value(s, type_meta, .Type, function_type, 0)
}

analyze_call :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
) -> Ir_Index {
	callee_value_id := analyze_expr(s, IR_INVALID, node.a)

	if callee_value_id == IR_INVALID do return IR_INVALID

	callee_value := s.ir.values[callee_value_id]

	callee_type_id := callee_value.type

	callee_type := s.ir.types[callee_type_id]

	if callee_type.tag == .Single_Pointer {
		pointer_callee_type_id := callee_type_id

		callee_type_id := callee_type.a

		callee_type := s.ir.types[callee_type_id]

		if callee_type.tag != .Function {
			sema_error(
				position,
				"can not call a '%s' value",
				type_to_string_temp(s, pointer_callee_type_id),
			)

			return IR_INVALID
		}
	} else if callee_type.tag != .Function {
		sema_error(position, "can not call a '%s' value", type_to_string_temp(s, callee_type_id))

		return IR_INVALID
	}

	callee_parameters_base := callee_type.a + 1
	callee_parameters_count := u32(s.ir.extra[callee_type.a])

	call_arguments_node := s.ast.nodes[node.b]

	call_arguments_base := call_arguments_node.a
	call_arguments_count := u32(call_arguments_node.b)

	if callee_parameters_count != call_arguments_count {
		sema_error(
			position,
			"expected '%v' argument(s), but got '%v'",
			callee_parameters_count,
			call_arguments_count,
		)

		return IR_INVALID
	}

	call_arguments := make([dynamic]Ir_Index)

	for i in 0 ..< call_arguments_count {
		callee_parameter_type := s.ir.extra[callee_parameters_base + Ir_Index(i)]
		call_argument_id := s.ast.extra[call_arguments_base + Ast_Index(i)]

		call_argument := analyze_expr(s, callee_parameter_type, call_argument_id)

		if call_argument == IR_INVALID do return IR_INVALID

		append(&call_arguments, call_argument)
	}

	call_arguments_index := len(s.ir.extra)

	append(&s.ir.extra, Ir_Index(call_arguments_count))
	append(&s.ir.extra, ..call_arguments[:])

	return append_value(s, callee_type.b, .Call, callee_value_id, Ir_Index(call_arguments_index))
}

analyze_function :: proc(
	s: ^Sema,
	result_type_id: Ir_Index,
	node: Ast_Node,
	position: Position,
	name: Maybe(string),
) -> Ir_Index {
	function_type_node := s.ast.nodes[node.a]

	parameters_node := s.ast.nodes[function_type_node.a]

	function_type_value := analyze_function_type(s, IR_INVALID, function_type_node, position)

	function_type_id := unchecked_value_as_type(s, function_type_value)

	function_type := s.ir.types[function_type_id]

	if result_type_id != IR_INVALID &&
	   !check_type_compatibility(s, position, function_type_id, result_type_id) {
		return IR_INVALID
	}

	name := Token {
		tag      = .Identifier,
		value    = name == nil ? fmt.tprintf("way_anonymous_function::%v", rand.uint128()) : name.(string),
		position = position,
	}

	old_function := s.function
	old_scope := s.scope
	old_block := s.block

	function_id := Ir_Index(len(s.ir.functions))

	s.function = function_id
	s.scope = make_scope(nil)
	s.block = IR_INVALID

	append(&s.ir.functions, Ir_Function{type = function_type_id, name = name})

	parameter_nodes_base := parameters_node.a
	parameter_nodes_len := parameters_node.b

	if parameters_node.tag != .Function_Named_Parameters && parameter_nodes_len > 0 {
		sema_error(position, "function with a body must have named parameters")

		return IR_INVALID
	}

	for i in 0 ..< parameter_nodes_len {
		parameter_name_node_id := s.ast.extra[parameter_nodes_base + i * 2]

		parameter_name_node := s.ast.nodes[parameter_name_node_id]
		parameter_name_position := s.ast.positions[parameter_name_node_id]

		parameter_name := string(s.ast.strings[parameter_name_node.a:][:parameter_name_node.b])

		parameter_type_id := s.ir.extra[function_type.a + 1 + Ir_Index(i)]

		parameter_value := append_value(s, parameter_type_id, .Parameter, Ir_Index(i), 0)

		scope_add(&s.scope, parameter_name, parameter_value, true, position)
	}

	if !analyze_block(s, s.ast.nodes[node.b], position) do return IR_INVALID

	if !ends_with_terminator(s) {
		function_type := s.ir.types[function_type_id]

		function_return_type_id := function_type.b

		function_return_type := s.ir.types[function_return_type_id]

		if function_return_type.tag == .Void {
			if s.block == IR_INVALID {
				new_block(s)
			}

			append_instruction(s, .Return, IR_INVALID, 0)
		} else {
			sema_error(
				position,
				"function did not return a value of type '%s'",
				type_to_string_temp(s, function_return_type_id),
			)

			return IR_INVALID
		}
	}

	function := &s.ir.functions[function_id]

	s.function = old_function
	s.block = old_block
	s.scope = old_scope

	return append_value(s, function_type_id, .Function, function_id, 0)
}

ends_with_terminator :: proc(s: ^Sema) -> bool {
	function := s.ir.functions[s.function]

	block := function.blocks[s.block]

	if len(block.instructions) == 0 do return false

	last_instruction := block.instructions[len(block.instructions) - 1]

	switch last_instruction.tag {
	case .Return, .Branch, .Conditional_Branch, .Unreachable:
		return true

	case .Value, .Store:
		return false

	case:
		return false
	}
}

new_block :: proc(s: ^Sema) -> Ir_Index {
	function := &s.ir.functions[s.function]

	new_block_id := Ir_Index(len(function.blocks))

	append(&function.blocks, Ir_Block{})

	if s.block != IR_INVALID {
		if !ends_with_terminator(s) {
			append_instruction(s, .Branch, new_block_id, 0)
		}
	}

	s.block = new_block_id

	return new_block_id
}

analyze_block :: proc(s: ^Sema, node: Ast_Node, position: Position) -> bool {
	block_id := new_block(s)

	old_scope := s.scope

	s.scope = make_scope(&old_scope)

	stmts := s.ast.extra[node.a:][:node.b]

	for stmt in stmts {
		analyze_stmt(s, stmt) or_return
	}

	delete(s.scope.locals)

	s.scope = old_scope

	return true
}

analyze_stmt :: proc(s: ^Sema, node_id: Ast_Index) -> bool {
	node := s.ast.nodes[node_id]
	position := s.ast.positions[node_id]

	#partial switch node.tag {
	case .Block:
		return analyze_block(s, node, position)

	case .Return:
		return analyze_return(s, node, position)

	case .Variable:
		return analyze_local_binding(s, node, position, false)

	case .Constant:
		return analyze_local_binding(s, node, position, true)

	case .If, .While, .For, .Break, .Continue:
		sema_error(position, "unhandled statement: %v", node.tag)

		return false

	case:
		value := analyze_expr(s, IR_INVALID, node_id)

		if value == IR_INVALID do return false

		append_instruction(s, .Value, value, 0)

		return true
	}
}

analyze_local_binding :: proc(
	s: ^Sema,
	node: Ast_Node,
	position: Position,
	constant: bool,
) -> bool {
	identifier := s.ast.nodes[s.ast.extra[node.a]]

	name := string(s.ast.strings[identifier.a:][:identifier.b])

	explicit_type := IR_INVALID

	explicit_type_node_id := s.ast.extra[node.a + 1]

	if explicit_type_node_id != AST_INVALID {
		type_meta := intern_type(s, .Type, 0, 0)
		type_value := analyze_expr(s, type_meta, explicit_type_node_id)

		if type_value == IR_INVALID do return false

		explicit_type = unchecked_value_as_type(s, type_value)
	}

	initializer_node_id := node.b

	initializer := IR_INVALID

	if initializer_node_id != AST_INVALID {
		initializer = analyze_expr(s, explicit_type, initializer_node_id)

		if initializer == IR_INVALID do return false

		if !constant {

		}
	} else {
		assert(explicit_type != IR_INVALID)

		initializer = append_value(s, explicit_type, .Zero, 0, 0)
	}

	assert(initializer != IR_INVALID)

	if constant {
		if !is_const_value(s, initializer) {
			sema_error(position, "expected a compile-time known constant value")

			return false
		}

		scope_add(&s.scope, name, initializer, constant, position)
	} else {
		initializer_type_id := s.ir.values[initializer].type

		initializer_type := s.ir.types[initializer_type_id]

		if initializer_type.tag == .Untyped_Int {
			sema_error(
				position,
				"please specify a type for your integer variable, the compiler can't decide on its own",
			)

			return false
		} else if initializer_type.tag == .Untyped_Float {
			sema_error(
				position,
				"please specify a type for your float variable, the compiler can't decide on its own",
			)

			return false
		}

		pointer_type := intern_type(s, .Single_Pointer, initializer_type_id, 0)
		alloca := append_value(s, pointer_type, .Alloca, initializer_type_id, 0)

		append_instruction(s, .Value, alloca, 0)
		append_instruction(s, .Store, alloca, initializer)

		scope_add(&s.scope, name, alloca, constant, position)
	}

	return true
}

analyze_return :: proc(s: ^Sema, node: Ast_Node, position: Position) -> bool {
	assert(s.function != IR_INVALID)

	function := s.ir.functions[s.function]

	function_type_id := function.type

	function_type := s.ir.types[function_type_id]

	assert(function_type.tag == .Function)

	return_type_id := function_type.b

	return_type := s.ir.types[return_type_id]

	if return_type.tag == .Void {
		if node.b != AST_INVALID {
			sema_error(
				position,
				"function of type '%s' should not return a value (return type is 'void')",
				type_to_string_temp(s, function.type),
			)

			return false
		}

		append_instruction(s, .Return, IR_INVALID, 0)
	} else {
		if node.b == AST_INVALID {
			sema_error(
				position,
				"function of type '%s' should return a value (return type is not 'void', it is '%s')",
				type_to_string_temp(s, function.type),
				type_to_string_temp(s, return_type_id),
			)

			return false
		}

		return_value := analyze_expr(s, return_type_id, node.b)

		if return_value == IR_INVALID do return false

		append_instruction(s, .Return, return_value, 0)
	}

	return true
}
