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


Method_getArgumentType origMethod_getArgumentType;
Method_getReturnType origMethod_getReturnType;

void customMethod_getArgumentType(Method m, unsigned int index, char *dst, size_t dst_len) {
    origMethod_getArgumentType(m, index, dst, dst_len);
    if(strcmp(dst, "@")) {
        // won't be accepted, overwrite
        //NSLog(@"overwriting method_getArgumentType return value with '@'");
        memset(dst, 0x40, 1);
        memset(dst+1, 0x0, 3);
    }
}

void customMethod_getReturnType(Method m, char *dst, size_t dst_len) {
    origMethod_getReturnType(m, dst, dst_len);
    if(strcmp(dst, "@")) {
        // won't be accepted, overwrite
        //NSLog(@"overwriting method_getReturnType return value with '@'");
        memset(dst, 0x40, 1);
        memset(dst+1, 0x0, 3);
    }
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

void enableArbitratyNSFunctionExpressions(void) {
    int countOffset = 0x10;
    void *coreFoundationHandle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
    if (coreFoundationHandle) {
        dictRetFunction _CFPredicatePolicyRestrictedClasses = dlsym(coreFoundationHandle, "_CFPredicatePolicyRestrictedClasses");
        dictRetFunction _CFPredicatePolicyRestrictedSelectors = dlsym(coreFoundationHandle, "_CFPredicatePolicyRestrictedSelectors");
        // doesn't need to be modified
        voidRetFunction _CFPredicatePolicyDataSelectors = dlsym(coreFoundationHandle, "_CFPredicatePolicyData");

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
    
    origMethod_getArgumentType = *(Method_getArgumentType*)method_getArgumentTypeGotEntryAddr;
    origMethod_getReturnType = *(Method_getReturnType*)method_getReturnTypeGotEntryAddr;
    
    void (*customMethod_getArgumentTypeAddress)(Method, unsigned int, char *, size_t) = &customMethod_getArgumentType;
    void (*customMethod_getReturnTypeAddress)(Method m, char *dst, size_t dst_len) = &customMethod_getReturnType;

    // install the hooks
    *method_getArgumentTypeGotEntryAddr = (uintptr_t)customMethod_getArgumentTypeAddress;
    *method_getReturnTypeGotEntryAddr = (uintptr_t)customMethod_getReturnTypeAddress;
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        enableArbitratyNSFunctionExpressions();
        //NSString *nullAllocExpression  = @"FUNCTION(CAST('NSNull','Class'), 'alloc')";
        //NSString *logNSFunctionExpression  = @"FUNCTION(FUNCTION(CAST('NSFileHandle','Class'), 'fileHandleWithStandardOutput'), 'writeData:', FUNCTION('!!!!! hello from function expression! !!!!!!\\n', 'dataUsingEncoding:', FUNCTION(2,'intValue')))";
        NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
        NSData *inputData = [NSData dataWithData:[input readDataToEndOfFile]];
        NSString *inputString = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
        NSExpression *expression = [NSExpression expressionWithFormat:inputString];
        NSLog(@"Calling [[NSFileHandle fileHandleWithStandardOutput] writeData:] with NSExpressions!");
        [expression expressionValueWithObject:nil context:nil];
    }
    return 0;
}
