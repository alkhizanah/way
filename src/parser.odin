package main

import "core:fmt"
import "core:os"
import "core:strconv"

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
	fmt.eprintf("%s:%d:%d: syntax error: ", p.file_path, position.line, position.column)
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

Precedence :: enum {
	Lowest,
}

parse_expr :: proc(p: ^Parser, precedence: Precedence) -> Ast_Index {
	lhs := parse_unary_expr(p)

	return lhs
}

parse_unary_expr :: proc(p: ^Parser) -> Ast_Index {
	#partial switch (p.current_token.tag) {
	case .Identifier:
		return parse_identifier(p)

	case .Int:
		return parse_int(p)

	case .Float:
		return parse_float(p)

	case .String:
		return parse_string(p)

	case:
		syntax_error(p, p.current_token.position, "unknown expression")

		return AST_INVALID
	}
}

parse_identifier :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

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

	return append_node(
		p,
		.Int,
		Ast_Index((v >> 32) & u64(max(u32))),
		Ast_Index(v & u64(max(u32))),
		token.position,
	)
}

parse_float :: proc(p: ^Parser) -> Ast_Index {
	token := advance_token(p)

	vf, ok := strconv.parse_f64(token.value)

	if !ok {
		syntax_error(p, token.position, "invalid floating point number")

		return AST_INVALID
	}
	
	v := transmute(u64)vf

	return append_node(
		p,
		.Float,
		Ast_Index((v >> 32) & u64(max(u32))),
		Ast_Index(v & u64(max(u32))),
		token.position,
	)
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
