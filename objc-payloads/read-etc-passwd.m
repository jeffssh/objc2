#import <Foundation/Foundation.h>

void main() {
    [[NSFileHandle fileHandleWithStandardOutput] writeData:[NSData dataWithContentsOfFile:@"/etc/passwd"]];
}
