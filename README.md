# objc2
C2 using the full power of NSExpressions to replace in memory dylib loading


## Expected testing output
```bash
make run
gcc -framework Foundation -o objc2-harness ./ObjC2/main.m
./objc2.py | ./objc2-harness
2024-04-25 22:16:19.412 objc2-harness[52705:970871] Calling [[NSFileHandle fileHandleWithStandardOutput] writeData:] with NSExpressions!
!!!!! hello from function expression! !!!!!!
```
