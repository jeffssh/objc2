
all: harness run

run: harness 
	./objc2.py | ./objc2-harness 

ast: harness build
	echo $(TARGET_FILE)
	gcc -Xclang -ast-dump=json -Xclang -ast-dump-filter=main -fsyntax-only -framework Foundation $(TARGET_FILE) > build/ast.json
	jq -s '.' < build/ast.json > build/slurped-ast.json 
	./ast-parse.py | ./objc2-harness  

harness:
	gcc -framework Foundation -o objc2-harness ./ObjC2/main.m  

build:
	mkdir build

clean:
	rm -f objc2-harness
	rm -rf build



# gcc -Xclang -ast-dump -Xclang -ast-dump-filter=main -fsyntax-only -framework Foundation ./objc-payloads/helloworld.m > ast.txt   	
# gcc -Xclang -ast-dump=json -Xclang -ast-dump-filter=main -fsyntax-only -framework Foundation ./objc-payloads/helloworld.m > ast.json