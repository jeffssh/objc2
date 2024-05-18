#import <Foundation/Foundation.h>

void main() {
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"Done Sleeping1!\n" dataUsingEncoding:2]];
    [NSThread sleepForTimeInterval:10];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"Done Sleeping2!\n" dataUsingEncoding:2]];
    [NSThread sleepForTimeInterval:10];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[@"Done Sleeping3!\n" dataUsingEncoding:2]];
}

