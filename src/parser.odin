package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Parser :: struct {
	lexer:          Lexer,
	ast:            Ast,
	current_token:  Token,
	previous_token: Token,
}

parser_init :: proc(p: ^Parser, file_path: string) -> bool {
	file_content, err := os.read_entire_file(file_path, context.allocator)

	if err != nil {
		fmt.eprintfln("error: could not open %v file: %v", file_path, err)
		return false
	}

	lexer_init(&p.lexer, file_path, string(file_content))

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
	if peek_token(p, tag) {
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
	a: Ast_Index,
	b: Ast_Index,
	position: Position,
) -> Ast_Index {
	append(&p.ast.nodes, Ast_Node{a, b, tag})
	append(&p.ast.positions, position)
	return Ast_Index(len(p.ast.nodes) - 1)
}

syntax_error :: proc(position: Position, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: syntax error: ", position.file_path, position.line, position.column)
	fmt.eprintfln(format, args = args)
}

expect_token :: proc(p: ^Parser, tag: Token_Tag) -> (Token, bool) {
	prev := p.current_token

	advance_token(p)

	if prev.tag == tag {
		return prev, true
	}

	syntax_error(
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

	target: ^[dynamic]Ast_Binding = &p.ast.global_variables

	if !peek_token(p, .Colon) && !peek_token(p, .Assign) {
		type = parse_expr(p, .Lowest, stop_on_assign = true)

		if type == AST_INVALID do return false
	}

	if allow_token(p, .Colon) {
		value = parse_expr(p, .Lowest)

		if value == AST_INVALID do return false

		target = &p.ast.global_constants
	} else if allow_token(p, .Assign) {
		value = parse_expr(p, .Lowest)

		if value == AST_INVALID do return false
	}

	expect_semicolon(p) or_return

	append(target, Ast_Binding{name = name, type = type, value = value})

	return true
}

parse_stmt :: proc(p: ^Parser) -> Ast_Index {
	#partial switch p.current_token.tag {
	case .Identifier:
		previous_token := p.previous_token
		identifier := advance_token(p)

		is_colon := peek_token(p, .Colon)

		p.previous_token = previous_token
		p.current_token = identifier

		if is_colon {
			return parse_binding(p)
		} else {
			return parse_expr(p, .Lowest)
		}

	case .Brace_Open:
		return parse_block(p)

	case .While:
		return parse_while_loop(p)

	case .For:
		return parse_for_loop(p)

	case .If:
		return parse_conditional(p)

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

parse_binding :: proc(p: ^Parser) -> Ast_Index {
	name := parse_identifier(p)

	// This must be of tag .Colon
	position := advance_token(p).position

	type := AST_INVALID
	value := AST_INVALID

	tag: Ast_Node_Tag

	if !peek_token(p, .Colon) && !peek_token(p, .Assign) {
		type = parse_expr(p, .Lowest)

		if type == AST_INVALID do return AST_INVALID
	}

	if allow_token(p, .Colon) {
		tag = .Constant

		value = parse_expr(p, .Lowest)

		if value == AST_INVALID do return AST_INVALID
	} else if allow_token(p, .Assign) {
		tag = .Variable

		value = parse_expr(p, .Lowest)

		if value == AST_INVALID do return AST_INVALID
	} else if peek_token(p, .Semicolon) {
		tag = .Variable
	} else {
		syntax_error(
			p.current_token.position,
			"expected a value, or ;, got %s",
			token_tag_string[p.current_token.tag],
		)

		return AST_INVALID
	}

	a := Ast_Index(len(p.ast.extra))

	append(&p.ast.extra, name, type)

	return append_node(p, tag, a, value, position)
}

parse_block :: proc(p: ^Parser) -> Ast_Index {
	brace_open, ok := expect_token(p, .Brace_Open)

	if !ok do return AST_INVALID

	stmts := make([dynamic]Ast_Index)

	for !allow_token(p, .Brace_Close) {
		stmt := parse_stmt(p)

		if stmt == AST_INVALID do return AST_INVALID

		if !expect_semicolon(p) do return AST_INVALID

		if peek_token(p, .EOF) {
			syntax_error(brace_open.position, "{{ is not closed")

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

parse_while_loop :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	condition := parse_expr(p, .Lowest)

	if condition == AST_INVALID do return AST_INVALID

	block := parse_block(p)

	if block == AST_INVALID do return AST_INVALID

	return append_node(p, .While, condition, block, token.position)
}

parse_for_loop :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	inital := AST_INVALID

	if !allow_token(p, .Semicolon) {
		inital = parse_stmt(p)

		if inital == AST_INVALID do return AST_INVALID

		_, ok := expect_token(p, .Semicolon)

		if !ok do return AST_INVALID
	}

	condition := AST_INVALID

	if !allow_token(p, .Semicolon) {
		condition = parse_expr(p, .Lowest)

		if condition == AST_INVALID do return AST_INVALID

		_, ok := expect_token(p, .Semicolon)

		if !ok do return AST_INVALID
	}

	ending := AST_INVALID

	if !peek_token(p, .Brace_Open) {
		ending = parse_stmt(p)

		if ending == AST_INVALID do return AST_INVALID
	}

	block := parse_block(p)

	if block == AST_INVALID do return AST_INVALID

	a := Ast_Index(len(p.ast.extra))

	append(&p.ast.extra, inital, condition, ending)

	return append_node(p, .For, a, block, token.position)
}

parse_conditional :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	condition := parse_expr(p, .Lowest)

	if condition == AST_INVALID do return AST_INVALID

	true_case := parse_block(p)

	if true_case == AST_INVALID do return AST_INVALID

	false_case := AST_INVALID

	if allow_token(p, .Else) {
		#partial switch (p.current_token.tag) {
		case .If:
			false_case = parse_conditional(p)

			if false_case == AST_INVALID do return AST_INVALID

		case .Brace_Open:
			false_case = parse_block(p)

			if false_case == AST_INVALID do return AST_INVALID

		case:
			syntax_error(
				p.current_token.position,
				"expected {{ or if, got %v",
				token_tag_string[p.current_token.tag],
			)

			return AST_INVALID
		}
	}

	b := Ast_Index(len(p.ast.extra))

	append(&p.ast.extra, true_case, false_case)

	return append_node(p, .If, condition, b, token.position)
}

parse_return :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	if peek_token(p, .Semicolon) {
		return append_node(p, .Return, 0, AST_INVALID, token.position)
	} else {
		value := parse_expr(p, .Lowest)

		if value == AST_INVALID do return AST_INVALID

		return append_node(p, .Return, 0, value, token.position)
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

parse_expr :: proc(p: ^Parser, precedence: Precedence, stop_on_assign := false) -> Ast_Index {
	a := parse_unary_expr(p)

	for precedence_of_token(p.current_token.tag) > precedence {
		if stop_on_assign && p.current_token.tag == .Assign do break

		if a == AST_INVALID do return AST_INVALID

		a = parse_binary_expr(p, a)
	}

	return a
}

parse_unary_expr :: proc(p: ^Parser) -> Ast_Index {
	#partial switch (p.current_token.tag) {
	case .Identifier:
		return parse_identifier(p)

	case .True:
		return append_node(p, .True, 0, 0, advance_token(p).position)

	case .False:
		return append_node(p, .False, 0, 0, advance_token(p).position)

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
		syntax_error(p.current_token.position, "unknown expression")

		return AST_INVALID
	}
}

parse_unary_op :: proc(p: ^Parser, tag: Ast_Node_Tag) -> Ast_Index {
	token := advance_token(p)
	b := parse_expr(p, .Prefix)
	if b == AST_INVALID do return AST_INVALID
	return append_node(p, tag, 0, b, token.position)
}

parse_grouped_expr :: proc(p: ^Parser) -> Ast_Index {
	advance_token(p)
	expr := parse_expr(p, .Lowest)
	_, ok := expect_token(p, .Paren_Close)
	if !ok do return AST_INVALID
	return expr
}

parse_binary_expr :: proc(p: ^Parser, a: Ast_Index) -> Ast_Index {
	#partial switch (p.current_token.tag) {
	case .Plus:
		return parse_binary_op(p, a, .Add)
	case .Minus:
		return parse_binary_op(p, a, .Sub)
	case .Star:
		return parse_binary_op(p, a, .Mul)
	case .Forward_Slash:
		return parse_binary_op(p, a, .Div)
	case .Percent:
		return parse_binary_op(p, a, .Mod)

	case .Equal:
		return parse_binary_op(p, a, .Eql)
	case .Not_Equal:
		return parse_binary_op(p, a, .Neq)
	case .Less_Than:
		return parse_binary_op(p, a, .Lt)
	case .Greater_Than:
		return parse_binary_op(p, a, .Gt)
	case .Less_Than_Equal:
		return parse_binary_op(p, a, .Lte)
	case .Greater_Than_Equal:
		return parse_binary_op(p, a, .Gte)

	case .Bit_Left_Shift:
		return parse_binary_op(p, a, .Bit_Shl)
	case .Bit_Right_Shift:
		return parse_binary_op(p, a, .Bit_Shr)
	case .Bit_And:
		return parse_binary_op(p, a, .Bit_And)
	case .Bit_Or:
		return parse_binary_op(p, a, .Bit_Or)
	case .Bit_Xor:
		return parse_binary_op(p, a, .Bit_Xor)

	case .Paren_Open:
		return parse_call(p, a)

	case .Bracket_Open:
		return parse_subscript(p, a)

	case .Assign:
		return parse_assign(p, a)

	case:
		syntax_error(p.current_token.position, "unhandled binary operator")

		return AST_INVALID
	}
}

parse_binary_op :: proc(p: ^Parser, a: Ast_Index, tag: Ast_Node_Tag) -> Ast_Index {
	token := advance_token(p)
	b := parse_expr(p, precedence_of_token(token.tag))
	if b == AST_INVALID do return AST_INVALID
	return append_node(p, tag, a, b, token.position)
}

parse_subscript :: proc(p: ^Parser, target: Ast_Index) -> Ast_Index {
	token := advance_token(p)
	index := parse_expr(p, .Lowest)
	if index == AST_INVALID do return AST_INVALID
	_, ok := expect_token(p, .Bracket_Close)
	if !ok do return AST_INVALID
	return append_node(p, .Subscript, target, index, token.position)
}

parse_assign :: proc(p: ^Parser, target: Ast_Index) -> Ast_Index {
	token := advance_token(p)
	value := parse_expr(p, .Lowest)
	if value == AST_INVALID do return AST_INVALID
	return append_node(p, .Assign, target, value, token.position)
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

					return append_node(p, tag, Ast_Index(bit_width), 0, token.position)
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
		syntax_error(token.position, "invalid integer")

		return AST_INVALID
	}

	return append_node(p, .Int, Ast_Index(v >> 32), Ast_Index(v), token.position)
}

parse_float :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	vf, ok := strconv.parse_f64(token.value)

	if !ok {
		syntax_error(token.position, "invalid floating point number")

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

		if !allow_token(p, .Comma) && !peek_token(p, .Paren_Close) {
			syntax_error(
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

	if peek_token(p, .Brace_Open) {
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
			if !peek_token(p, .Identifier) {
				syntax_error(
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

			if allow_token(p, .Colon) {
				named = true

				if p.ast.nodes[expr].tag != .Identifier {
					syntax_error(
						p.ast.positions[expr],
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

		if !allow_token(p, .Comma) && !peek_token(p, .Paren_Close) {
			syntax_error(
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

	if peek_token(p, .Brace_Open) {
		return_type = append_node(p, .Void_Type, 0, 0, p.current_token.position)
	} else {
		arrow_token, ok := expect_token(p, .Right_Arrow)

		if !ok do return AST_INVALID

		return_type := parse_expr(p, .Lowest)

		if return_type == AST_INVALID do return AST_INVALID
	}

	return append_node(p, .Function_Type, parameters_node, return_type, paren_open.position)
}
