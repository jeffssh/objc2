
all: harness run

run: harness 
	./objc2.py | ./objc2-harness 

harness:
	gcc -framework Foundation -o objc2-harness ./main.m   

clean:
	rm -f objc2-harness