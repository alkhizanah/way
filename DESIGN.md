# Declarations

- Explicit type with initializer

```
name : T = value; // Variable
name : T : value; // Constants
```

- Explicit type without initializer (works only for variables, constants can not be modified so they must have a value)

```
name : T; // Variable
```

- Inferred type

```
name := value; // Variable
name :: value; // Constants
```

# Functions

- With parameters and result

```
name :: (a : T, b : T) -> R {

}
```

- Without parameters but with result

```
name :: () -> R {

}
```

- Without parameters and without result

```
name :: () -> void {

}

name :: () -> { // A shortcut to the above one

}
```

- Using it as a type

```
name : (a : T, b : T) -> R;
name : () -> R;
name : () -> void; // No shortcut since that would be ambiguous
```

# Operators

```
a + b; // Addition
a - b; // Subtraction
a * b; // Multiplication
a / b; // Division
a < b; // Less than
a > b; // Greater than
a == b; // Equal
a <= b; // Less than or equal
a >= b; // Greater than or equal
a << b; // Shift `a`'s bits to the left `b`times
a >> b; // Shift `a`'s bits to the right `b`times
a & b; // Perform AND operation on the bits of `a` and `b`
a | b; // Perform OR operation on the bits of `a` and `b`
a ^ b; // Perform XOR operation on the bits of `a` and `b`
```

# Primitive types

```
void // A type that describes that a function returns, but with no *useful* value, 
     // reading the top of the stack or the register `rax` (on System V x64 ABI)
     // after calling that function is meaningless and considered undefined

bool // A boolean, either `true` or `false`

u8 .. u16 .. u32 .. u57 .. u64 .. u128 .. uN // An arbitrary bit-lengthed unsigned integer (N must be smaller than 65536)
s8 .. s16 .. s32 .. s57 .. s64 .. s128 .. sN // An arbitrary bit-lengthed signed integer (N must be smaller than 65536)

usize, ssize // unsigned or signed integer with the size of a register

f16, f32, f64 // A floating point number defined by IEEE 754 standard
```

# Pointer types

Pointers are specified by adding a `*` prefix to the type, and dereferenced by `.*` suffix, for example:

```
swap :: (a : *u8, b : *u8) -> u8 {
    temp := a.*;
    a.* = b.*;
    b.* = temp;
}
```

You can have a multi-value pointer:

```
iterate :: (xs : [*]u8, len : usize, f : (x : u8) -> void) -> {
    for i := 0; i < len; i++ {
        f(xs[i])
    }
}
```

The above example is better if we used slices, a structure with mutli-value pointer and a length:

```
iterate :: (xs : []u8, f : (x : u8) -> void) -> {
    for i := 0; i < xs.len; i++ {
        f(xs[i])
    }
}
```

... To be continued
