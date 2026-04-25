package main

import "core:fmt"
import "core:os"
import "core:strings"

import "llvm"

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

		if !parser_init(&parser, os.args[2]) do os.exit(1)

		if !parse(&parser) do os.exit(1)

		sema: Sema

		sema_init(&sema, &parser.ast)

		if !analyze(&sema) do os.exit(1)

		delete_ast(parser.ast)

		when #config(C_BACKEND, false) {
			c_backend: C_Backend

			c_init(&c_backend, sema.ir)

			c_start(&c_backend)

			fmt.println(strings.to_string(c_backend.output))
		} else {
			llvm_backend: LLVM_Backend

			llvm_init(
				&llvm_backend,
				strings.clone_to_cstring(parser.lexer.position.file_path),
				&sema.ir,
			)

			llvm_start(&llvm_backend)

			llvm.DumpModule(llvm_backend.module)
		}

	case:
		fmt.eprintfln("error: unhandled command: %v", command)
		os.exit(1)
	}
}
