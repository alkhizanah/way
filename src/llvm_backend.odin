package main

import "core:strings"
import "llvm"

LLVM_Backend :: struct {
	ir:            ^Ir,
	ctx:           llvm.ContextRef,
	builder:       llvm.BuilderRef,
	module:        llvm.ModuleRef,
	function:      llvm.ValueRef,
	globals:       [dynamic]llvm.ValueRef,
	functions:     [dynamic]llvm.ValueRef,
	blocks:        [dynamic]llvm.BasicBlockRef,
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

	for function in l.ir.functions {
		llvm_type := llvm_compile_type(l, function.type)

		append(
			&l.functions,
			llvm.AddFunction(l.module, strings.clone_to_cstring(function.name.value), llvm_type),
		)
	}

	for binding, i in l.ir.globals {
		llvm_value := llvm_compile_value(l, binding.value)

		llvm.SetInitializer(l.globals[i], llvm_value)
	}

	for function, i in l.ir.functions {
		l.function = l.functions[i]

		clear(&l.blocks)

		clear(&l.cached_values)

		reserve(&l.blocks, len(function.blocks))

		for block in function.blocks {
			append(&l.blocks, llvm.AppendBasicBlock(l.function, ""))
		}

		for block, i in function.blocks {
			llvm.PositionBuilderAtEnd(l.builder, l.blocks[i])

			for instruction in block.instructions {
				llvm_compile_instruction(l, instruction)
			}
		}
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

	case .Function:
		params_info := type.a

		param_count := int(l.ir.extra[params_info])

		param_types := make([]llvm.TypeRef, param_count)

		for i in 0 ..< param_count {
			param_type_id := l.ir.extra[params_info + 1 + Ir_Index(i)]
			param_types[i] = llvm_compile_type(l, param_type_id)
		}

		return_type := llvm_compile_type(l, type.b)

		llvm_type = llvm.FunctionType(return_type, raw_data(param_types), u32(param_count), 0)

	case .Untyped_Int:
		llvm_type = llvm.Int64TypeInContext(l.ctx)

	case .Untyped_Float:
		llvm_type = llvm.DoubleTypeInContext(l.ctx)

	case .Slice:
		element_types := []llvm.TypeRef {
			llvm.PointerTypeInContext(l.ctx, 0),
			llvm.Int64TypeInContext(l.ctx),
		}

		llvm_type = llvm.StructTypeInContext(
			l.ctx,
			raw_data(element_types),
			u32(len(element_types)),
			Packed = 0,
		)

	case .Type:
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

	value_type := l.ir.types[value.type]

	llvm_value_type := llvm_compile_type(l, value.type)

	#partial switch value.tag {
	case .Int:
		llvm_value = llvm.ConstInt(llvm_value_type, extract_int_value(value), 0)

	case .Float:
		llvm_value = llvm.ConstReal(llvm_value_type, extract_float_value(value))

	case .Bool:
		llvm_value = llvm.ConstInt(llvm_value_type, u64(value.a), 0)

	case .Zero, .Null:
		llvm_value = llvm.ConstNull(llvm_value_type)

	case .Add:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(value_type) {
			llvm_value = llvm.BuildFAdd(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildAdd(l.builder, a, b, "")
		}

	case .Sub:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(value_type) {
			llvm_value = llvm.BuildFSub(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildSub(l.builder, a, b, "")
		}

	case .Mul:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		if is_float_type(value_type) {
			llvm_value = llvm.BuildFMul(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildMul(l.builder, a, b, "")
		}

	case .Div:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := value_type.tag == .Signed_Int

		if is_float_type(value_type) {
			llvm_value = llvm.BuildFDiv(l.builder, a, b, "")
		} else if signed {
			llvm_value = llvm.BuildSDiv(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildUDiv(l.builder, a, b, "")
		}

	case .Mod:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		signed := value_type.tag == .Signed_Int

		if is_float_type(value_type) {
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

		signed := value_type.tag == .Signed_Int

		if signed {
			llvm_value = llvm.BuildAShr(l.builder, a, b, "")
		} else {
			llvm_value = llvm.BuildLShr(l.builder, a, b, "")
		}

	case .Eql, .Neq, .Lt, .Gt, .Lte, .Gte:
		a := llvm_compile_value(l, value.a)
		b := llvm_compile_value(l, value.b)

		operand_type := l.ir.types[l.ir.values[value.a].type]

		signed := operand_type.tag == .Signed_Int

		if is_float_type(operand_type) {
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

		if is_float_type(value_type) {
			llvm_value = llvm.BuildFNeg(l.builder, a, "")
		} else {
			llvm_value = llvm.BuildNeg(l.builder, a, "")
		}

	case .Bool_Not, .Bit_Not:
		a := llvm_compile_value(l, value.a)

		llvm_value = llvm.BuildNot(l.builder, a, "")

	case .Alloca:
		llvm_element_type := llvm_compile_type(l, value.a)

		alloca_block := llvm.GetEntryBasicBlock(l.function)

		ip := llvm.GetInsertBlock(l.builder)

		first := llvm.GetFirstInstruction(alloca_block)

		if first != nil {
			llvm.PositionBuilderBefore(l.builder, first)
		} else {
			llvm.PositionBuilderAtEnd(l.builder, alloca_block)
		}

		llvm_value = llvm.BuildAlloca(l.builder, llvm_element_type, "")

		llvm.PositionBuilderAtEnd(l.builder, ip)

	case .Load:
		pointer_value := l.ir.values[value.a]

		llvm_pointer_value := llvm_compile_value(l, value.a)

		if pointer_value.tag == .Get_Element_Ptr {
			llvm_slice := llvm_compile_value(l, pointer_value.a)

			if llvm.IsAConstant(llvm_slice) != nil {
				llvm_slice := llvm_compile_value(l, pointer_value.a)

				index_value := l.ir.values[pointer_value.b]

				if index_value.tag == .Int {
					llvm_value = llvm.BuildExtractValue(
						l.builder,
						llvm_slice,
						u32(extract_int_value(index_value)),
						"",
					)
				} else {
					llvm_value = llvm.BuildLoad2(
						l.builder,
						llvm_value_type,
						llvm_pointer_value,
						"",
					)
				}
			} else {
				llvm_value = llvm.BuildLoad2(l.builder, llvm_value_type, llvm_pointer_value, "")
			}
		} else {
			llvm_value = llvm.BuildLoad2(l.builder, llvm_value_type, llvm_pointer_value, "")
		}

	case .Global:
		llvm_value = l.globals[value.a]

	case .Function:
		llvm_value = l.functions[value.a]

	case .Parameter:
		llvm_value = llvm.GetParam(l.function, u32(value.a))

	case .Get_Slice_Ptr, .Get_Slice_Len:
		slice_type := l.ir.types[l.ir.values[value.a].type]

		llvm_slice := llvm_compile_value(l, value.a)

		if slice_type.tag == .Single_Pointer {
			llvm_slice_ptr_index := llvm.ConstInt(
				llvm.Int8TypeInContext(l.ctx),
				value.tag == .Get_Slice_Ptr ? 0 : 1,
				0,
			)

			llvm_slice_ptr_ptr := llvm.BuildGEP2(
				l.builder,
				llvm_value_type,
				llvm_slice,
				&llvm_slice_ptr_index,
				1,
				"",
			)

			llvm_value = llvm.BuildLoad2(l.builder, llvm_value_type, llvm_slice_ptr_ptr, "")
		} else if slice_type.tag == .Slice {
			llvm_value = llvm.BuildExtractValue(
				l.builder,
				llvm_slice,
				value.tag == .Get_Slice_Ptr ? 0 : 1,
				"",
			)
		}

	case .Get_Element_Ptr:
		assert(value_type.tag == .Single_Pointer || value_type.tag == .Multi_Pointer)

		base_pointer_value := l.ir.values[value.a]

		base_pointer_type := l.ir.types[base_pointer_value.type]

		llvm_element_type := llvm_compile_type(l, base_pointer_type.a)

		llvm_base_pointer := llvm_compile_value(l, value.a)

		llvm_index := llvm_compile_value(l, value.b)

		llvm_value = llvm.BuildGEP2(
			l.builder,
			llvm_element_type,
			llvm_base_pointer,
			&llvm_index,
			1,
			"",
		)

	case .Call:
		callee_value := l.ir.values[value.a]

		callee_type_id := callee_value.type

		if l.ir.types[callee_type_id].tag == .Single_Pointer {
			callee_type_id = l.ir.types[callee_type_id].a
		}

		assert(l.ir.types[callee_type_id].tag == .Function)

		llvm_callee_type := llvm_compile_type(l, callee_type_id)

		llvm_callee := llvm_compile_value(l, value.a)

		args_data := l.ir.extra[value.b:]
		arg_count := int(args_data[0])

		args := make([]llvm.ValueRef, arg_count)

		for i in 0 ..< arg_count {
			arg_id := args_data[i + 1]
			args[i] = llvm_compile_value(l, arg_id)
		}

		llvm_value = llvm.BuildCall2(
			l.builder,
			llvm_callee_type,
			llvm_callee,
			raw_data(args),
			u32(arg_count),
			"",
		)

	case .String:
		string_value := llvm.ConstStringInContext2(
			l.ctx,
			cstring(&l.ir.strings[value.a]),
			i32(value.b),
			DontNullTerminate = 0,
		)

		string_global := llvm.AddGlobal(l.module, llvm.TypeOf(string_value), "")

		llvm.SetInitializer(string_global, string_value)

		constant_vals := []llvm.ValueRef {
			string_global,
			llvm.ConstInt(llvm.Int64TypeInContext(l.ctx), u64(value.b), 0),
		}

		llvm_value = llvm.ConstStructInContext(
			l.ctx,
			raw_data(constant_vals),
			u32(len(constant_vals)),
			Packed = 0,
		)

	case .Type:
		assert(false, "should be unreachable")
	}

	l.cached_values[value_id] = llvm_value

	return
}

llvm_compile_instruction :: proc(l: ^LLVM_Backend, instruction: Ir_Instruction) {
	switch instruction.tag {
	case .Value:
		llvm_compile_value(l, instruction.a)

	case .Store:
		pointer_value := llvm_compile_value(l, instruction.a)
		value_to_store := llvm_compile_value(l, instruction.b)

		llvm.BuildStore(l.builder, value_to_store, pointer_value)

	case .Branch:
		llvm.BuildBr(l.builder, l.blocks[instruction.a])

	case .Conditional_Branch:
		condition := llvm_compile_value(l, instruction.a)

		then_block := l.blocks[l.ir.extra[instruction.b]]
		else_block := l.blocks[l.ir.extra[instruction.b + 1]]

		llvm.BuildCondBr(l.builder, condition, then_block, else_block)

	case .Return:
		if instruction.a == IR_INVALID {
			llvm.BuildRetVoid(l.builder)
		} else {
			llvm.BuildRet(l.builder, llvm_compile_value(l, instruction.a))
		}

	case .Unreachable:
		llvm.BuildUnreachable(l.builder)
	}
}
