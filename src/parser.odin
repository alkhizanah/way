package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Parser :: struct {
	lexer:          Lexer,
	ast:            Ast,
	file_path:      string,
	current_token:  Token,
	previous_token: Token,
}

parser_init :: proc(p: ^Parser, file_path: string) -> bool {
	file_content, err := os.read_entire_file(file_path, context.allocator)

	if err != nil {
		fmt.eprintfln("error: could not open %v file: %v", file_path, err)
		return false
	}

	p.file_path = file_path

	lexer_init(&p.lexer, string(file_content))

	advance_token(p)

	return true
}

advance_token :: proc(p: ^Parser) -> Token {
	p.previous_token = p.current_token
	p.current_token = next_token(&p.lexer)
	return p.previous_token
}

@(require_results)
allow_token :: proc(p: ^Parser, tag: Token_Tag) -> bool {
	if p.current_token.tag == tag {
		advance_token(p)

		return true
	}

	return false
}

@(require_results)
peek_token :: proc(p: ^Parser, tag: Token_Tag) -> bool {
	return p.current_token.tag == tag
}

append_node :: proc(
	p: ^Parser,
	tag: Ast_Node_Tag,
	lhs: Ast_Index,
	rhs: Ast_Index,
	source: Position,
) -> Ast_Index {
	append(&p.ast.nodes, Ast_Node{lhs, rhs, tag})
	append(&p.ast.sources, source)
	return Ast_Index(len(p.ast.nodes) - 1)
}

syntax_error :: proc(p: ^Parser, position: Position, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: syntax error: ", p.file_path, position.line, position.column)
	fmt.eprintfln(format, args = args)
}

expect_token :: proc(p: ^Parser, tag: Token_Tag) -> (Token, bool) {
	prev := p.current_token

	advance_token(p)

	if prev.tag == tag {
		return prev, true
	}

	syntax_error(
		p,
		prev.position,
		"expected %s, got %s",
		token_tag_string[tag],
		token_tag_string[prev.tag],
	)

	return prev, false
}

expect_semicolon :: proc(p: ^Parser) -> bool {
	if (p.previous_token.tag != .Brace_Close) {
		expect_token(p, .Semicolon) or_return
	}

	return true
}

parse :: proc(p: ^Parser) -> bool {
	for !peek_token(p, .EOF) {
		parse_global(p) or_return
	}

	return true
}

parse_global :: proc(p: ^Parser) -> bool {
	name := expect_token(p, .Identifier) or_return

	expect_token(p, .Colon) or_return

	type := AST_INVALID

	value := AST_INVALID

	target: ^[dynamic]Ast_Binding

	if (p.current_token.tag != .Colon && p.current_token.tag != .Assign) {
		type = parse_expr(p, .Lowest)

		if type == AST_INVALID {
			return false
		}
	}

	if (p.current_token.tag == .Colon) {
		advance_token(p)

		value = parse_expr(p, .Lowest)

		if value == AST_INVALID {
			return false
		}

		target = &p.ast.global_constants
	} else if (p.current_token.tag == .Assign) {
		advance_token(p)

		value = parse_expr(p, .Lowest)

		if value == AST_INVALID {
			return false
		}

		target = &p.ast.global_variables
	}

	expect_semicolon(p) or_return


	append(target, Ast_Binding{name = name, type = type, value = value})

	return true
}

parse_stmt :: proc(p: ^Parser) -> Ast_Index {
	#partial switch p.current_token.tag {
	case .Brace_Open:
		return parse_block(p)

	case .Return:
		return parse_return(p)

	case .Break:
		return append_node(p, .Break, 0, 0, advance_token(p).position)

	case .Continue:
		return append_node(p, .Continue, 0, 0, advance_token(p).position)

	case:
		return parse_expr(p, .Lowest)
	}
}

Precedence :: enum {
	Lowest,
	Assign,
	Bitwise,
	Comparison,
	Shift,
	Additive,
	Multiplicative,
	Prefix,
	Postfix,
}

precedence_of_token :: proc(tag: Token_Tag) -> Precedence {
	#partial switch tag {
	case .Plus, .Minus:
		return .Additive

	case .Star, .Forward_Slash, .Percent:
		return .Multiplicative

	case .Bit_Left_Shift, .Bit_Right_Shift:
		return .Shift

	case .Equal, .Not_Equal, .Less_Than, .Greater_Than, .Less_Than_Equal, .Greater_Than_Equal:
		return .Comparison

	case .Bit_And, .Bit_Or, .Bit_Xor:
		return .Bitwise

	case .Paren_Open, .Bracket_Open, .Dot:
		return .Postfix

	case .Assign:
		return .Assign

	case:
		return .Lowest
	}
}

parse_expr :: proc(p: ^Parser, precedence: Precedence) -> Ast_Index {
	lhs := parse_unary_expr(p)

	for precedence_of_token(p.current_token.tag) > precedence {
		if lhs == AST_INVALID do return AST_INVALID

		lhs = parse_binary_expr(p, lhs)
	}

	return lhs
}

parse_unary_expr :: proc(p: ^Parser) -> Ast_Index {
	#partial switch (p.current_token.tag) {
	case .Identifier:
		return parse_identifier(p)

	case .Null:
		return append_node(p, .Null, 0, 0, advance_token(p).position)

	case .Void:
		return append_node(p, .Void_Type, 0, 0, advance_token(p).position)

	case .Int:
		return parse_int(p)

	case .Float:
		return parse_float(p)

	case .String:
		return parse_string(p)

	case .Minus:
		return parse_unary_op(p, .Negate)

	case .Bit_Not:
		return parse_unary_op(p, .Bit_Not)

	case .Bool_Not:
		return parse_unary_op(p, .Bool_Not)

	case .Paren_Open:
		return parse_grouped_expr(p)

	case .Fn:
		return parse_function(p)

	case:
		syntax_error(p, p.current_token.position, "unknown expression")

		return AST_INVALID
	}
}

parse_unary_op :: proc(p: ^Parser, tag: Ast_Node_Tag) -> Ast_Index {
	token := advance_token(p)
	rhs := parse_expr(p, .Prefix)
	if rhs == AST_INVALID do return AST_INVALID
	return append_node(p, tag, 0, rhs, token.position)
}

parse_grouped_expr :: proc(p: ^Parser) -> Ast_Index {
	advance_token(p)
	expr := parse_expr(p, .Lowest)
	_, ok := expect_token(p, .Paren_Close)
	if !ok do return AST_INVALID
	return expr
}

parse_binary_expr :: proc(p: ^Parser, lhs: Ast_Index) -> Ast_Index {
	#partial switch (p.current_token.tag) {
	case .Plus:
		return parse_binary_op(p, lhs, .Add)
	case .Minus:
		return parse_binary_op(p, lhs, .Sub)
	case .Star:
		return parse_binary_op(p, lhs, .Mul)
	case .Forward_Slash:
		return parse_binary_op(p, lhs, .Div)
	case .Percent:
		return parse_binary_op(p, lhs, .Mod)

	case .Equal:
		return parse_binary_op(p, lhs, .Eql)
	case .Not_Equal:
		return parse_binary_op(p, lhs, .Neq)
	case .Less_Than:
		return parse_binary_op(p, lhs, .Lt)
	case .Greater_Than:
		return parse_binary_op(p, lhs, .Gt)
	case .Less_Than_Equal:
		return parse_binary_op(p, lhs, .Lte)
	case .Greater_Than_Equal:
		return parse_binary_op(p, lhs, .Gte)

	case .Bit_Left_Shift:
		return parse_binary_op(p, lhs, .Bit_Shl)
	case .Bit_Right_Shift:
		return parse_binary_op(p, lhs, .Bit_Shr)
	case .Bit_And:
		return parse_binary_op(p, lhs, .Bit_And)
	case .Bit_Or:
		return parse_binary_op(p, lhs, .Bit_Or)
	case .Bit_Xor:
		return parse_binary_op(p, lhs, .Bit_Xor)

	case .Paren_Open:
		return parse_call(p, lhs)

	case .Bracket_Open:
		return parse_subscript(p, lhs)

	case:
		syntax_error(p, p.current_token.position, "unhandled binary operator")

		return AST_INVALID
	}
}

parse_binary_op :: proc(p: ^Parser, lhs: Ast_Index, tag: Ast_Node_Tag) -> Ast_Index {
	token := advance_token(p)
	rhs := parse_expr(p, precedence_of_token(token.tag))
	if rhs == AST_INVALID do return AST_INVALID
	return append_node(p, tag, lhs, rhs, token.position)
}

parse_subscript :: proc(p: ^Parser, target: Ast_Index) -> Ast_Index {
	token := advance_token(p)
	index := parse_expr(p, .Lowest)
	if index == AST_INVALID do return AST_INVALID
	_, ok := expect_token(p, .Bracket_Close)
	if !ok do return AST_INVALID
	return append_node(p, .Subscript, target, index, token.position)
}

parse_return :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	if p.current_token.tag == .Semicolon {
		return append_node(p, .Return, 0, AST_INVALID, token.position)
	} else {
		value := parse_expr(p, .Lowest)

		if value == AST_INVALID do return AST_INVALID

		return append_node(p, .Return, 0, value, token.position)
	}
}

parse_identifier :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	if len(token.value) >= 2 {
		bit_width, ok := strconv.parse_u64(token.value[1:])

		if ok {
			switch token.value[0] {
			case 'u', 's':
				if bit_width < u64(max(u16)) {
					tag: Ast_Node_Tag =
						token.value[0] == 'u' ? .Unsigned_Int_Type : .Signed_Int_Type

					return append_node(p, tag, 0, Ast_Index(bit_width), token.position)
				}

			case 'f':
				switch bit_width {
				case 16:
					return append_node(p, .Float16_Type, 0, 0, token.position)
				case 32:
					return append_node(p, .Float32_Type, 0, 0, token.position)
				case 64:
					return append_node(p, .Float64_Type, 0, 0, token.position)
				}
			}
		}
	}

	string_offset := len(p.ast.strings)

	append(&p.ast.strings, token.value)

	return append_node(
		p,
		.Identifier,
		Ast_Index(string_offset),
		Ast_Index(len(p.ast.strings) - string_offset),
		token.position,
	)
}

parse_int :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	v, ok := strconv.parse_u64(token.value)

	if !ok {
		syntax_error(p, token.position, "invalid integer")

		return AST_INVALID
	}

	return append_node(p, .Int, Ast_Index(v >> 32), Ast_Index(v), token.position)
}

parse_float :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	vf, ok := strconv.parse_f64(token.value)

	if !ok {
		syntax_error(p, token.position, "invalid floating point number")

		return AST_INVALID
	}

	v := transmute(u64)vf

	return append_node(p, .Float, Ast_Index(v >> 32), Ast_Index(v), token.position)
}

parse_string :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	string_offset := len(p.ast.strings)

	append(&p.ast.strings, token.value)

	return append_node(
		p,
		.String,
		Ast_Index(string_offset),
		Ast_Index(len(p.ast.strings) - string_offset),
		token.position,
	)
}

parse_call :: proc(p: ^Parser, callee: Ast_Index) -> Ast_Index {
	paren_open, ok := expect_token(p, .Paren_Open)

	if !ok do return AST_INVALID

	arguments: [dynamic]Ast_Index

	for !allow_token(p, .Paren_Close) {
		argument := parse_expr(p, .Lowest)

		if argument == AST_INVALID do return AST_INVALID

		append(&arguments, argument)

		if !allow_token(p, .Comma) && p.current_token.tag != .Paren_Close {
			syntax_error(
				p,
				p.current_token.position,
				"expected , or ) got %v",
				token_tag_string[p.current_token.tag],
			)

			return AST_INVALID
		}
	}

	arguments_index := len(p.ast.extra)

	append(&p.ast.extra, ..arguments[:])

	arguments_node := append_node(
		p,
		.Call_Arguments,
		Ast_Index(arguments_index),
		Ast_Index(len(arguments)),
		paren_open.position,
	)

	return append_node(p, .Call, callee, arguments_node, paren_open.position)
}

parse_function :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	type := parse_function_type(p)

	if type == AST_INVALID do return AST_INVALID

	if p.current_token.tag == .Brace_Open {
		block := parse_block(p)

		if block == AST_INVALID do return AST_INVALID

		return append_node(p, .Function, type, block, token.position)
	} else {
		return type
	}
}

parse_function_type :: proc(p: ^Parser) -> Ast_Index {
	paren_open, ok := expect_token(p, .Paren_Open)

	if !ok do return AST_INVALID

	parameters := make([dynamic]Ast_Index)

	defer delete(parameters)

	named := false

	for !allow_token(p, .Paren_Close) {
		if named {
			if p.current_token.tag != .Identifier {
				syntax_error(
					p,
					p.current_token.position,
					"expected an identifier for a parameter name but got %v",
					token_tag_string[p.current_token.tag],
				)

				return AST_INVALID
			}

			name := parse_identifier(p)

			_, ok = expect_token(p, .Colon)

			if !ok do return AST_INVALID

			type := parse_expr(p, .Lowest)

			if type == AST_INVALID do return AST_INVALID

			append(&parameters, name, type)
		} else {
			expr := parse_expr(p, .Lowest)

			if expr == AST_INVALID do return AST_INVALID

			if p.current_token.tag == .Colon {
				advance_token(p)

				named = true

				if p.ast.nodes[expr].tag != .Identifier {
					syntax_error(
						p,
						p.ast.sources[expr],
						"expected an identifier for a parameter name",
					)

					return AST_INVALID
				}

				name := expr

				type := parse_expr(p, .Lowest)

				if type == AST_INVALID do return AST_INVALID

				append(&parameters, name, type)
			} else {
				append(&parameters, expr)
			}
		}

		if !allow_token(p, .Comma) && p.current_token.tag != .Paren_Close {
			syntax_error(
				p,
				p.current_token.position,
				"expected , or ) got %v",
				token_tag_string[p.current_token.tag],
			)

			return AST_INVALID
		}
	}

	parameters_index := len(p.ast.extra)

	append(&p.ast.extra, ..parameters[:])

	parameters_node := append_node(
		p,
		named ? .Function_Named_Parameters : .Function_Unamed_Parameters,
		Ast_Index(parameters_index),
		Ast_Index(len(parameters)),
		paren_open.position,
	)

	return_type: Ast_Index

	if p.current_token.tag == .Brace_Open {
		return_type = append_node(p, .Void_Type, 0, 0, p.current_token.position)
	} else {
		arrow_token, ok := expect_token(p, .Right_Arrow)

		if !ok do return AST_INVALID

		return_type := parse_expr(p, .Lowest)

		if return_type == AST_INVALID do return AST_INVALID
	}

	return append_node(p, .Function_Type, parameters_node, return_type, paren_open.position)
}

parse_block :: proc(p: ^Parser) -> Ast_Index {
	brace_open, ok := expect_token(p, .Brace_Open)

	if !ok do return AST_INVALID

	stmts := make([dynamic]Ast_Index)

	for !allow_token(p, .Brace_Close) {
		stmt := parse_stmt(p)

		if stmt == AST_INVALID do return AST_INVALID

		if !expect_semicolon(p) do return AST_INVALID

		if p.current_token.tag == .EOF {
			syntax_error(p, brace_open.position, "{{ is not closed")

			return AST_INVALID
		}

		append(&stmts, stmt)
	}

	stmts_index := len(p.ast.extra)

	append(&p.ast.extra, ..stmts[:])

	stmts_count := len(stmts)

	delete(stmts)

	return append_node(
		p,
		.Block,
		Ast_Index(stmts_index),
		Ast_Index(stmts_count),
		brace_open.position,
	)
}
