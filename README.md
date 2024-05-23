# objc2
Restoring the power of NSExpressions to replace in memory dylib loading.
Works, but very limited due to inability to pass doubles/floats/other data
types that use different registers. As an example, a double return value will
be placed in d0 normally, but the NSFunctionExpression implementation always
stores the return value in x0. This makes the usable calls very limited


# To generate an AST, create an NSExpression, then test using the harness
```bash
$ TARGET_FILE=./objc-payloads/read-etc-passwd.m make ast       
gcc -framework Foundation -o objc2-harness ./ObjC2/main.m
mkdir build
echo ./objc-payloads/read-etc-passwd.m
./objc-payloads/read-etc-passwd.m
gcc -Xclang -ast-dump=json -Xclang -ast-dump-filter=main -fsyntax-only -framework Foundation ./objc-payloads/read-etc-passwd.m > build/ast.json
clang: warning: -framework Foundation: 'linker' input unused [-Wunused-command-line-argument]
./objc-payloads/read-etc-passwd.m:3:1: warning: return type of 'main' is not 'int' [-Wmain-return-type]
void main() {
^
./objc-payloads/read-etc-passwd.m:3:1: note: change return type to 'int'
void main() {
^~~~
int
1 warning generated.
jq -s '.' < build/ast.json > build/slurped-ast.json
./ast-parse.py | ./objc2-harness
##
# User Database
#
# Note that this file is consulted directly only when the system is running
# in single-user mode.  At other times this information is provided by
# Open Directory.
#
# See the opendirectoryd(8) man page for additional information about
# Open Directory.
##
nobody:*:-2:-2:Unprivileged User:/var/empty:/usr/bin/false
```

