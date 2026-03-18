package main

Ast_Node_Tag :: enum {
	// lhs holds an index into strings and rhs is the amount of bytes the string contains
	Identifier,
	// lhs holds an index into strings and rhs is the amount of bytes the string contains
	String,
	// lhs is the upper bits and rhs is the lower bits
	Int,
	// lhs is the upper bits and rhs is the lower bits
	Float,
	// rhs is the bit width
	Unsigned_Int_Type,
	Signed_Int_Type,
	// the following are left as an exercise to the reader (they are unary operations, lhs is unused)
	Negate,
	Bool_Not,
	Bit_Not,
	Return,
	// the following are left as an exercise to the reader (they are binary operations, lhs and rhs are node indices)
	Bit_Or,
	Bit_Xor,
	Bit_And,
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
	// lhs is an index into statements in extra, and rhs is the amount of statements
	Block,
	// lhs is an index into pairs of (identifier index, parameter type index) in extra, and rhs is the amount of parameters
	Function_Parameters,
	// lhs is an index to Function_Parameters and rhs is an index to the return type
	Function_Prototype,
	// lhs is an index to Function_Prototype and rhs is an index to Block
	Function,
	// lhs is an index into values in extra, and rhs is the amount of values
	Call_Arguments,
	// lhs is an index to the callee, and rhs is an index to Call_Arguments
	Call,
	// lhs is the condition and rhs is an index to Block
	While,
	// lhs is the condition and rhs is an index to Block
	If,
	// lhs is an index into the sequence (start statement, conditon, end statement) in extra and rhs is an index to Block
	For,
	// lhs is an index into pair (name index, type index) in extra and rhs is an index to the value
	Variable,
	// lhs is an index into pair (name index, type index) in extra and rhs is an index to the value
	Constant,
	// no payload needed for those
	Break,
	Continue,
	Null,
	Void_Type,
	Float16_Type,
	Float32_Type,
	Float64_Type,
}

Ast_Index :: distinct u32

AST_INVALID :: max(Ast_Index)

Ast_Node :: struct {
	lhs: Ast_Index,
	rhs: Ast_Index,
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
	sources:          [dynamic]Position,
	extra:            [dynamic]Ast_Index,
	strings:          [dynamic]u8,
}
