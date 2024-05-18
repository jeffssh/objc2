# objc2
Restoring the power of NSExpressions to replace in memory dylib loading.
Works, but very limited due to inability to pass doubles/floats/other data
types that use different data types. As an example, a double return value will
be placed in d0 normally, but the NSFunctionExpression implementation always
stores the return value in x0. This makes the usable calls very limited


# To generate an AST, create an NSExpression, then test using the harness
```
TARGET_FILE=./objc-payloads/read-etc-passwd.m make ast
```

