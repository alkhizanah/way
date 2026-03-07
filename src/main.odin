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

        input_file_path := os.args[2]

        input_file_content, err := os.read_entire_file(input_file_path, context.allocator)

        if err != nil {
			fmt.eprintfln("error: could not open %v file: %v", input_file_path, err)
			os.exit(1)
        }

        lexer : Lexer

        lexer_init(&lexer, string(input_file_content))

        for token := next_token(&lexer); token.tag != .EOF; token = next_token(&lexer) {
            fmt.println(token.tag)
        }

	case:
		fmt.eprintfln("error: unhandled command: %v", command)
		os.exit(1)
	}
}
