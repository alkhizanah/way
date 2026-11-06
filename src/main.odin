package main

import "core:fmt"
import "core:os"
import "core:strings"

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

		file_path := os.args[2]

		parser: Parser

		if !parser_init(&parser, file_path) do os.exit(1)

		if !parse(&parser) do os.exit(1)

		sema: Sema

		sema_init(&sema, &parser.ast)

		if !analyze(&sema) do os.exit(1)

		delete_ast(parser.ast)

		llvm_backend: LLVM_Backend

		llvm_init(
			&llvm_backend,
			strings.clone_to_cstring(parser.lexer.position.file_path),
			&sema.ir,
		)

		llvm_start(&llvm_backend)

		output_file_path := file_path

		if strings.ends_with(output_file_path, ".way") {
			output_file_path = output_file_path[:len(output_file_path) - 4]
		} else {
			output_file_path = fmt.tprintf("%s.out", output_file_path)
		}

		llvm_commit(&llvm_backend, output_file_path)

	case:
		fmt.eprintfln("error: unhandled command: %v", command)
		os.exit(1)
	}
}
