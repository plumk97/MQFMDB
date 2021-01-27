//
//  MQFMDB.m
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import "MQFMDB.h"
#import "MQFMDBIDAutoincrement.h"

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIApplication.h>
#endif

@interface MQFMDB () {
    
    dispatch_queue_t _sql_queue_t;
    dispatch_queue_t _wait_operation_objects_queue_t;
}
@property (nonatomic, strong) FMDatabase * database;

@property (nonatomic, strong) NSMutableDictionary * configDict;
@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBIDAutoincrement *> * autoincrements;
@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBObject *> * objects;
@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBObject *> * waitOperationObjects;

@end


@implementation MQFMDB
@synthesize dbConfig = _dbConfig;

// MARK: - Class Method
/// 获取Document目录
+ (NSString *)documentDir {
    NSString * documentDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return documentDir;
}

// -----------------------
- (id)initWithConfigContent:(NSString *)configContent {
    
    self = [super init];
    if (self) {
        
        _sql_queue_t = dispatch_queue_create("_sql_queue_t", DISPATCH_QUEUE_SERIAL);
        _wait_operation_objects_queue_t = dispatch_queue_create("_wait_operation_objects_queue_t", DISPATCH_QUEUE_SERIAL);
        
        _dbConfig = [self readConfigContent:configContent];
        self.objects = [[NSMutableDictionary alloc] init];
        self.autoincrements = [[NSMutableDictionary alloc] init];
        self.waitOperationObjects = [[NSMutableDictionary alloc] init];
        
        self.configDict = [[NSMutableDictionary alloc] initWithContentsOfFile: self.configDictCachePath];
        if (!self.configDict) {
            self.configDict = [[NSMutableDictionary alloc] init];
        }
        
#if !TARGET_OS_OSX
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidReceiveMemoryWarningNotification:(NSNotification *)noti {
    [self clearCache];
}

- (NSString *)configDictCachePath {
    return [self.dbConfig.dbDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_VersionCache.plist", self.dbConfig.identify]];
}

- (void)synchronizeVersionCache {
    if (self.configDict) {
        [self.configDict writeToFile:[self configDictCachePath] atomically:YES];
    }
}

- (NSString *)version {
    return [[self configDict] objectForKey:@"version"];
}

- (void)setVersion:(NSString *)version {
    [[self configDict] setObject:version forKey:@"version"];
}


// MARK: - 升级

- (NSInteger)integerForVersion:(NSString *)version {
    return [[version stringByReplacingOccurrencesOfString:@"." withString:@""] integerValue];
}

- (BOOL)executeUpgradeScript:(NSString *)scriptFile {

    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:scriptFile];
    if (!isExist) {
        return NO;
    }

    NSError * error;
    NSString * content = [[NSString alloc] initWithContentsOfFile:scriptFile encoding:NSUTF8StringEncoding error:&error];
    if (error != nil) {
        NSLog(@"%@", error);
        return NO;
    }
    [self.database beginTransaction];
    
    NSArray<NSString *> * statements = [content componentsSeparatedByString:@";"];
    for (NSString * statement in statements) {
        BOOL isOK = [self.database executeStatements:statement];
        
        // 防止跨版本升级 某些表在旧版本不存在报错 导致升级失败 也有可能会有其他问题
        if ([self.database.lastErrorMessage hasPrefix:@"no such table"]) {
            isOK = YES;
        }
        
        if (!isOK) {
            [self.database rollback];
            return NO;
        }
    }
    
    [self.database commit];
    return YES;
}

/**
 升级数据库
 
 @return
 */
- (BOOL)upgradeDatabase {
    
    NSString * version = self.version;
    if (!version) return YES;
    
    NSString * newVersion = self.dbConfig.version;
    if ([version isEqualToString:newVersion] || [self integerForVersion:version] >= [self integerForVersion:newVersion]) return YES;
    
    NSArray <NSString *> * keys = [self.dbConfig.upgradeConfig.allKeys sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [self integerForVersion:obj1] < [self integerForVersion:obj2] ? NSOrderedAscending : NSOrderedDescending;
    }];
    
    NSInteger i_version = [self integerForVersion:version];
    for (NSString * key in keys) {
        NSInteger i_key = [self integerForVersion:key];
        if (i_version <= i_key) {

            NSString * scriptPath = [[self.dbConfig.upgradeConfig objectForKey:key] objectForKey:@"script"];
            if (scriptPath.length <= 0) {
                continue;
            }
            
#if !TARGET_OS_OSX
            if ([scriptPath hasPrefix:@"<App>"]) {
                scriptPath = [scriptPath stringByReplacingOccurrencesOfString:@"<App>" withString:[[NSBundle mainBundle] bundlePath]];
            } else if ([scriptPath hasPrefix:@"<MQFMDB>"]) {
                scriptPath = [scriptPath stringByReplacingOccurrencesOfString:@"<MQFMDB>" withString:[[MQFMDB documentDir] stringByAppendingPathComponent:@"MQFMDB"]];
            }
#endif
            
            BOOL isOk = [self executeUpgradeScript:scriptPath];
            
            if (!isOk) {
                return NO;
            }
            i_version = i_key;
        }
    }
    return YES;
}

// MARK: - -----

/**
 *  打开数据库
 *
 *  @return
 */
- (BOOL)openDatabaseWithOpertions:(void (^)(MQFMDB *))opertions {
    return [self openDataBaseWithForceOpenIfUpgradeFail:NO opertions:opertions];
}

/**
 打开数据库
 
 @param forceOpen 如果数据库升级失败, 是否强制打开
 @param opertions
 @return
 */
- (BOOL)openDataBaseWithForceOpenIfUpgradeFail:(BOOL)forceOpen opertions:(void (^) (MQFMDB * db))opertions {
    if (self.database) {
        [self closeDatabase];
    }
    
    self.database = [FMDatabase databaseWithPath:self.dbConfig.dbPath];
    if (![self.database open]) {
        self.database = nil;
        return  NO;
    }
    
    if (self.dbConfig.key && ![self.dbConfig.key isEqualToString:@""]) {
        [self.database setKey:self.dbConfig.key];
    }
    
    if (![self.database goodConnection]) {
        // 打开老版本数据库 SQLCipher 4.0 不兼容 3.0版本
        [self.database close];
        [self.database open];
        if (self.dbConfig.key && ![self.dbConfig.key isEqualToString:@""]) {
            [self.database setKey:self.dbConfig.key];
        }
        
        [self.database executeStatements:@"PRAGMA kdf_iter = 64000"];
        [self.database executeStatements:@"PRAGMA cipher_page_size = 1024"];
        [self.database executeStatements:@"PRAGMA cipher_hmac_algorithm = HMAC_SHA1"];
        [self.database executeStatements:@"PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA1"];
        
        if (![self.database goodConnection]) {
            return NO;
        }
    }
    
    // -- 先升级数据库
    BOOL isOK = [self upgradeDatabase];
    if (isOK || forceOpen) {
        opertions(self);
        if (isOK) {
            [self setVersion:self.dbConfig.version];
            [self synchronizeVersionCache];
        }
    } else {
        [self closeDatabase];
    }
    return isOK;
}


/**
 *  关闭数据库
 */
- (void)closeDatabase {
    [self.database close];
    self.database = nil;
}


- (void)addOneUpdateObject:(MQFMDBObject *)object {
    dispatch_sync(_wait_operation_objects_queue_t, ^{
        [self.waitOperationObjects setObject:object forKey:[[self class] keyWithClass:[object class] _Id:object._Id]];
    });
}
/**
 *  判断表是否存在
 *
 *  @param cls
 *
 *  @return
 */
- (BOOL)tableExists:(Class)cls {
    
    __block BOOL isExists = NO;
    
    dispatch_sync(_sql_queue_t, ^{
        isExists = [self.database tableExists:[cls tablename]];
    });
    return isExists;
}

/**
 *  插入一张表到数据库
 *
 *  @param tableName
 *
 *  @return
 */
- (BOOL)insertNewTable:(Class)cls {
    
    __block BOOL isSucceed = NO;
    isSucceed = [self tableExists:cls];
    dispatch_sync(_sql_queue_t, ^{
        NSString * cur = [cls tableCreateCommand];
        if (!isSucceed) {
            isSucceed = [self.database executeUpdate:cur];
        }
    });
    return isSucceed;
}

/**
 *  插入一条数据到指定表
 *
 *  @param tableName 表名
 *
 *  @return 返回插入的数据
 */
- (__kindof MQFMDBObject *)insertNewObjectForTable:(Class)cls {
    return [self insertNewObjectForTable:cls withDictionary:nil];
}

/**
 *  插入一条数据到指定表
 *
 *  @param cls        表名
 *  @param dictionary 赋值字典
 *
 *  @return
 */
- (__kindof MQFMDBObject *)insertNewObjectForTable:(Class)cls withDictionary:(NSDictionary *)dictionary {
    
    
    __block MQFMDBObject * object = nil;
    
    dispatch_sync(_sql_queue_t, ^{
        object = [cls objectWithDictionary:dictionary inDB:self];
        
        MQFMDBIDAutoincrement * autoincrement = [self getIdAutoincrementWithClass:cls];
        
        NSUInteger _id = [autoincrement next];
        if (dictionary && [dictionary objectForKey:@"_Id"]) {
            _id = [[dictionary objectForKey:@"_Id"] unsignedIntegerValue];
        }
        
        [object setValue:[NSNumber numberWithUnsignedInteger:_id] forKey:@"_Id"];
        [object setValue:[NSNumber numberWithInteger:MQFMDBObjectStateInsert] forKey:@"objectState"];
        
        NSString * key = [MQFMDB keyWithClass:cls _Id:_id];
        [self.objects setObject:object forKey:key];
        
        dispatch_sync(_wait_operation_objects_queue_t, ^{
            [self.waitOperationObjects setObject:object forKey:key];
        });
    });
    return object;
}

- (MQFMDBIDAutoincrement *)getIdAutoincrementWithClass:(Class)cls {
    
    MQFMDBIDAutoincrement * autoincrement = nil;
    NSString * key = NSStringFromClass(cls);
    autoincrement = [self.autoincrements objectForKey:key];
    if (!autoincrement) {
        
        NSInteger maxValue = [self.database intForQuery:[NSString stringWithFormat:@"SELECT MAX(_Id) FROM %@", key]];
        autoincrement = [[MQFMDBIDAutoincrement alloc] initWithStartId:maxValue];
        [self.autoincrements setObject:autoincrement forKey:key];
    }
    return autoincrement;
}

/**
 *  删除一条数据
 *
 *  @param object
 */
- (BOOL)deleteObject:(MQFMDBObject *)object {
    
    __block BOOL isSucceed = NO;
    dispatch_sync(_sql_queue_t, ^{
        isSucceed = [self _deleteObject:object];
    });
    return isSucceed;
}

- (BOOL)_deleteObject:(MQFMDBObject *)object {
    if (object._Id <= 0) {
        return NO;
    }
    
    BOOL isSucceed = NO;
    NSString * key = [MQFMDB keyWithClass:[object class] _Id:object._Id];
    if (object.objectState == MQFMDBObjectStateInsert) {
        [self.objects removeObjectForKey:key];
        dispatch_sync(_wait_operation_objects_queue_t, ^{
           [self.waitOperationObjects removeObjectForKey:key];
        });
        isSucceed = YES;
    }
    
    if (!isSucceed) {
        NSString * command = [NSString stringWithFormat:@"DELETE FROM %@ WHERE _Id = %ld",[[object class] tablename], object._Id];
        
        isSucceed = [self.database executeUpdate:command];
        if (isSucceed) {
            [self.objects removeObjectForKey:key];
            dispatch_sync(_wait_operation_objects_queue_t, ^{
               [self.waitOperationObjects removeObjectForKey:key];
            });
        }
    }
    return isSucceed;
}

/**
 *  批量删除数据
 *
 *  @param objects
 *  @param completion
 */
- (void)deleteObjects:(NSArray <MQFMDBObject *> *)objects {
    dispatch_sync(_sql_queue_t, ^{
        [self.database beginTransaction];
        for (MQFMDBObject * object in objects) {
            [self _deleteObject:object];
        }
        [self.database commit];
    });
    
}

/**
 *  从内存缓冲中删除 缓存的 object
 *
 *  @param object
 */
- (void)deleteCacheObject:(MQFMDBObject *)object {
    
    dispatch_sync(_sql_queue_t, ^{
        NSString * key = [MQFMDB keyWithClass:[object class] _Id:object._Id];
        [self.objects removeObjectForKey:key];
    });
}

/**
 清空缓存
 */
- (void)clearCache {
    [self saveOpertion];
    dispatch_sync(_sql_queue_t, ^{
        dispatch_sync(_wait_operation_objects_queue_t, ^{
           [self.waitOperationObjects removeAllObjects];
        });
        [self.objects removeAllObjects];
    });
}
/**
 删除一张表数据
 
 @param cls
 */
- (BOOL)deleteTable:(Class)cls {
    
    __block BOOL succeed = NO;
    dispatch_sync(_sql_queue_t, ^{
        for (NSString * key in self.objects.allKeys) {
            MQFMDBObject * obj = [self.objects objectForKey:key];
            if ([obj isKindOfClass:cls]) {
                [self.objects removeObjectForKey:key];
            }
        }
        succeed = [self.database executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@", [cls tablename]]];
    });
    return succeed;
}

/**
 删除一张表
 
 @param cls
 @return
 */
- (BOOL)dropTable:(Class)cls {
    __block BOOL succeed = NO;
    dispatch_sync(_sql_queue_t, ^{
        for (NSString * key in self.objects.allKeys) {
            MQFMDBObject * obj = [self.objects objectForKey:key];
            if ([obj isKindOfClass:cls]) {
                [self.objects removeObjectForKey:key];
            }
        }
        succeed = [self.database executeUpdate:[NSString stringWithFormat:@"DROP TABLE %@", [cls tablename]]];
    });
    return succeed;
}

/**
 *  保存所有操作
 */
- (void)saveOpertion {
    
    dispatch_sync(_sql_queue_t, ^{
        NSDictionary * waitOperationObjects = [self.waitOperationObjects copy];
        
        if (waitOperationObjects.count == 0) {
            return;
        }
        
        BOOL isTransaction = NO;
        if (waitOperationObjects.count > 1) {
            [self.database beginTransaction];
            isTransaction = YES;
        }
        
        @try {
            for (MQFMDBObject * object in waitOperationObjects.allValues) {
                
                if (object.objectState == MQFMDBObjectStateInsert) {
                    
                    NSArray * outValues = nil;
                    NSString * insert = [object objectInsertCommandValues:&outValues];
                    if (!insert || !outValues) {
                        continue;
                    }
                    
                    [self.database executeUpdate:insert withArgumentsInArray:outValues];
                    [object setValue:[NSNumber numberWithInteger:MQFMDBObjectStateNone] forKey:@"objectState"];
                } else if (object.objectState == MQFMDBObjectStateUpdate) {
                    
                    NSArray * outValues = nil;
                    NSString * update = [object objectUpdateCommandValues:&outValues];
                    if (!update || !outValues) {
                        continue;
                    }
                    
                    [self.database executeUpdate:update withArgumentsInArray:outValues];
                    [object setValue:[NSNumber numberWithInteger:MQFMDBObjectStateNone] forKey:@"objectState"];
                }
            }
            
            dispatch_sync(_wait_operation_objects_queue_t, ^{
                [self.waitOperationObjects removeAllObjects];
            });
            
        } @catch (NSException *exception) {
            NSLog(@"%@", exception);
        } @finally {
            
        }
        
        if (isTransaction) {
            [self.database commit];
        }
    });
    
}

/**
 *  查询一个表有多少条数据
 *
 *  @param cls
 *
 *  @return
 */
- (NSInteger)countTable:(Class)cls {
    
    return [self.database intForQuery:[NSString stringWithFormat:@"SELECT COUNT (*) FROM \"%@\"", [cls tablename]]];
}

/**
 *  查询一个表有多少条数据
 *
 *  @param cls
 *  @param condition 条件
 *
 *  @return
 */
- (NSInteger)countTable:(Class)cls condition:(NSString *)condition {
    return [self.database intForQuery:[NSString stringWithFormat:@"SELECT COUNT (*) FROM \"%@\" WHERE %@", [cls tablename], condition]];
}

/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *
 *  @return
 */
- (NSArray *)queryTable:(Class)cls condition:(NSString *)condition {
    return [self queryTable:cls condition:condition values:nil];
}

/// 查询数据库
/// @param cls
/// @param condition 查询条件
/// @param values 以?占位的值
- (NSArray *)queryTable:(Class)cls condition:(NSString *)condition values:(NSArray *)values {
    
    [self saveOpertion];
    return [self _queryTable:cls condition:condition values:values];
}

/// 查询数据库并获取第一个查询到的值
/// @param cls
/// @param condition 查询条件
- (MQFMDBObject *)firstQueryTable:(Class)cls condition:(NSString *)condition {
    return [[self queryTable:cls condition:condition] firstObject];
}

/// 查询数据库并获取第一个查询到的值
/// @param cls
/// @param condition 查询条件
/// @param values 以?占位的值
- (MQFMDBObject *)firstQueryTable:(Class)cls condition:(NSString *)condition values:(NSArray *)values {
    return [[self queryTable:cls condition:condition values:values] firstObject];
}

- (NSArray *)_queryTable:(Class)cls condition:(NSString *)condition values:(NSArray *)values {
    
    NSMutableArray * mArr = [[NSMutableArray alloc] init];
    dispatch_sync(_sql_queue_t, ^{
        NSString * query = nil;
        
        if ([condition rangeOfString:@"ORDER"].length > 0) {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@", [[cls class] tablename], condition];
        } else if (condition) {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ ORDER BY _Id", [[cls class] tablename], condition];
        } else {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ ORDER BY _Id", [[cls class] tablename]];
        }
        
        FMResultSet * result = nil;
        if (values) {
            result = [self.database executeQuery:query withArgumentsInArray:values];
        } else {
            result = [self.database executeQuery:query];
        }
        
        while ([result next]) {
            
            NSString * key = [MQFMDB keyWithClass:cls _Id:[[result.resultDictionary objectForKey:@"_Id"] integerValue]];
            MQFMDBObject * object = [self.objects objectForKey:key];
            
            if (!object) {
                object = [[cls class] objectWithDictionary:result.resultDictionary inDB:self];
                [self.objects setObject:object forKey:key];
            }
            
            [mArr addObject:object];
        }
        [result close];
    });
    return [NSArray arrayWithArray:mArr];
}


/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *
 *  @return 字典形式
 */
- (NSDictionary <NSString *, MQFMDBObject *> *)dict_queryTable:(Class)cls condition:(NSString *)condition {
    return [self dict_queryTable:cls condition:condition keyWithField:nil];
}

/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *  @param field 使用字段做key
 *
 *  @return
 */
- (NSDictionary <NSString *, MQFMDBObject *> *)dict_queryTable:(Class)cls condition:(NSString *)condition keyWithField:(NSString *)field {
    
    NSMutableDictionary * mDict = [[NSMutableDictionary alloc] init];
    dispatch_sync(_sql_queue_t, ^ {
        
        NSString * query = nil;
        if ([condition rangeOfString:@"ORDER"].length > 0) {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@", [[cls class] tablename], condition];
        } else if (condition) {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ ORDER BY _Id", [[cls class] tablename], condition];
        } else {
            query = [NSString stringWithFormat:@"SELECT * FROM %@ ORDER BY _Id", [[cls class] tablename]];
        }
        
        
        FMResultSet * result = [self.database executeQuery:query];
        
        while ([result next]) {
            
            NSString * key = [MQFMDB keyWithClass:cls _Id:[[result.resultDictionary objectForKey:@"_Id"] integerValue]];
            MQFMDBObject * object = [self.objects objectForKey:key];
            
            if (!object) {
                object = [[cls class] objectWithDictionary:result.resultDictionary inDB:self];
                [self.objects setObject:object forKey:key];
            }
            if (field) {
                [mDict setObject:object forKey:[NSString stringWithFormat:@"%@", [object valueForKey:field]]];
            } else {
                [mDict setObject:object forKey:key];
            }
        }
    });
    return [NSDictionary dictionaryWithDictionary:mDict];
}


+ (NSString *)keyWithClass:(Class)cls _Id:(NSUInteger)_Id {
    return [NSString stringWithFormat:@"%@_%ld", NSStringFromClass(cls), _Id];
}
@end



@implementation MQFMDBConfig
@synthesize identify = _identify;
@synthesize version = _version;

@synthesize key = _key;
@synthesize dbDir = _dbDir;
@synthesize dbPath = _dbPath;

@synthesize upgradeConfig = _upgradeConfig;

- (void)readConfigString:(NSString *)configString {
    
    NSDictionary * configDict = [NSJSONSerialization JSONObjectWithData:[configString dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
    
    _identify = [configDict objectForKey:@"identify"];
    _version = [configDict objectForKey:@"version"];
    _key = [configDict objectForKey:@"key"];
    _upgradeConfig = [configDict objectForKey:@"upgrade"];
    
#if TARGET_OS_OSX
    NSString * path = [configDict objectForKey:@"path"];
    _dbDir = [path stringByDeletingLastPathComponent];
    _dbPath = path;
#else
    NSString * path = [configDict objectForKey:@"path"];
    if ([path hasPrefix:@"<App>"]) {
        path = [path stringByReplacingOccurrencesOfString:@"<App>" withString:[[NSBundle mainBundle] bundlePath]];
        _dbDir = [path stringByDeletingLastPathComponent];
    } else if ([path hasPrefix:@"<MQFMDB>"]) {
        path = [path stringByReplacingOccurrencesOfString:@"<MQFMDB>" withString:[[MQFMDB documentDir] stringByAppendingPathComponent:@"MQFMDB"]];
        
        NSString * dir = [path stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _dbDir = dir;
    }
    _dbPath = path;
#endif
}



@end

@implementation MQFMDB (Config)

- (MQFMDBConfig *)readConfigContent:(NSString *)configString {
    
    MQFMDBConfig * config = [[MQFMDBConfig alloc] init];
    [config readConfigString:configString];
    return config;
}
@end
