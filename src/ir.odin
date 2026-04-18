package main

Ir_Index :: distinct u32

IR_INVALID :: max(Ir_Index)

Ir_Type_Tag :: enum {
	// a is an index into extra which has parameter types,
	// first element is the amount and the rest are the type indices,
	// b is an index to a return type
	Function,

	// a is the child type
	Single_Pointer,
	Multi_Pointer,
	Slice,

	// a is the child type, b is the amount of elements
	Array,

	// a is the bit width in these
	Unsigned_Int,
	Signed_Int,
	Float,

	// no payload is needed
	Untyped_Int,
	Untyped_Float,
	Type,
	Void,
	Bool,
}

Ir_Type :: struct {
	a:   Ir_Index,
	b:   Ir_Index,
	tag: Ir_Type_Tag,
}

Ir_Value_Tag :: enum {
	// a is upper bits and b is the lower bits for these
	Int,
	Float,

	// a is an index into strings and b is the amount of bytes the string contains
	String,

	// a is either 1 or 0
	Bool,

	// a is an index for a global variable
	Global,

	// a is an index to a function
	Function,

	// a is an index to a type
	Type,

	// two value indices as operands
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Bit_Or,
	Bit_Xor,
	Bit_And,
	Bit_Shl,
	Bit_Shr,

	// two value indices as operands, all of them produce Bool value
	Eql,
	Neq,
	Lt,
	Gt,
	Lte,
	Gte,

	// requires only one index to a value operand in a
	Negate,
	Bool_Not,
	Bit_Not,

	// a is an index to a type
	Alloca,

	// a is an index to value which is the pointer
	Load,

	// a is an index to value which is the pointer, and b is an index to the value to store
	Store,

	// a is an index to value which is the base pointer, and b is an index to the value which is the offset
	Get_Element_Ptr,

	// a is an index to a value which is the callee, b is an index into extra for call arguments
	Call,

	// a is an index for which parameter this is
	Parameter,

	// no payload is needed
	Zero, // ZII, zero initializer of the type it is associated with
	Null,
}

Ir_Value :: struct {
	a:    Ir_Index,
	b:    Ir_Index,
	type: Ir_Index,
	tag:  Ir_Value_Tag,
}

Ir_Instruction_Tag :: enum {
	// a is a value index (this is needed for values that do side effect but its return is not needed)
	Value,

	// a is a block index to branch into
	Branch,

	// a is a value index which is the condition and b is an index to a pair of (true case block index, false case block index) in extra
	Conditional_Branch,

	// a is a value index
	Return,

	// doesn't need a payload, and should never be reached
	Unreachable,
}

Ir_Instruction :: struct {
	a:   Ir_Index,
	b:   Ir_Index,
	tag: Ir_Instruction_Tag,
}

Ir_Block :: struct {
	instructions_start: Ir_Index,
	instructions_count: u32,
}

Ir_Function :: struct {
	name:         Token,
	type:         Ir_Index,
	blocks_start: Ir_Index,
	blocks_count: u32,
}

Ir_Global :: struct {
	name:  Token,
	value: Ir_Index,
}

Ir :: struct {
	values:       [dynamic]Ir_Value,
	types:        [dynamic]Ir_Type,
	extra:        [dynamic]Ir_Index,
	instructions: [dynamic]Ir_Instruction,
	positions:    [dynamic]Position,
	blocks:       [dynamic]Ir_Block,
	functions:    [dynamic]Ir_Function,
	globals:      [dynamic]Ir_Global,
	strings:      [dynamic]u8,
}
