local example = require("src.example")

-- Exercise trivial (CC=1): fully covered.
assert(example.trivial() == 42)

-- Exercise branchy with flag=true: covers the 'then' branch but not 'else'.
assert(example.branchy(true) == "yes")

-- Exercise loopy: loop executes n=5 times.
assert(example.loopy(5) == 15)

-- untouched() is NEVER called, producing a zero-coverage function.
