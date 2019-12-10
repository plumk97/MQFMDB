//
//  MQFMDBObject.m
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import "MQFMDB.h"
#import "MQFMDBObject.h"
#import <objc/runtime.h>

/**
 压缩JSON 成 一行
 
 @param jsonData json数据
 @return
 */
NSData * _JSONCompressOneLineWithData(NSData * jsonData) {
    
    NSMutableData * data = [[NSMutableData alloc] init];
    
    UInt8 oneByte = 0;
    UInt8 recordByte = 0;
    
    for (int i = 0; i < jsonData.length; i ++) {
        [jsonData getBytes:&oneByte range:NSMakeRange(i, 1)];
        
        if (oneByte == '\n') continue;
        
        if (oneByte && recordByte == oneByte) {
            
            UInt8 tmpOneByte;
            [jsonData getBytes:&tmpOneByte range:NSMakeRange(i - 1, 1)];
            if (tmpOneByte != '\\') {
                recordByte = 0;
            }
        } else if (!recordByte && (oneByte == '"' || oneByte == '\'')) {
            recordByte = oneByte;
        } else if (!recordByte && (oneByte == ' ' || oneByte == '\t')) {
            oneByte = 0;
        }
        if (oneByte > 0)
            [data appendBytes:&oneByte length:1];
    }
    return data;
}

/**
 转换 NSDictionary NSArray 为JSON数据并且压缩
 
 @param object
 @return
 */
NSData * _ObjectEncodeJsonData(NSObject * object) {
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (jsonData) {
        jsonData = _JSONCompressOneLineWithData(jsonData);
    }
    return jsonData;
}


typedef enum {
    _PROPERTY_TYPE_Invalid,
    _PROPERTY_TYPE_Int,
    _PROPERTY_TYPE_BOOL,
    _PROPERTY_TYPE_Float,
    _PROPERTY_TYPE_Double,
    _PROPERTY_TYPE_NSString,
    _PROPERTY_TYPE_NSDate,
    _PROPERTY_TYPE_NSData,
    _PROPERTY_TYPE_NSDictionary,
    _PROPERTY_TYPE_NSArray,
    _PROPERTY_TYPE_MQFMDBObject
} _PROPERTY_TYPE;

typedef enum {
    SQLITE_FIELD_TYPE_INVALID,
    SQLITE_FIELD_TYPE_INTEGER,
    SQLITE_FIELD_TYPE_BOOLEAN,
    SQLITE_FIELD_TYPE_VARCHAR,
    SQLITE_FIELD_TYPE_DATE,
    SQLITE_FIELD_TYPE_BLOB,
    SQLITE_FIELD_TYPE_FLOAT,
    SQLITE_FIELD_TYPE_DOUBLE
} SQLITE_FIELD_TYPE;

/**
 转换 SQLITE_FIELD_TYPE 到 NSString
 
 @param type
 @return
 */
NSString * SQLITE_FIELD_TYPE_STR(SQLITE_FIELD_TYPE type) {
    switch (type) {
        case SQLITE_FIELD_TYPE_INVALID:
            break;
        case SQLITE_FIELD_TYPE_INTEGER:
            return @"INTEGER";
            break;
        case SQLITE_FIELD_TYPE_BOOLEAN:
            return @"BOOLEAN";
            break;
        case SQLITE_FIELD_TYPE_VARCHAR:
            return @"VARCHAR";
            break;
        case SQLITE_FIELD_TYPE_DATE:
            return @"DATE";
            break;
        case SQLITE_FIELD_TYPE_BLOB:
            return @"BLOB";
            break;
        case SQLITE_FIELD_TYPE_FLOAT:
            return @"FLOAT";
            break;
        case SQLITE_FIELD_TYPE_DOUBLE:
            return @"DOUBLE";
            break;
        default:
            break;
    }
    return nil;
}


@interface MQFMDBObject ()


@property (nonatomic, copy) NSArray * initialPropertyDictKeys;
@property (nonatomic, strong) NSMutableDictionary * propertyDict;

@property (nonatomic, strong) NSMutableDictionary * dbObjectIdDict;
@end
@implementation MQFMDBObject
@dynamic _Id;
@synthesize objectState = _objectState;
@synthesize affiliationDB = _affiliationDB;


+ (MQFMDBObject *)objectWithDictionary:(NSDictionary *)dictionary inDB:(MQFMDB *)inDB {
    
    MQFMDBObject * object = [[[self class] alloc] init];
    object.affiliationDB = inDB;
    if (dictionary) {
        /** 初始化值 */
        [self enumAllPropertyWithClass:[self class] execute:^(const char *propertyName, _PROPERTY_TYPE propertyType, SQLITE_FIELD_TYPE fieldType, objc_property_t property) {
            NSString * key = [NSString stringWithUTF8String:propertyName];
            id obj = [dictionary objectForKey:key];
            if (obj && ![obj isKindOfClass:[NSNull class]]) {
                
                switch (propertyType) {
                    case _PROPERTY_TYPE_NSDate: {
                        if ([obj isKindOfClass:[NSString class]]) {
                            
                            NSDateFormatter * dateF = [[NSDateFormatter alloc] init];
                            [dateF setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                            
                            NSDate * date = [dateF dateFromString:obj];
                            [object.propertyDict setObject:date forKey:key];
                        } else {
                            NSDate * date = [NSDate dateWithTimeIntervalSince1970:[obj doubleValue]];
                            [object.propertyDict setObject:date forKey:key];
                        }
                    }
                        break;
                    case _PROPERTY_TYPE_MQFMDBObject: {
                        // 在使用的时候再去查找
                        [object.dbObjectIdDict setObject:obj forKey:key];
                    }
                        break;
                    case _PROPERTY_TYPE_NSArray:
                    case _PROPERTY_TYPE_NSDictionary: {
                        obj = [NSJSONSerialization JSONObjectWithData:obj options:NSJSONReadingAllowFragments error:nil];
                        if (obj) {
                            [object.propertyDict setObject:obj forKey:key];
                        }
                    }
                        break;
                    default: {
                        [object.propertyDict setObject:obj forKey:key];
                    }
                        break;
                }
            }
        }];
    }
    
    object.initialPropertyDictKeys = [[self class] instanceAttributes];
    return object;
    
}


- (id) init {
    self = [super init];
    if (self) {
        self.propertyDict = [[NSMutableDictionary alloc] init];
        self.dbObjectIdDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    
}

- (void)setAffiliationDB:(MQFMDB *)affiliationDB {
    if (_affiliationDB != affiliationDB) {
        _affiliationDB = affiliationDB;
    }
}

- (void)setObjectState:(MQFMDBObjectState)objectState {
    
    if (objectState == MQFMDBObjectStateUpdate && _objectState == MQFMDBObjectStateInsert) {
        return;
    }
    if (_objectState != objectState) {
        _objectState = objectState;
    }
}

/**
 标记为需要更新状态
 */
- (void)markUpdateStatus {
    if (self.objectState != MQFMDBObjectStateUpdate && self.objectState != MQFMDBObjectStateInsert) {
        self.objectState = MQFMDBObjectStateUpdate;
        [self.affiliationDB performSelector:sel_getUid("addOneUpdateObject:") onThread:[NSThread currentThread] withObject:self waitUntilDone:YES];
    }
}

// MARK: - KVC
// -- Overwrite KVC
- (void)setValue:(id)value forKey:(NSString *)key {
    
    if ([self propertyIsTableFieldWithPropertyName:key]) {
        [self.propertyDict setObject:value forKey:key];
        [self markUpdateStatus];
        return;
    }
    [super setValue:value forKey:key];
}

- (id)valueForKey:(NSString *)key {
    if ([self propertyIsTableFieldWithPropertyName:key]) {
        return [self.propertyDict objectForKey:key];
    }
    return [super valueForKey:key];
}

/**
 判断某个属性是否是数据库字段
 
 @param propertyName 属性名
 @return YES/NO
 */
- (BOOL)propertyIsTableFieldWithPropertyName:(NSString *)propertyName {
    
    objc_property_t property_t = class_getProperty([self class], [propertyName UTF8String]);
    if (property_t == NULL) return NO;
    
    const char * attributes = property_getAttributes(property_t);
    return strstr(attributes, ",D") != NULL;
}

// MARK: - Forward message
// -- 拦截消息 实现 SET、GET 方法

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature * signature = [super methodSignatureForSelector:aSelector];
    if (signature) {
        return signature;
    }
    /** 生成签名 */
    NSString *sel = NSStringFromSelector(aSelector);
    BOOL isSet = [sel hasPrefix:@"set"];
    NSString * key = isSet ? [sel substringWithRange:NSMakeRange(3, sel.length - 4)] : sel;
    if (isSet) {
        key = [[[key substringToIndex:1] lowercaseString] stringByAppendingString:[key substringWithRange:NSMakeRange(1, key.length - 1)]];
    }
    
    objc_property_t property = class_getProperty([self class], [key UTF8String]);
    if (property == NULL) {
        return nil;
    }
    NSString * attributes = [NSString stringWithUTF8String:property_getAttributes(property)];
    NSArray * components = [attributes componentsSeparatedByString:@","];
    NSString * partType = [components objectAtIndex:0];
    if (![partType hasPrefix:@"T"]) {
        return nil;
    }
    
    if ([partType rangeOfString:@"@"].length > 0) {
        // Id type
        return isSet ? [NSMethodSignature signatureWithObjCTypes:"v@:@"] : [NSMethodSignature signatureWithObjCTypes:"@@:"];
    }
    
    // ctype
    // SET
    if (isSet) {
        const char * objcTypes = [[NSString stringWithFormat:@"v@:%@", [partType substringWithRange:NSMakeRange(1, partType.length - 1)]] UTF8String];
        return [NSMethodSignature signatureWithObjCTypes:objcTypes];
    }
    
    // GET
    const char * objcTypes = [[[partType substringWithRange:NSMakeRange(1, partType.length - 1)] stringByAppendingString:@"@:"] UTF8String];
    return [NSMethodSignature signatureWithObjCTypes:objcTypes];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    
    NSString * key = NSStringFromSelector([invocation selector]);
    BOOL isSet = [key hasPrefix:@"set"];
    if (isSet) {
        key = [key substringWithRange:NSMakeRange(3, key.length - 4)];
        key = [[[key substringToIndex:1] lowercaseString] stringByAppendingString:[key substringWithRange:NSMakeRange(1, key.length - 1)]];
    }
    
    objc_property_t t = class_getProperty([self class], [key UTF8String]);
    
    _PROPERTY_TYPE property_type;
    SQLITE_FIELD_TYPE sqlite_type;
    char * encode_str;
    [[self class] lookupProperty:t outPropertyType:&property_type outSqliteType:&sqlite_type outEncodeStr:&encode_str];
    if (property_type == _PROPERTY_TYPE_Invalid) {
        return;
    }
    
    if (isSet) {
        // SET
        NSObject * obj = nil;
        switch (property_type) {
            case _PROPERTY_TYPE_Invalid:
                break;
            case _PROPERTY_TYPE_Int: {
                if (0) {
                } else if (strcmp(@encode(short), encode_str) == 0) {
                    short value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithShort:value];
                } else if (strcmp(@encode(unsigned short), encode_str) == 0) {
                    unsigned short value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithUnsignedShort:value];
                } else if (strcmp(@encode(int), encode_str) == 0) {
                    int value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithInt:value];
                } else if (strcmp(@encode(unsigned int), encode_str) == 0) {
                    unsigned int value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithUnsignedInt:value];
                } else if (strcmp(@encode(long), encode_str) == 0) {
                    long value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithLong:value];
                } else if (strcmp(@encode(unsigned long), encode_str) == 0) {
                    unsigned long value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithUnsignedLong:value];
                } else if (strcmp(@encode(long long), encode_str) == 0) {
                    long long value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithLongLong:value];
                } else if (strcmp(@encode(unsigned long long), encode_str) == 0) {
                    unsigned long long value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithUnsignedLongLong:value];
                } else if (strcmp(@encode(NSInteger), encode_str) == 0) {
                    NSInteger value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithInteger:value];
                } else if (strcmp(@encode(NSUInteger), encode_str) == 0) {
                    NSUInteger value = 0;
                    [invocation getArgument:&value atIndex:2];
                    obj = [NSNumber numberWithUnsignedInteger:value];
                }
            }
                break;
            case _PROPERTY_TYPE_BOOL: {
                BOOL value = false;
                [invocation getArgument:&value atIndex:2];
                obj = [NSNumber numberWithBool:value];
            }
                break;
            case _PROPERTY_TYPE_Float: {
                float value = 0;
                [invocation getArgument:&value atIndex:2];
                obj = [NSNumber numberWithFloat:value];
            }
                break;
            case _PROPERTY_TYPE_Double: {
                double value = 0;
                [invocation getArgument:&value atIndex:2];
                obj = [NSNumber numberWithDouble:value];
            }
                break;
            case _PROPERTY_TYPE_NSString: {
                __unsafe_unretained NSString * string = nil;
                [invocation getArgument:&string atIndex:2];
                if (string) {
                    obj = string;
                }
            }
                break;
            case _PROPERTY_TYPE_NSDate: {
                __unsafe_unretained NSDate * date = nil;
                [invocation getArgument:&date atIndex:2];
                if (date) {
                    obj = date;
                }
            }
                break;
            case _PROPERTY_TYPE_NSData: {
                __unsafe_unretained NSData * data = nil;
                [invocation getArgument:&data atIndex:2];
                if (data) {
                    obj = data;
                }
            }
                break;
            case _PROPERTY_TYPE_NSDictionary: {
                __unsafe_unretained NSDictionary * dict;
                [invocation getArgument:&dict atIndex:2];
                if (dict) {
                    obj = dict;
                }
            }
                break;
            case _PROPERTY_TYPE_NSArray: {
                __unsafe_unretained NSArray * array = nil;
                [invocation getArgument:&array atIndex:2];
                if (array) {
                    obj = array;
                }
            }
                break;
            case _PROPERTY_TYPE_MQFMDBObject:{
                __unsafe_unretained MQFMDBObject * object = nil;
                [invocation getArgument:&object atIndex:2];
                if (object) {
                    obj = object;
                }
                [self.dbObjectIdDict removeObjectForKey:key];
            }
                break;
            default:
                break;
        }
        
        [self willChangeValueForKey:key];
        if (obj) {
            [self.propertyDict setObject:obj forKey:key];
        } else {
            [self.propertyDict removeObjectForKey:key];
        }
        [self didChangeValueForKey:key];
        
        [self markUpdateStatus];
        
    } else {
        // GET
        void * value = NULL;
        if (!self.propertyDict || property_type == _PROPERTY_TYPE_Invalid) {
            [invocation setReturnValue:&value];
            return;
        }
        
        switch (property_type) {
            case _PROPERTY_TYPE_Int: {
                NSNumber * num = [self.propertyDict objectForKey:key];
                if (0) {
                } else if (strcmp(@encode(short), encode_str) == 0) {
                    short value = [num shortValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(unsigned short), encode_str) == 0) {
                    unsigned short value = [num unsignedShortValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(int), encode_str) == 0) {
                    int value = [num intValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(unsigned int), encode_str) == 0) {
                    unsigned int value = [num unsignedIntValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(long), encode_str) == 0) {
                    long value = [num longValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(unsigned long), encode_str) == 0) {
                    unsigned long value = [num unsignedLongValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(long long), encode_str) == 0) {
                    long long value = [num longLongValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(unsigned long long), encode_str) == 0) {
                    unsigned long long value = [num unsignedLongLongValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(NSInteger), encode_str) == 0) {
                    NSInteger value = [num integerValue];
                    [invocation setReturnValue:&value];
                } else if (strcmp(@encode(NSUInteger), encode_str) == 0) {
                    NSUInteger value = [num unsignedIntegerValue];
                    [invocation setReturnValue:&value];
                }
                return;
            }
                break;
            case _PROPERTY_TYPE_BOOL: {
                NSNumber * num = [self.propertyDict objectForKey:key];
                BOOL value = [num boolValue];
                [invocation setReturnValue:&value];
                return;
            }
                break;
            case _PROPERTY_TYPE_Float: {
                NSNumber * num = [self.propertyDict objectForKey:key];
                float value = [num floatValue];
                [invocation setReturnValue:&value];
                return;
            }
                break;
            case _PROPERTY_TYPE_Double: {
                NSNumber * num = [self.propertyDict objectForKey:key];
                double value = [num doubleValue];
                [invocation setReturnValue:&value];
                return;
            }
                break;
            case _PROPERTY_TYPE_MQFMDBObject: {
                
                id obj = [self.propertyDict objectForKey:key];
                if (obj) {
                    value = (__bridge void *)(obj);
                    break;
                }
                if (!self.affiliationDB) return;
                
                NSString * attibutes = [NSString stringWithUTF8String:property_getAttributes(t)];
                NSArray * attibutesList = [attibutes componentsSeparatedByString:@","];
                NSString * class = [attibutesList firstObject];
                class = [class substringWithRange:NSMakeRange(3, class.length - 4)];
                
                // -- NSInvocation
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
                SEL selector = @selector(_queryTable:condition:values:);
#pragma clang diagnostic pop
                
                Method method = class_getInstanceMethod([MQFMDB class], selector);
                
                NSInvocation * invocation = [NSInvocation invocationWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]];
                invocation.target = self.affiliationDB;
                invocation.selector = selector;
                
                Class cls = objc_getClass([class UTF8String]);
                [invocation setArgument:(void *)&cls atIndex:2];
                
                NSString * condition = [NSString stringWithFormat:@"_Id == %ld", [[self.dbObjectIdDict objectForKey:key] integerValue]];
                [invocation setArgument:(void *)&condition atIndex:3];
                
                [invocation invoke];
                
                void * returnValue = nil;
                [invocation getReturnValue:&returnValue];
                
                NSArray * result = (__bridge NSArray *)(returnValue);
                if (result.count) {
                    [self.propertyDict setObject:[result firstObject] forKey:key];
                    
                    obj = [result firstObject];
                    value = (__bridge void *)(obj);
                }
                
                [self.dbObjectIdDict removeObjectForKey:key];
            }
                break;
            default: {
                NSObject * obj = [self.propertyDict objectForKey:key];
                value = (__bridge void *)(obj);
            }
                break;
        }
        [invocation setReturnValue:&value];
    }
}


// MARK: - Description
/**
 重写生成描述
 
 @return
 */
- (NSString *)description {
    
    NSMutableString * des = [[NSMutableString alloc] initWithFormat:@"%@\n", [super description]];
    [self allDescription:[self class] outString:&des];
    return des;
}

- (void)allDescription:(Class)cls outString:(NSMutableString * __autoreleasing *)outString {
    
    __weak __typeof (self) weakSelf = self;
    [[self class] enumAllPropertyWithClass:cls execute:^(const char *propertyName, _PROPERTY_TYPE propertyType, SQLITE_FIELD_TYPE fieldType, objc_property_t property) {
        
        id obj = [weakSelf.propertyDict objectForKey:[NSString stringWithUTF8String:propertyName]];
        if (propertyType == _PROPERTY_TYPE_MQFMDBObject) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            obj = [weakSelf performSelector:sel_getUid(propertyName)];
#pragma clang diagnostic pop
        }
        [*outString appendFormat:@"%s : %@ \n",propertyName, obj];
    }];
}

// MARK: - Insert / Update
/**
 *  生成插入当前对象的数据库语句
 *
 *  @return
 */
- (NSString *)objectInsertCommandValues:(NSArray *__autoreleasing *)outValues {
    
    if (self.propertyDict.allKeys.count <= 0) {
        return nil;
    }
    
    NSMutableString * command = [[NSMutableString alloc] init];
    [command appendFormat:@"INSERT INTO \"%@\" (", [[self class] tablename]];
    
    NSArray * allKey = [self.propertyDict allKeys];
    NSMutableArray * mValues = [NSMutableArray array];
    for (NSString * key in allKey) {
        
        [command appendFormat:@"%@,", key];
        
        id object = [self.propertyDict objectForKey:key];
        if ([object isKindOfClass:[MQFMDBObject class]]) {
            [mValues addObject:[NSNumber numberWithInteger:((MQFMDBObject *)object)._Id]];
            
        } else if ([object isKindOfClass:[NSDictionary class]] ||
                   [object isKindOfClass:[NSArray class]]) {
            NSData * jsonData = _ObjectEncodeJsonData(object);
            if (jsonData)
                [mValues addObject:jsonData];
            
        } else {
            [mValues addObject:object];
        }
    }
    if ([command hasSuffix:@","]) {
        [command deleteCharactersInRange:NSMakeRange(command.length - 1, 1)];
    }
    [command appendString:@") VALUES ("];
    
    for (int i = 0; i < allKey.count; i ++) {
        [command appendString:@"?,"];
    }
    if ([command hasSuffix:@","]) {
        [command deleteCharactersInRange:NSMakeRange(command.length - 1, 1)];
    }
    [command appendString:@") "];
    
    *outValues = [[NSArray alloc] initWithArray:mValues];
    return command;
    
}

/**
 *  生成更新当前对象的数据库语句
 *
 *  @return
 */
- (NSString *)objectUpdateCommandValues:(NSArray *__autoreleasing *)outValues {
    
    if (self.propertyDict.allKeys.count <= 0) {
        return nil;
    }
    NSMutableString * command = [[NSMutableString alloc] init];
    [command appendFormat:@"UPDATE \"%@\" SET ", [[self class] tablename]];
    
    
    NSMutableArray * mChangeValues = [NSMutableArray array];
    for (NSString * key in self.initialPropertyDictKeys) {
        
        id newObject = [self.propertyDict objectForKey:key];
        
        if (newObject == nil) {
            [command appendFormat:@"'%@' = NULL,", key];
            continue;
        }
        
        [command appendFormat:@"'%@' = ?,", key];
        if ([newObject isKindOfClass:[MQFMDBObject class]]) {
            [mChangeValues addObject:[NSNumber numberWithInteger:((MQFMDBObject *)newObject)._Id]];
            
        } else if ([newObject isKindOfClass:[NSDictionary class]] ||
                   [newObject isKindOfClass:[NSArray class]]) {
            NSData * jsonData = _ObjectEncodeJsonData(newObject);
            if (jsonData)
                [mChangeValues addObject:jsonData];
            
        } else {
            [mChangeValues addObject:newObject];
        }
    }
    
    if ([command hasSuffix:@","]) {
        [command deleteCharactersInRange:NSMakeRange(command.length - 1, 1)];
    }
    
    [command appendFormat:@" WHERE _Id = '%@'", [self.propertyDict objectForKey:@"_Id"]];
    *outValues = [[NSArray alloc] initWithArray:mChangeValues];
    return command;
}


// MARK: - Class Method
/**
 *  当前实体对应表名
 */
+ (NSString *)tablename {
    return NSStringFromClass([self class]);
}

/**
 *  生成当前表创建命令
 *
 *  @return
 */
+ (NSString *)tableCreateCommand {
    
    NSMutableString * command = [[NSMutableString alloc] init];
    [command appendFormat:@"CREATE TABLE %@ (", [self tablename]];
    
    [self tableCreateCommand:[self class] command:&command];
    
    if ([command hasSuffix:@","]) {
        [command deleteCharactersInRange:NSMakeRange(command.length - 1, 1)];
    }
    [command appendFormat:@")"];
    
    return command;
}

+ (void)tableCreateCommand:(Class)cls command:(NSMutableString * __autoreleasing *)command {
    
    [self enumAllPropertyWithClass:cls execute:^(const char *propertyName, _PROPERTY_TYPE propertyType, SQLITE_FIELD_TYPE fieldType, objc_property_t property) {
        
        if (strcmp(propertyName, "_Id") == 0) {
            [*command appendFormat:@"%s INTEGER PRIMARY KEY,", propertyName];
        } else {
            [*command appendFormat:@"%s %@,", propertyName, SQLITE_FIELD_TYPE_STR(fieldType)];
        }
    }];
}

/**
 *  当前类的实列属性
 *
 *  @return
 */
+ (NSArray <NSString *> *)instanceAttributes {
    
    static NSMutableDictionary * AttributeSetDict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AttributeSetDict = [[NSMutableDictionary alloc] init];
    });
    
    NSString * key = NSStringFromClass(self);
    NSArray * array = [AttributeSetDict objectForKey:key];
    if (array) {
        return array;
    }
    
    NSMutableSet * mSet = [[NSMutableSet alloc] init];
    __weak __typeof(mSet) weakSet = mSet;
    [self enumAllPropertyWithClass:[self class] execute:^(const char *propertyName, _PROPERTY_TYPE propertyType, SQLITE_FIELD_TYPE fieldType, objc_property_t property) {
        __strong __typeof (weakSet) strongSet = weakSet;
        [strongSet addObject:[NSString stringWithUTF8String:propertyName]];
    }];
    
    array = [mSet allObjects];
    [AttributeSetDict setObject:array forKey:key];
    return array;
}

+ (void)enumAllPropertyWithClass:(Class)cls execute:(void (^) (const char *propertyName, _PROPERTY_TYPE propertyType, SQLITE_FIELD_TYPE fieldType, objc_property_t property))execute {
    
    if (![NSStringFromClass(cls) isEqualToString:@"MQFMDBObject"]) {
        [self enumAllPropertyWithClass:[cls superclass] execute:execute];
    }
    
    u_int count;
    objc_property_t * propertyList = class_copyPropertyList(cls, &count);
    
    for (u_int i = 0; i < count; i ++) {
        
        const char * name = property_getName(propertyList[i]);
        
        _PROPERTY_TYPE outPropertyType;
        SQLITE_FIELD_TYPE outFieldType;
        
        [self lookupProperty:propertyList[i] outPropertyType:&outPropertyType outSqliteType:&outFieldType outEncodeStr:nil];
        if (outFieldType == SQLITE_FIELD_TYPE_INVALID) continue;
        
        if (strcmp(name, "hash") == 0 ||
            strcmp(name, "superclass") == 0 ||
            strcmp(name, "description") == 0 ||
            strcmp(name, "debugDescription") == 0) {
            continue;
        }
        
        if (execute) {
            execute (name, outPropertyType, outFieldType, propertyList[i]);
        }
    }
    free (propertyList);
    execute = nil;
}

/**
 检查属性
 
 @param property
 @param outPropertyType 属性类型
 @param outFieldType SQL类型
 */
+ (void)lookupProperty:(objc_property_t)property outPropertyType:(_PROPERTY_TYPE *)outPropertyType outSqliteType:(SQLITE_FIELD_TYPE *)outSqliteType outEncodeStr:(char **)outEncodeStr {
    NSString * attibutes = [NSString stringWithUTF8String:property_getAttributes(property)];
    NSArray * attibutesList = [attibutes componentsSeparatedByString:@","];
    
    *outPropertyType = _PROPERTY_TYPE_Invalid;
    *outSqliteType = SQLITE_FIELD_TYPE_INVALID;
    
    BOOL isDynamic = NO;
    for (NSString * str in attibutesList) {
        if ([str isEqualToString:@"D"]) {
            isDynamic = YES;
            break;
        }
    }
    if (!isDynamic) {
        return;
    }
    
    NSString * type = [attibutesList firstObject];
    const char * c_type = [[type substringWithRange:NSMakeRange(1, type.length - 1)] UTF8String];
    if (outEncodeStr != NULL) {
        *outEncodeStr = (char *)c_type;
    }
    
    if (strcmp(c_type, @encode(NSInteger))              == 0 ||
        strcmp(c_type, @encode(NSUInteger))             == 0 ||
        strcmp(c_type, @encode(int))                    == 0 ||
        strcmp(c_type, @encode(unsigned int))           == 0 ||
        strcmp(c_type, @encode(long))                   == 0 ||
        strcmp(c_type, @encode(unsigned long))          == 0 ||
        strcmp(c_type, @encode(long long))              == 0 ||
        strcmp(c_type, @encode(unsigned long long))     == 0 ||
        strcmp(c_type, @encode(short))                  == 0 ||
        strcmp(c_type, @encode(unsigned short))         == 0) {
        *outSqliteType = SQLITE_FIELD_TYPE_INTEGER;
        *outPropertyType = _PROPERTY_TYPE_Int;
        return;
    }
    
    if ([type isEqualToString:@"T@\"NSString\""]) {
        *outSqliteType = SQLITE_FIELD_TYPE_VARCHAR;
        *outPropertyType = _PROPERTY_TYPE_NSString;
        return;
    }
    
    if ([type isEqualToString:@"T@\"NSDate\""]) {
        *outSqliteType = SQLITE_FIELD_TYPE_DATE;
        *outPropertyType = _PROPERTY_TYPE_NSDate;
        return;
    }
    
    if ([type isEqualToString:@"T@\"NSData\""]) {
        *outSqliteType = SQLITE_FIELD_TYPE_BLOB;
        *outPropertyType = _PROPERTY_TYPE_NSData;
        return;
    }
    
    if ([type isEqualToString:@"T@\"NSDictionary\""]) {
        *outSqliteType = SQLITE_FIELD_TYPE_BLOB;
        *outPropertyType = _PROPERTY_TYPE_NSDictionary;
        return;
    }
    
    if ([type isEqualToString:@"T@\"NSArray\""]) {
        *outSqliteType = SQLITE_FIELD_TYPE_BLOB;
        *outPropertyType = _PROPERTY_TYPE_NSArray;
        return;
    }
    
    if (strcmp(c_type, @encode(BOOL)) == 0) {
        *outSqliteType = SQLITE_FIELD_TYPE_BOOLEAN;
        *outPropertyType = _PROPERTY_TYPE_BOOL;
        return;
    }
    
    if (strcmp(c_type, @encode(float)) == 0) {
        *outSqliteType = SQLITE_FIELD_TYPE_FLOAT;
        *outPropertyType = _PROPERTY_TYPE_Float;
        return;
    }
    
    if (strcmp(c_type, @encode(double)) == 0) {
        *outSqliteType = SQLITE_FIELD_TYPE_DOUBLE;
        *outPropertyType = _PROPERTY_TYPE_Double;
        return;
    }
    
    /** 判断是否是 MQFMDBObject 类型 */
    NSString * class = [attibutesList firstObject];
    class = [class substringWithRange:NSMakeRange(3, class.length - 4)];
    
    Class cls = class_getSuperclass(objc_getClass([class UTF8String]));
    while (cls != [MQFMDBObject class] && cls != [NSObject class]) {
        cls = class_getSuperclass(objc_getClass([class UTF8String]));
    }
    
    if ([MQFMDBObject class] == cls) {
        *outSqliteType = SQLITE_FIELD_TYPE_INTEGER;
        *outPropertyType = _PROPERTY_TYPE_MQFMDBObject;
    }
    
}

@end

