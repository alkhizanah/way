package main

import "core:fmt"
import "core:strings"
import "core:unicode"

Transpiler :: struct {
	ir:     Ir,
	output: strings.Builder,
}

transpiler_init :: proc(t: ^Transpiler, ir: Ir) {
	t.ir = ir

	strings.builder_init(&t.output)
}

transpile :: proc(t: ^Transpiler) {
	fmt.sbprintln(&t.output, "#include <stddef.h>")
	fmt.sbprintln(&t.output, "#include <stdbool.h>")
	fmt.sbprintln(&t.output, "#include <stdint.h>")
	fmt.sbprintln(&t.output, "")
	fmt.sbprintln(&t.output, "struct _way_slice {")
	fmt.sbprintln(&t.output, "	void *ptr;")
	fmt.sbprintln(&t.output, "	size_t len;")
	fmt.sbprintln(&t.output, "};")

	for binding in t.ir.globals {
		fmt.sbprintln(&t.output, "")
		transpile_type(t, t.ir.values[binding.value].type)
		fmt.sbprintf(&t.output, " %v = ", binding.name.value)
		transpile_value(t, binding.value)
		fmt.sbprintln(&t.output, ";")
	}
}

transpile_value :: proc(t: ^Transpiler, value_id: Ir_Index) {
	value := t.ir.values[value_id]

	if !is_untyped_type(t.ir.types[value.type]) {

		fmt.sbprint(&t.output, "(")
		transpile_type(t, value.type)
		fmt.sbprint(&t.output, ")")
	}

	fmt.sbprint(&t.output, "(")

	#partial switch value.tag {
	case .Int:
		fmt.sbprintf(&t.output, "%v", extract_int_value(value))

	case .Float:
		fmt.sbprintf(&t.output, "%v", extract_float_value(value))

	case .Bool:
		fmt.sbprintf(&t.output, "%v", value.a == 0 ? "false" : "true")

	case .Null:
		fmt.sbprint(&t.output, "(void*)(0)")

	case .String:
		fmt.sbprint(&t.output, "(struct _way_slice){ .ptr = (uint8_t[]){")

		for byte in t.ir.strings[value.a:][:value.b] {
			if unicode.is_print(rune(byte)) {
				fmt.sbprintf(&t.output, "'%c', ", byte)
			} else {
				fmt.sbprintf(&t.output, "%v, ", byte)
			}
		}

		fmt.sbprintf(&t.output, "}}, .len = %v }}", value.b)

	case .Negate, .Bool_Not, .Bit_Not:
		#partial switch value.tag {
		case .Negate:
			fmt.sbprint(&t.output, "-")

		case .Bool_Not:
			fmt.sbprint(&t.output, "!")

		case .Bit_Not:
			fmt.sbprint(&t.output, "~")
		}

		transpile_value(t, value.a)

	case .Add,
	     .Sub,
	     .Mul,
	     .Div,
	     .Mod,
	     .Bit_Or,
	     .Bit_And,
	     .Bit_Shl,
	     .Bit_Shr,
	     .Bit_Xor,
	     .Eql,
	     .Neq,
	     .Lt,
	     .Lte,
	     .Gt,
	     .Gte:
		transpile_value(t, value.a)

		#partial switch value.tag {
		case .Add:
			fmt.sbprint(&t.output, " + ")

		case .Sub:
			fmt.sbprint(&t.output, " - ")

		case .Mul:
			fmt.sbprint(&t.output, " * ")

		case .Div:
			fmt.sbprint(&t.output, " / ")

		case .Mod:
			fmt.sbprint(&t.output, " % ")

		case .Bit_Or:
			fmt.sbprint(&t.output, " | ")

		case .Bit_And:
			fmt.sbprint(&t.output, " & ")

		case .Bit_Shl:
			fmt.sbprint(&t.output, " << ")

		case .Bit_Shr:
			fmt.sbprint(&t.output, " >> ")

		case .Bit_Xor:
			fmt.sbprint(&t.output, " ^ ")

		case .Eql:
			fmt.sbprint(&t.output, " == ")

		case .Neq:
			fmt.sbprint(&t.output, " != ")

		case .Lt:
			fmt.sbprint(&t.output, " < ")

		case .Lte:
			fmt.sbprint(&t.output, " <= ")

		case .Gt:
			fmt.sbprint(&t.output, " > ")

		case .Gte:
			fmt.sbprint(&t.output, " >= ")
		}

		transpile_value(t, value.b)

	case:
		fmt.sbprint(&t.output, "/* todo */")
	}

	fmt.sbprint(&t.output, ")")
}

transpile_type :: proc(t: ^Transpiler, type_id: Ir_Index) {
	type := t.ir.types[type_id]

	switch type.tag {
	case .Void:
		fmt.sbprint(&t.output, "void")

	case .Bool:
		fmt.sbprint(&t.output, "bool")

	case .Signed_Int:
		switch type.a {
		case 8, 16, 32, 64:
			fmt.sbprintf(&t.output, "int%v_t", type.a)

		case:
			fmt.sbprintf(&t.output, "_BitInt(%v)", type.a)
		}

	case .Unsigned_Int:
		switch type.a {
		case 8, 16, 32, 64:
			fmt.sbprintf(&t.output, "uint%v_t", type.a)

		case:
			fmt.sbprintf(&t.output, "unsigned _BitInt(%v)", type.a)
		}

	case .Float:
		switch type.a {
		case 16:
			fmt.sbprint(&t.output, "_Float16")
		case 32:
			fmt.sbprint(&t.output, "float")
		case 64:
			fmt.sbprint(&t.output, "double")
		}

	case .Untyped_Int, .Untyped_Float:
		fmt.sbprint(&t.output, "/* untyped type */")

	case .Type:
		fmt.sbprint(&t.output, "/* type of a type */")

	case .Single_Pointer:
	case .Multi_Pointer:
		transpile_type(t, type.a)
		fmt.sbprint(&t.output, "*")

	case .Slice:
		fmt.sbprint(&t.output, "struct _way_slice")

	case .Array:
	case .Function:
		fmt.sbprint(&t.output, "/* todo */")
	}
}
