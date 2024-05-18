#import <Foundation/Foundation.h>

void main() {
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"Hello, World!\n" dataUsingEncoding:2]];
}