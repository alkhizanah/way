package main

import "core:unicode/utf8"


Position :: struct {
	line:   int,
	column: int,
	offset: int,
}

Lexer :: struct {
	position:    Position,
	buffer:      string,
	character:   rune,
	width:       int,
	offset:      int,
	line_offset: int,
}

Token_Tag :: enum {
	Invalid,
	EOF,
	Plus,
	Minus,
	Star,
	Forward_Slash,
	Percent,
	Dot,
	Comma,
	Semicolon,
	Paren_Open,
	Paren_Close,
	Bracket_Open,
	Bracket_Close,
	Brace_Open,
	Brace_Close,
	Assign,
	Equal,
	Not_Equal,
	Less_Than,
	Greater_Than,
	Less_Than_Equal,
	Greater_Than_Equal,
	Ellipsis,
	Right_Arrow,
	Colon,
	Bit_Left_Shift,
	Bit_Right_Shift,
	Bit_And,
	Bit_Or,
	Bit_Xor,
	Bit_Not,
	Bool_Not,
	Identifier,
	Int,
	Float,
	String,
	Fn,
	While,
	For,
	If,
	Else,
	True,
	False,
	Null,
	Return,
}

@(rodata)
token_tag_string := [Token_Tag]string {
	.Invalid            = "invalid bytes",
	.EOF                = "end of file",
	.Plus               = "+",
	.Minus              = "-",
	.Star               = "*",
	.Forward_Slash      = "/",
	.Percent            = "%",
	.Dot                = ".",
	.Comma              = ",",
	.Semicolon          = ";",
	.Paren_Open         = "(",
	.Paren_Close        = ")",
	.Bracket_Open       = "[",
	.Bracket_Close      = "]",
	.Brace_Open         = "{",
	.Brace_Close        = "}",
	.Assign             = "=",
	.Equal              = "==",
	.Not_Equal          = "!=",
	.Less_Than          = "<",
	.Greater_Than       = ">",
	.Less_Than_Equal    = "<=",
	.Greater_Than_Equal = ">=",
	.Ellipsis           = "...",
	.Right_Arrow        = "->",
	.Colon              = ":",
	.Bit_Left_Shift     = "<<",
	.Bit_Right_Shift    = ">>",
	.Bit_And            = "&",
	.Bit_Or             = "|",
	.Bit_Xor            = "^",
	.Bit_Not            = "~",
	.Bool_Not           = "!",
	.Identifier         = "an identifier",
	.Int                = "an integer",
	.Float              = "a floating points number",
	.String             = "a string",
	.Fn                 = "fn",
	.While              = "while",
	.For                = "for",
	.If                 = "if",
	.Else               = "else",
	.True               = "true",
	.False              = "false",
	.Null               = "null",
	.Return             = "return",
}

Token :: struct {
	tag:      Token_Tag,
	value:    string,
	position: Position,
}

lexer_init :: proc(l: ^Lexer, buffer: string) {
	l^ = Lexer {
		buffer = buffer,
	}

	l.position.line = 1

	next_rune(l)

	if l.character == utf8.RUNE_BOM {
		next_rune(l)
	}
}

next_rune :: proc(l: ^Lexer) -> rune {
	if l.offset < len(l.buffer) {
		l.offset += l.width
		l.character, l.width = utf8.decode_rune_in_string(l.buffer[l.offset:])
		l.position.column = l.offset - l.line_offset + 1
	}

	if l.offset >= len(l.buffer) {
		l.character = utf8.RUNE_EOF
		l.width = 1
	}

	return l.character
}

peek_rune :: proc(l: ^Lexer) -> rune {
	prev := l^
	character := next_rune(l)
	l^ = prev
	return character
}

next_token :: proc(l: ^Lexer) -> (token: Token) {
	skip_whitespace :: proc(l: ^Lexer) {
		for l.offset < len(l.buffer) {
			switch l.character {
			case ' ', '\t', '\r', '\f', '\v':
				next_rune(l)
			case '\n':
				l.line_offset = l.offset
				l.position.column = 1
				l.position.line += 1
				next_rune(l)
			case:
				return
			}
		}
	}

	is_identifier_continue :: proc(r: rune) -> bool {
		return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_' || r >= '0' && r <= '9'
	}

	is_digit :: proc(r: rune) -> bool {
		return r >= '0' && r <= '9'
	}

	scan_string :: proc(l: ^Lexer, token: ^Token) {
		start := l.offset

		for {
			if l.character == '"' || l.character == utf8.RUNE_EOF {
				break
			}

			if l.character == '\\' {
				next_rune(l)
			}

			next_rune(l)
		}

		token.value = l.buffer[start:l.offset]

		if l.character == '"' {
			next_rune(l)
		} else {
			token.tag = .Invalid
		}

		token.tag = .String
	}

	scan_number :: proc(l: ^Lexer, token: ^Token) {
		start := l.offset - l.width

		is_float := false

		for is_identifier_continue(l.character) {
			next_rune(l)
		}

		if l.character == '.' {
			is_float = true

			next_rune(l)

			for is_identifier_continue(l.character) {
				next_rune(l)
			}
		}

		token.value = l.buffer[start:l.offset]

		if is_float {
			token.tag = .Float
		} else {
			token.tag = .Int
		}
	}

	scan_identifier :: proc(l: ^Lexer, token: ^Token) {
		start := l.offset - l.width

		for is_identifier_continue(l.character) {
			next_rune(l)
		}

		text := l.buffer[start:l.offset]

		token.value = text

		switch text {
		case "fn":
			token.tag = .Fn
		case "while":
			token.tag = .While
		case "for":
			token.tag = .For
		case "if":
			token.tag = .If
		case "else":
			token.tag = .Else
		case "true":
			token.tag = .True
		case "false":
			token.tag = .False
		case "null":
			token.tag = .Null
		case "return":
			token.tag = .Return
		}

		token.tag = .Identifier
	}

	skip_whitespace(l)


	token.tag = .Invalid

	if l.character != utf8.RUNE_EOF {
		token.value = l.buffer[l.offset:][:l.width]
	}

	token.position = l.position

	character := l.character

	next_rune(l)

	switch character {
	case utf8.RUNE_EOF:
		token.tag = .EOF

	case '+':
		token.tag = .Plus

	case '-':
		if l.character == '>' {
			next_rune(l)

			token.tag = .Right_Arrow
		} else {
			token.tag = .Minus
		}

	case '*':
		token.tag = .Star

	case '/':
		switch l.character {
		case '/':
			// single-line comment
			for l.character != '\n' && l.character != utf8.RUNE_EOF {
				next_rune(l)
			}

			return next_token(l)

		case '*':
			// multi-line comment
			next_rune(l)

			for {
				if l.character == utf8.RUNE_EOF {
					token.tag = .Invalid
					return
				}

				if l.character == '*' && peek_rune(l) == '/' {
					next_rune(l) // *
					next_rune(l) // /
					break
				}

				if l.character == '\n' {
					l.line_offset = l.offset
					l.position.column = 1
					l.position.line += 1
				}

				next_rune(l)
			}

			return next_token(l)

		case:
			token.tag = .Forward_Slash
		}

	case '%':
		token.tag = .Percent

	case '.':
		if l.character == '.' && peek_rune(l) == '.' {
			next_rune(l)
			next_rune(l)

			token.value = "..."

			token.tag = .Ellipsis
		} else {
			token.tag = .Dot
		}

	case ',':
		token.tag = .Comma

	case ';':
		token.tag = .Semicolon

	case ':':
		token.tag = .Colon

	case '(':
		token.tag = .Paren_Open

	case ')':
		token.tag = .Paren_Close

	case '[':
		token.tag = .Bracket_Open

	case ']':
		token.tag = .Bracket_Close

	case '{':
		token.tag = .Brace_Open

	case '}':
		token.tag = .Brace_Close

	case '&':
		token.tag = .Bit_And

	case '|':
		token.tag = .Bit_Or

	case '^':
		token.tag = .Bit_Xor

	case '~':
		token.tag = .Bit_Not

	case '!':
		if l.character == '=' {
			next_rune(l)
			token.value = "!="
			token.tag = .Not_Equal
		} else {
			token.tag = .Bool_Not
		}

	case '=':
		if l.character == '=' {
			next_rune(l)
			token.value = "=="
			token.tag = .Equal
		} else {
			token.tag = .Assign
		}

	case '<':
		if l.character == '=' {
			next_rune(l)
			token.value = "<="
			token.tag = .Less_Than_Equal
		} else if l.character == '<' {
			next_rune(l)
			token.value = "<<"
			token.tag = .Bit_Left_Shift
		} else {
			token.tag = .Less_Than
		}

	case '>':
		if l.character == '=' {
			next_rune(l)
			token.value = ">="
			token.tag = .Greater_Than_Equal
		} else if l.character == '>' {
			next_rune(l)
			token.value = ">>"
			token.tag = .Bit_Right_Shift
		} else {
			token.tag = .Greater_Than
		}

	case '"':
		scan_string(l, &token)

	case 'A' ..= 'Z', 'a' ..= 'z', '_':
		scan_identifier(l, &token)

	case '0' ..= '9':
		scan_number(l, &token)
	}

	return token
}
