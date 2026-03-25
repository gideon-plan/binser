# Choice/Life Adoption Plan: binser

## Summary

- **Error type**: `BinserError` defined in lattice.nim -- move to `cbor.nim`
- **Files to modify**: 4 + re-export module
- **Result sites**: 5
- **Life**: Not applicable

## Steps

1. Delete `src/binser/lattice.nim`
2. Move `BinserError* = object of CatchableError` to `src/binser/cbor.nim`
3. Add `requires "basis >= 0.1.0"` to nimble
4. In every file importing lattice:
   - Replace `import.*lattice` with `import basis/code/choice`
   - Replace `Result[T, E].good(v)` with `good(v)`
   - Replace `Result[T, E].bad(e[])` with `bad[T]("binser", e.msg)`
   - Replace `Result[T, E].bad(BinserError(msg: "x"))` with `bad[T]("binser", "x")`
   - Replace return type `Result[T, BinserError]` with `Choice[T]`
5. Update re-export: `export lattice` -> `export choice`
6. Update tests
