package main

Ast_Index :: distinct u32

AST_INVALID :: max(Ast_Index)

Ast_Node_Tag :: enum {
	// a holds an index into strings and b is the amount of bytes the string contains
	Identifier,
	// a holds an index into strings and b is the amount of bytes the string contains
	String,
	// a is the upper bits and b is the lower bits
	Int,
	// a is the upper bits and b is the lower bits
	Float,
	// b is the bit width
	Unsigned_Int_Type,
	Signed_Int_Type,
	// the following are left as an exercise to the reader (they are unary operations, a is unused)
	Negate,
	Bool_Not,
	Bit_Not,
	// like the above but if b is AST_INVALID then the user didn't provide any return value
	Return,
	// the following are left as an exercise to the reader (they are binary operations, a and b are node indices)
	Bit_Or,
	Bit_Xor,
	Bit_And,
	Bit_Shl,
	Bit_Shr,
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Eql,
	Neq,
	Lt,
	Gt,
	Lte,
	Gte,
	Assign,
	Subscript,
	// a is an index into statements in extra, and b is the amount of statements
	Block,
	// a is an index into pairs of (identifier index, parameter type index) in extra, and b is the amount of parameters
	Function_Named_Parameters,
	// a is an index into array of parameter types in extra, and b is the amount of parameters
	Function_Unamed_Parameters,
	// a is an index to Function_Named_Parameters or Function_Unnamed_Parameters and b is an index to the return type
	Function_Type,
	// a is an index to Function_Type and b is an index to Block
	Function,
	// a is an index into values in extra, and b is the amount of values
	Call_Arguments,
	// a is an index to the callee, and b is an index to Call_Arguments
	Call,
	// a is the condition and b is an index to Block
	While,
	// a is the condition and b is an index to 2 elements in extra array where
	// first element is the true case block and the second is the false case block,
	// if the second element is AST_INVALID then the false case block is empty
	If,
	// a is an index into the sequence (start statement, conditon, end statement) in extra, all of them can be AST_INVALID,
	// and b is an index to Block
	For,
	// a is an index into pair (name index, type index) in extra and b is an index to the value
	Variable,
	// a is an index into pair (name index, type index) in extra and b is an index to the value
	Constant,
	// no payload needed for those
	Break,
	Continue,
	True,
	False,
	Null,
	Void_Type,
	Float16_Type,
	Float32_Type,
	Float64_Type,
}

Ast_Node :: struct {
	a:   Ast_Index,
	b:   Ast_Index,
	tag: Ast_Node_Tag,
}

Ast_Binding :: struct {
	name:  Token,
	type:  Ast_Index,
	value: Ast_Index,
}

Ast :: struct {
	global_variables: [dynamic]Ast_Binding,
	global_constants: [dynamic]Ast_Binding,
	nodes:            [dynamic]Ast_Node,
	positions:        [dynamic]Position,
	extra:            [dynamic]Ast_Index,
	strings:          [dynamic]u8,
}
