package main

import "core:fmt"
import "core:os"

main :: proc() {
	program := os.args[0]

	if len(os.args) < 2 {
		fmt.eprintln("error: no command is provided")
		os.exit(1)
	}

	command := os.args[1]

	switch command {
	case "compile":
		if len(os.args) < 3 {
			fmt.eprintfln("error: no input file path is provided")
			os.exit(1)
		}

		parser: Parser

		parser_init(&parser, os.args[2])

		if !parse(&parser) {
			os.exit(1)
		}

		sema: Sema

		sema.ast = &parser.ast

		if !analyze(&sema) {
			os.exit(1)
		}
	case:
		fmt.eprintfln("error: unhandled command: %v", command)
		os.exit(1)
	}
}
