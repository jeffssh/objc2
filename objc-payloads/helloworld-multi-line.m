#import <Foundation/Foundation.h>

void main() {
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"1st Hello, World!\n" dataUsingEncoding:2]];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"2nd Hello, World!\n" dataUsingEncoding:2]];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"3rd Hello, World!\n" dataUsingEncoding:2]];
}