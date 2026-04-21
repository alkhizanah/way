package main

import "core:strings"
import "llvm"

LLVM_Backend :: struct {
	ir:            ^Ir,
	ctx:           llvm.ContextRef,
	builder:       llvm.BuilderRef,
	module:        llvm.ModuleRef,
	globals:       [dynamic]llvm.ValueRef,
	cached_types:  map[Ir_Index]llvm.TypeRef,
	cached_values: map[Ir_Index]llvm.ValueRef,
}

llvm_init :: proc(l: ^LLVM_Backend, name: cstring, ir: ^Ir) {
	l.ir = ir

	l.ctx = llvm.ContextCreate()
	l.builder = llvm.CreateBuilderInContext(l.ctx)
	l.module = llvm.ModuleCreateWithNameInContext(name, l.ctx)

	l.cached_types = make(map[Ir_Index]llvm.TypeRef, len(l.ir.types))
	l.cached_values = make(map[Ir_Index]llvm.ValueRef, len(l.ir.values))
}

llvm_start :: proc(l: ^LLVM_Backend) {
	for binding in l.ir.globals {
		llvm_type := llvm_compile_type(l, l.ir.values[binding.value].type)

		append(
			&l.globals,
			llvm.AddGlobal(l.module, llvm_type, strings.clone_to_cstring(binding.name.value)),
		)
	}

	for binding, i in l.ir.globals {
		llvm_value := llvm_compile_value(l, binding.value)

		llvm.SetInitializer(l.globals[i], llvm_value)
	}
}

llvm_compile_type :: proc(l: ^LLVM_Backend, type_id: Ir_Index) -> (llvm_type: llvm.TypeRef) {
	if cached_type, ok := l.cached_types[type_id]; ok {
		return cached_type
	}

	type := l.ir.types[type_id]

	switch type.tag {
	case .Void:
		llvm_type = llvm.VoidTypeInContext(l.ctx)

	case .Single_Pointer, .Multi_Pointer:
		llvm_type = llvm.PointerTypeInContext(l.ctx, 0)

	case .Signed_Int, .Unsigned_Int:
		llvm_type = llvm.IntTypeInContext(l.ctx, u32(type.a))

	case .Bool:
		llvm_type = llvm.IntTypeInContext(l.ctx, 1)

	case .Float:
		switch type.a {
		case 16:
			llvm_type = llvm.HalfTypeInContext(l.ctx)
		case 32:
			llvm_type = llvm.FloatTypeInContext(l.ctx)
		case 64:
			llvm_type = llvm.DoubleTypeInContext(l.ctx)
		case:
			assert(false, "should be unreachable")
		}

	case .Array:
		child_type := llvm_compile_type(l, type.a)
		llvm_type = llvm.ArrayType2(child_type, u64(type.b))

	case .Function, .Slice:
		assert(false, "todo")

	case .Untyped_Int, .Untyped_Float, .Type:
		assert(false, "should be unreachable")
	}

	l.cached_types[type_id] = llvm_type

	return
}

llvm_compile_value :: proc(l: ^LLVM_Backend, value_id: Ir_Index) -> (llvm_value: llvm.ValueRef) {
	if cached_value, ok := l.cached_values[value_id]; ok {
		return cached_value
	}

	value := l.ir.values[value_id]

	type := l.ir.types[value.type]

	llvm_type := llvm_compile_type(l, value.type)

	#partial switch value.tag {

	case .Int:
		llvm_value = llvm.ConstInt(llvm_type, extract_int_value(value), 0)

	case .Float:
		llvm_value = llvm.ConstReal(llvm_type, extract_float_value(value))

	case .Bool:
		llvm_value = llvm.ConstInt(llvm_type, u64(value.a), 0)

	case .Zero, .Null:
		llvm_value = llvm.ConstNull(llvm_type)

	case .Add:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(type) {
			llvm_value = llvm.BuildFAdd(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildAdd(l.builder, a, b, "")
		}

	case .Sub:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(type) {
			llvm_value = llvm.BuildFSub(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildSub(l.builder, a, b, "")
		}

	case .Mul:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(type) {
			llvm_value = llvm.BuildFMul(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildMul(l.builder, a, b, "")
		}

	case .Div:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := type.tag == .Signed_Int

		if is_float_type(type) {
			llvm_value = llvm.BuildFDiv(l.builder, a, b, "")
		} else if signed {
			llvm_value = llvm.BuildSDiv(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildUDiv(l.builder, a, b, "")
		}

	case .Mod:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := type.tag == .Signed_Int

		if is_float_type(type) {
			llvm_value = llvm.BuildFRem(l.builder, a, b, "")
		} else if signed {
			llvm_value = llvm.BuildSRem(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildURem(l.builder, a, b, "")
		}

	case .Bit_Or:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		llvm_value = llvm.BuildOr(l.builder, a, b, "")

	case .Bit_Xor:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		llvm_value = llvm.BuildXor(l.builder, a, b, "")

	case .Bit_And:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		llvm_value = llvm.BuildAnd(l.builder, a, b, "")

	case .Bit_Shl:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		llvm_value = llvm.BuildShl(l.builder, a, b, "")

	case .Bit_Shr:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := type.tag == .Signed_Int

		if signed {
			llvm_value = llvm.BuildAShr(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildLShr(l.builder, a, b, "")
		}

	case .Eql, .Neq, .Lt, .Gt, .Lte, .Gte:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := type.tag == .Signed_Int

		if is_float_type(type) {
			#partial switch value.tag {
			case .Eql:
				llvm_value = llvm.BuildFCmp(l.builder, .OEQ, a, b, "")
			case .Neq:
				llvm_value = llvm.BuildFCmp(l.builder, .ONE, a, b, "")
			case .Lt:
				llvm_value = llvm.BuildFCmp(l.builder, .OLT, a, b, "")
			case .Gt:
				llvm_value = llvm.BuildFCmp(l.builder, .OGT, a, b, "")
			case .Lte:
				llvm_value = llvm.BuildFCmp(l.builder, .OLE, a, b, "")
			case .Gte:
				llvm_value = llvm.BuildFCmp(l.builder, .OGE, a, b, "")
			}
		} else {
			#partial switch value.tag {
			case .Eql:
				llvm_value = llvm.BuildICmp(l.builder, .EQ, a, b, "")
			case .Neq:
				llvm_value = llvm.BuildICmp(l.builder, .NE, a, b, "")
			case .Lt:
				llvm_value = llvm.BuildICmp(l.builder, signed ? .SLT : .ULT, a, b, "")
			case .Gt:
				llvm_value = llvm.BuildICmp(l.builder, signed ? .SGT : .UGT, a, b, "")
			case .Lte:
				llvm_value = llvm.BuildICmp(l.builder, signed ? .SLE : .ULE, a, b, "")
			case .Gte:
				llvm_value = llvm.BuildICmp(l.builder, signed ? .SGE : .UGE, a, b, "")
			}
		}

	case .Negate:
		a := llvm_compile_value(l, value.a)

		if is_float_type(type) {
			llvm_value = llvm.BuildFNeg(l.builder, a, "")
		} else {
			llvm_value = llvm.BuildNeg(l.builder, a, "")
		}

	case .Bool_Not, .Bit_Not:
		a := llvm_compile_value(l, value.a)

		llvm_value = llvm.BuildNot(l.builder, a, "")

	case:
		assert(false, "todo")
	}

	l.cached_values[value_id] = llvm_value

	return
}
