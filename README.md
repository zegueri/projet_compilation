# Logic Interpreter

This mini project provides a simple interpreter able to manipulate boolean functions defined by truth tables or formulas.

## Building

Run `make` to build the `logic_interpreter` binary. `flex` and `bison` must be installed.

## Running

- **Interactive mode:** `./logic_interpreter` then type commands followed by Enter.
- **File mode:** `./logic_interpreter < file.txt` to execute commands from a file.

## Commands

- `define NAME[(vars)] = FORMULA|{ table }` – create or replace a function.
- `list` – display the names of all defined functions.
- `varlist NAME` – show the variables used by a function.
- `table NAME` – print the truth table of a function.
- `eval NAME at VALUES` – evaluate a function with the provided values.
- `formula NAME` – display a formula representing the function.

## Tests

Example command files are located in `tests/`. Run `make test` to build the interpreter and check the output of these scripts.

## Limitations

Error handling remains very light and some edge cases may not be reported gracefully.
