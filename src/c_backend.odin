package main

import "core:fmt"
import "core:strings"
import "core:unicode"

C_Backend :: struct {
	ir:     Ir,
	output: strings.Builder,
}

c_init :: proc(c: ^C_Backend, ir: Ir) {
	c.ir = ir

	strings.builder_init(&c.output)
}

c_start :: proc(c: ^C_Backend) {
	fmt.sbprintln(&c.output, "#include <stddef.h>")
	fmt.sbprintln(&c.output, "#include <stdbool.h>")
	fmt.sbprintln(&c.output, "#include <stdint.h>")
	fmt.sbprintln(&c.output, "")
	fmt.sbprintln(&c.output, "struct _way_slice {")
	fmt.sbprintln(&c.output, "	void *ptr;")
	fmt.sbprintln(&c.output, "	size_t len;")
	fmt.sbprintln(&c.output, "};")

	for binding in c.ir.globals {
		fmt.sbprintln(&c.output, "")
		c_compiler_type(c, c.ir.values[binding.value].type)
		fmt.sbprintf(&c.output, " %v = ", binding.name.value)
		c_compile_value(c, binding.value)
		fmt.sbprintln(&c.output, ";")
	}
}

c_compile_value :: proc(c: ^C_Backend, value_id: Ir_Index) {
	value := c.ir.values[value_id]

	if !is_untyped_type(c.ir.types[value.type]) {
		fmt.sbprint(&c.output, "(")
		c_compiler_type(c, value.type)
		fmt.sbprint(&c.output, ")")
	}

	fmt.sbprint(&c.output, "(")

	#partial switch value.tag {
	case .Int:
		fmt.sbprintf(&c.output, "%v", extract_int_value(value))

	case .Float:
		fmt.sbprintf(&c.output, "%v", extract_float_value(value))

	case .Bool:
		fmt.sbprintf(&c.output, "%v", value.a == 0 ? "false" : "true")

	case .Null:
		fmt.sbprint(&c.output, "(void*)(0)")

	case .String:
		fmt.sbprint(&c.output, "(struct _way_slice){ .ptr = (uint8_t[]){")

		for byte in c.ir.strings[value.a:][:value.b] {
			if unicode.is_print(rune(byte)) {
				fmt.sbprintf(&c.output, "'%c', ", byte)
			} else {
				fmt.sbprintf(&c.output, "%v, ", byte)
			}
		}

		fmt.sbprintf(&c.output, "}}, .len = %v }}", value.b)

	case .Negate, .Bool_Not, .Bit_Not:
		#partial switch value.tag {
		case .Negate:
			fmt.sbprint(&c.output, "-")

		case .Bool_Not:
			fmt.sbprint(&c.output, "!")

		case .Bit_Not:
			fmt.sbprint(&c.output, "~")
		}

		c_compile_value(c, value.a)

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
		c_compile_value(c, value.a)

		#partial switch value.tag {
		case .Add:
			fmt.sbprint(&c.output, " + ")

		case .Sub:
			fmt.sbprint(&c.output, " - ")

		case .Mul:
			fmt.sbprint(&c.output, " * ")

		case .Div:
			fmt.sbprint(&c.output, " / ")

		case .Mod:
			fmt.sbprint(&c.output, " % ")

		case .Bit_Or:
			fmt.sbprint(&c.output, " | ")

		case .Bit_And:
			fmt.sbprint(&c.output, " & ")

		case .Bit_Shl:
			fmt.sbprint(&c.output, " << ")

		case .Bit_Shr:
			fmt.sbprint(&c.output, " >> ")

		case .Bit_Xor:
			fmt.sbprint(&c.output, " ^ ")

		case .Eql:
			fmt.sbprint(&c.output, " == ")

		case .Neq:
			fmt.sbprint(&c.output, " != ")

		case .Lt:
			fmt.sbprint(&c.output, " < ")

		case .Lte:
			fmt.sbprint(&c.output, " <= ")

		case .Gt:
			fmt.sbprint(&c.output, " > ")

		case .Gte:
			fmt.sbprint(&c.output, " >= ")
		}

		c_compile_value(c, value.b)

	case:
		fmt.sbprint(&c.output, "/* todo */")
	}

	fmt.sbprint(&c.output, ")")
}

c_compiler_type :: proc(c: ^C_Backend, type_id: Ir_Index) {
	type := c.ir.types[type_id]

	switch type.tag {
	case .Void:
		fmt.sbprint(&c.output, "void")

	case .Bool:
		fmt.sbprint(&c.output, "bool")

	case .Signed_Int:
		switch type.a {
		case 8, 16, 32, 64:
			fmt.sbprintf(&c.output, "int%v_t", type.a)

		case:
			fmt.sbprintf(&c.output, "_BitInt(%v)", type.a)
		}

	case .Unsigned_Int:
		switch type.a {
		case 8, 16, 32, 64:
			fmt.sbprintf(&c.output, "uint%v_t", type.a)

		case:
			fmt.sbprintf(&c.output, "unsigned _BitInt(%v)", type.a)
		}

	case .Float:
		switch type.a {
		case 16:
			fmt.sbprint(&c.output, "_Float16")
		case 32:
			fmt.sbprint(&c.output, "float")
		case 64:
			fmt.sbprint(&c.output, "double")
		}

	case .Untyped_Int, .Untyped_Float:
		fmt.sbprint(&c.output, "/* untyped type */")

	case .Type:
		fmt.sbprint(&c.output, "/* type of a type */")

	case .Single_Pointer:
	case .Multi_Pointer:
		c_compiler_type(c, type.a)
		fmt.sbprint(&c.output, "*")

	case .Slice:
		fmt.sbprint(&c.output, "struct _way_slice")

	case .Array:
	case .Function:
		fmt.sbprint(&c.output, "/* todo */")
	}
}
