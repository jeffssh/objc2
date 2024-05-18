//
//  main.m
//  ObjC2
//

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#import <objc/runtime.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>


typedef NSDictionary* (*dictRetFunction)(void);
typedef void* (*voidRetFunction)(void);
typedef void (*Method_getArgumentType)(Method m, unsigned int index, char *dst, size_t dst_len);
typedef void (*Method_getReturnType)(Method m, char *dst, size_t dst_len);
typedef uint32_t dyld_platform_t;
typedef struct {
    dyld_platform_t platform;
    uint32_t        version;
} dyld_build_version_t;
extern bool dyld_program_sdk_at_least(dyld_build_version_t version);
typedef bool (*dyld_program_sdk_at_least_type)(dyld_build_version_t version);
typedef void* (*objc_retain_type)(void* obj);
typedef void* (*objc_autorelease_type)(void* obj);

Method_getArgumentType orig_method_getArgumentType;
Method_getReturnType orig_method_getReturnType;
dyld_program_sdk_at_least_type orig_dyld_program_sdk_at_least;
objc_retain_type orig_objc_retain;
objc_autorelease_type orig_objc_autorelease;
bool objc_autorelease_reentry_flag = NO;
//(instancetype) orig_objc_retain;

NSMutableDictionary* perThreadReturnTypeForObjcRetainCtx;
NSMutableDictionary* perThreadReturnTypeForObjcAutoreleaseCtx;

NSString *returnTypeKey = @"returnType";
NSString *returnValueKey = @"returnValue";


void custom_method_getArgumentType(Method m, unsigned int index, char *dst, size_t dst_len) {
    orig_method_getArgumentType(m, index, dst, dst_len);
    if(strcmp(dst, "@")) {
        // won't be accepted, overwrite
        //NSLog(@"overwriting method_getArgumentType return value with '@'");
        memset(dst, 0x40, 1);
        memset(dst+1, 0x0, 3);
    }
}

void custom_method_getReturnType(Method m, char *dst, size_t dst_len) {
    orig_method_getReturnType(m, dst, dst_len);
    if(strcmp(dst, "@")) {
        // won't be accepted, overwrite
        NSString *currReturnType = [NSString stringWithUTF8String:dst];
        //NSLog(@"overwriting method_getReturnType return value of %@ with '@'", currReturnType);
        NSThread *thread = [NSThread currentThread];
        NSMutableDictionary *threadDict = [thread threadDictionary];
        [threadDict setValue:currReturnType forKey:returnTypeKey];
        memset(dst, 0x40, 1); // @
        memset(dst+1, 0x0, 3);
    }
}

bool custom_dyld_program_sdk_at_least(dyld_build_version_t version) {
    //NSLog(@"Hello from custom_dyld_program_sdk_at_least");
    //bool ret = orig_dyld_program_sdk_at_least(version);
    return 0;
}

void* custom_objc_retain(void* obj) {
    if ([NSThread.callStackSymbols count] >= 2 && [NSThread.callStackSymbols[2] containsString:@"-[NSFunctionExpression expressionValueWithObject:context:]"]) {
        NSThread *thread = [NSThread currentThread];
        NSMutableDictionary *threadDict = [thread threadDictionary];
        NSString *returnType = [threadDict valueForKey:returnTypeKey];
        NSNumber *returnValue = [threadDict valueForKey:returnValueKey];
        // if there was an altered return type, pass the value through
        if(returnType) {
            // on second call (so after return value has been set), pass through but clear the tracking keys)
            if((unsigned long long) obj == [returnValue unsignedLongLongValue]) {
                //NSLog(@"Hello from custom_objc_retain, stored return value is %p, clearing thread dict", obj);
                [threadDict removeObjectForKey:returnTypeKey];
                [threadDict removeObjectForKey:returnValueKey];
            } else {
                //NSLog(@"Hello from custom_objc_retain, expected return type is %@, storing return value of %p", returnType, obj);
                [threadDict setValue:[NSNumber numberWithUnsignedLongLong:(unsigned long long) obj] forKey:returnValueKey];
            }
            return obj;
        }
    } else if ([NSThread.callStackSymbols[1] containsString:@"-[NSFunctionExpression expressionValueWithObject:context:]"]) {
        // final return value won't be set in custom_objc_autorelease
        // in this case, return value points to null. Skip regular call to prevent crash
        return obj;
    }
    void* ret = orig_objc_retain(obj);
    return ret;
}

/*
 Hook entry order for 14.4.1
 custom_objc_autorelease, obj
 custom_objc_retain, 2
 custom_objc_retain, 2
 custom_objc_autorelease, 2
 */

void* custom_objc_autorelease(void* obj) {
    if (objc_autorelease_reentry_flag) {
        return obj;
    }
    objc_autorelease_reentry_flag = YES;
    if ([NSThread.callStackSymbols count] >= 2 && [NSThread.callStackSymbols[2] containsString:@"-[NSFunctionExpression expressionValueWithObject:context:]"]) {
        NSThread *thread = [NSThread currentThread];
        NSMutableDictionary *threadDict = [thread threadDictionary];
        NSNumber *returnValue = [threadDict valueForKey:returnValueKey];
        if((unsigned long long) obj == [returnValue unsignedLongLongValue]) {
            //NSLog(@"Hello from custom_objc_autorelease, skipping for return value %p", obj);
            return obj;
        }
    }
    void* ret = orig_objc_autorelease(obj);
    objc_autorelease_reentry_flag = NO;
    return ret;
}


uintptr_t getAddressOfSection(const char *imageName, const char *sectionName) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, imageName) != NULL) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (header == NULL) {
                continue;
            }
            
            uintptr_t slide = _dyld_get_image_vmaddr_slide(i);
            unsigned long long mach_header_size = sizeof(struct mach_header_64);
            const struct load_command *loadCmd = (struct load_command *)((uintptr_t)header + mach_header_size);
            for (uint32_t j = 0; j < header->ncmds; j++) {
                if (loadCmd->cmd == LC_SEGMENT_64) {
                    const struct segment_command_64 *segCmd = (struct segment_command_64 *)loadCmd;
                    const struct section_64 *section = (struct section_64 *)((uintptr_t)segCmd + sizeof(struct segment_command_64));
                    for (uint32_t k = 0; k < segCmd->nsects; k++) {
                        if (strcmp(section->sectname, sectionName) == 0) {
                            return (uintptr_t)section->addr + slide;
                        }
                        section++;
                    }
                }
                loadCmd = (struct load_command *)((uintptr_t)loadCmd + loadCmd->cmdsize);
            }
        }
    }
    return 0;
}


void* returnEmptyDict(void) {
    return (__bridge void*) [[NSDictionary alloc] init];
}


void enableArbitratyNSFunctionExpressionsMacOS135(void) {
    int countOffset = 0x10;
    void *coreFoundationHandle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
    if (coreFoundationHandle) {
        dictRetFunction _CFPredicatePolicyRestrictedClasses = dlsym(coreFoundationHandle, "_CFPredicatePolicyRestrictedClasses");
        dictRetFunction _CFPredicatePolicyRestrictedSelectors = dlsym(coreFoundationHandle, "_CFPredicatePolicyRestrictedSelectors");
        // doesn't need to be modified
        voidRetFunction _CFPredicatePolicyDataSelectors = dlsym(coreFoundationHandle, "_CFPredicatePolicyData");

        uintptr_t objc_dictobjAddr = getAddressOfSection("/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation", "__objc_dictobj");
        mprotect((void*)(objc_dictobjAddr & 0xffffffffffff0000), 0x10000, PROT_READ | PROT_WRITE);
        
        if (_CFPredicatePolicyRestrictedClasses && _CFPredicatePolicyRestrictedSelectors && _CFPredicatePolicyDataSelectors) {
            NSDictionary *predicateRestrictedClassesDict = _CFPredicatePolicyRestrictedClasses();
            NSDictionary *predicateRestrictedSelectorsDict = _CFPredicatePolicyRestrictedSelectors();
            void **doublePointer = _CFPredicatePolicyDataSelectors();
            NSDictionary *predicatePolicyDataSelectorsDict = (__bridge NSDictionary *)(*doublePointer);
//            NSLog(@"Restricted Classes before overwrite: %@", predicateRestrictedSelectorsDict);
//            NSLog(@"Restricted Selectors before overwrite: %@", predicateRestrictedSelectorsDict);
            // doesn't need to be modified
            //NSLog(@"Policy Data Selectors before overwrite: %@", predicatePolicyDataSelectorsDict);
            
            // overwrite size of the NSConstantDictionary to 0
            void *p = (__bridge void *)predicateRestrictedClassesDict + countOffset;
            memset(p, 0, 1);
            p = (__bridge void *)predicateRestrictedSelectorsDict + countOffset;
            memset(p, 0, 1);
           
            p = (__bridge void *)predicatePolicyDataSelectorsDict + countOffset;
            // doesn't need to be modified
            //memset(p, 0, 1);
            
            NSLog(@"Predicate restricted Classes after overwrite: %@", predicateRestrictedClassesDict);
            NSLog(@"Predicate restricted Selectors after overwrite: %@", predicateRestrictedSelectorsDict);
            // doesn't need to be modified
            //NSLog(@"Restricted Data Selectors after overwrite: %@", predicatePolicyDataSelectorsDict);
        } else {
            NSLog(@"Failed to find symbol(s) _CFPredicatePolicyRestrictedClasses or _CFPredicatePolicyRestrictedSelectors or _CFPredicatePolicyDataSelectors");
        }
        dlclose(coreFoundationHandle);
    } else {
        NSLog(@"Failed to load CoreFoundation framework");
    }
    
    // hook arg and ret type signature functions
    NSString *frameworkPath = @"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation";
    const char *sectionName = "__auth_got";
    uintptr_t foundationFrameworkAuthGotAddr = getAddressOfSection([frameworkPath UTF8String], sectionName);
    void *method_getArgumentTypeAddress = &method_getArgumentType;
    void *method_getReturnTypeAddress = &method_getReturnType;
    uintptr_t *method_getArgumentTypeGotEntryAddr = 0;
    uintptr_t *method_getReturnTypeGotEntryAddr = 0;
    while (!method_getArgumentTypeGotEntryAddr || !method_getReturnTypeGotEntryAddr) {
        void **value = (void *)foundationFrameworkAuthGotAddr;
        if (*value == method_getArgumentTypeAddress) {
            method_getArgumentTypeGotEntryAddr = (uintptr_t *)foundationFrameworkAuthGotAddr;
        }
        if (*value == method_getReturnTypeAddress) {
            method_getReturnTypeGotEntryAddr = (uintptr_t *)foundationFrameworkAuthGotAddr;
        }
        foundationFrameworkAuthGotAddr += sizeof(uint64_t);
    }
    
    NSLog(@"method_getArgumentType GOT entry addr 0x%p", method_getArgumentTypeGotEntryAddr);
    NSLog(@"method_getReturnType GOT entry addr 0x%p", method_getReturnTypeGotEntryAddr);
    
    orig_method_getArgumentType = *(Method_getArgumentType*)method_getArgumentTypeGotEntryAddr;
    orig_method_getReturnType = *(Method_getReturnType*)method_getReturnTypeGotEntryAddr;
    
    void (*custom_method_getArgumentTypeAddress)(Method, unsigned int, char *, size_t) = &custom_method_getArgumentType;
    void (*custom_method_getReturnTypeAddress)(Method m, char *dst, size_t dst_len) = &custom_method_getReturnType;

    // install the hooks
    *method_getArgumentTypeGotEntryAddr = (uintptr_t)custom_method_getArgumentTypeAddress;
    *method_getReturnTypeGotEntryAddr = (uintptr_t)custom_method_getReturnTypeAddress;
}


void installHookViaGotOverwrite(NSString *frameworkPath, NSString *sectionName, void *origFunction, void *hookFunction) {
    void *currGotEntryGuessAddr = (void*)getAddressOfSection([frameworkPath UTF8String], [sectionName  UTF8String]);
    void **gotEntryAddr = 0;
    while (!gotEntryAddr) {
        void **value = currGotEntryGuessAddr;
        if (*value == origFunction) {
            gotEntryAddr = currGotEntryGuessAddr;
        }
        currGotEntryGuessAddr += sizeof(uint64_t);
    }
    // install the hook
    *gotEntryAddr = hookFunction;
}


void enableArbitratyNSFunctionExpressionsMacOS1441(void) {
    void *dylib = dlopen("/usr/lib/system/libdyld.dylib", 0);
    orig_dyld_program_sdk_at_least = dlsym(dylib, "dyld_program_sdk_at_least");
    dlclose(dylib);
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_dyld_program_sdk_at_least,
                               &custom_dyld_program_sdk_at_least);
    dylib = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW);
    orig_objc_retain = dlsym(dylib, "objc_retain");
    orig_objc_autorelease = dlsym(dylib, "objc_autorelease");
    orig_method_getArgumentType = dlsym(dylib, "method_getArgumentType");
    orig_method_getReturnType = dlsym(dylib, "method_getReturnType");
    dlclose(dylib);
    dylib = dlopen("/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation", RTLD_NOW);
    dictRetFunction _CFPredicatePolicyRestrictedClasses = dlsym(dylib, "_CFPredicatePolicyRestrictedClasses");
    dictRetFunction _CFPredicatePolicyRestrictedSelectors = dlsym(dylib, "_CFPredicatePolicyRestrictedSelectors");
    dlclose(dylib);
    
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_objc_retain,
                               &custom_objc_retain);
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_objc_autorelease,
                               &custom_objc_autorelease);
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_method_getArgumentType,
                               &custom_method_getArgumentType);
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_method_getReturnType,
                               &custom_method_getReturnType);
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               orig_method_getReturnType,
                               &custom_method_getReturnType);
    
    // ensure loaded in the GOT
    _CFPredicatePolicyRestrictedClasses();
    // br s -a 0x19ebf57c4
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               _CFPredicatePolicyRestrictedClasses,
                               &returnEmptyDict);
    _CFPredicatePolicyRestrictedSelectors();
    installHookViaGotOverwrite(@"/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
                               @"__auth_got",
                               _CFPredicatePolicyRestrictedSelectors,
                               &returnEmptyDict);
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        //enableArbitratyNSFunctionExpressionsMacOS135();
        enableArbitratyNSFunctionExpressionsMacOS1441();
        NSString *nullAllocExpression  = @"FUNCTION(CAST('NSNull','Class'), 'alloc')";
        NSString *logNSFunctionExpression  = @"FUNCTION(FUNCTION(CAST('NSFileHandle','Class'), 'fileHandleWithStandardOutput'), 'writeData:', FUNCTION('!!!!! hello from function expression! !!!!!!\\n', 'dataUsingEncoding:', FUNCTION(2,'intValue')))";
        NSString *complexLogExpression = @"FUNCTION(CAST('NSNull','Class'), 'alloc', FUNCTION(FUNCTION(CAST('NSFileHandle','Class'), 'fileHandleWithStandardOutput'), 'writeData:', FUNCTION('!!!!! hello from function expression! !!!!!!\\n', 'dataUsingEncoding:', FUNCTION('0x2','intValue'))), FUNCTION(FUNCTION(CAST('NSFileHandle','Class'), 'fileHandleWithStandardOutput'), 'writeData:', FUNCTION('!!!!! hello from function expression! !!!!!!\\n', 'dataUsingEncoding:', FUNCTION(2,'intValue'))))";

        bool readFromStdin = YES;
        NSExpression *expression;
        if(readFromStdin) {
            NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
            NSData *inputData = [NSData dataWithData:[input readDataToEndOfFile]];
            NSString *inputString = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
            expression = [NSExpression expressionWithFormat:inputString];
        } else {
            expression = [NSExpression expressionWithFormat:complexLogExpression];
        }
        NSMutableDictionary* ctx = [NSMutableDictionary new];
        [expression expressionValueWithObject:nil context:ctx];
        NSLog(@"Done calling supplied NSExpressions!");
    }
    return 0;
}
