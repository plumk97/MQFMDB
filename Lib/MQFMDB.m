//
//  MQFMDB.m
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import "MQFMDB.h"
#import "MQFMDBIDAutoincrement.h"
#import <UIKit/UIApplication.h>

@interface MQFMDB () {
    
    dispatch_queue_t _opertion_queue_t;
}
@property (nonatomic, strong) FMDatabase * database;

@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBIDAutoincrement *> * autoincrements;
@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBObject *> * objects;
@property (nonatomic, strong) NSMutableDictionary <NSString *, MQFMDBObject *> * waiteOpertionObjects;

@end


@implementation MQFMDB
@synthesize dbConfig = _dbConfig;

// MARK: - Class Method
+ (NSString *)MQFMDBFolder {
    
    NSString * document = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString * folder = [document stringByAppendingPathComponent:@"MQFMDB"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return folder;
}

+ (NSString *)MQFMDBVersionCachePath {
    
    static NSString * versionCachePath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versionCachePath = [[self MQFMDBFolder] stringByAppendingPathComponent:@"MQFMDBVersionCache.plist"];
    });
    return versionCachePath;
}

+ (NSMutableDictionary *)versionCacheDict {
    
    static NSMutableDictionary * MQFMDBVersionCacheDict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        MQFMDBVersionCacheDict = [[NSMutableDictionary alloc] initWithContentsOfFile:[MQFMDB MQFMDBVersionCachePath]];
        if (!MQFMDBVersionCacheDict) {
            MQFMDBVersionCacheDict = [[NSMutableDictionary alloc] init];
        }
    });
    return MQFMDBVersionCacheDict;
}

+ (void)synchronizeVersionCache {
    if (MQFMDB.versionCacheDict) {
        [MQFMDB.versionCacheDict writeToFile:[self MQFMDBVersionCachePath] atomically:YES];
    }
}


// -----------------------
- (id)initWithConfigContent:(NSString *)configContent {
    
    self = [super init];
    if (self) {
        
        _opertion_queue_t = dispatch_queue_create("_opertion_queue_t", DISPATCH_QUEUE_SERIAL);
        _dbConfig = [self readConfigContent:configContent];
        self.objects = [[NSMutableDictionary alloc] init];
        self.autoincrements = [[NSMutableDictionary alloc] init];
        self.waiteOpertionObjects = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidReceiveMemoryWarningNotification:(NSNotification *)noti {
    [self clearCache];
}

- (NSMutableDictionary *)dbCacheDict {
    id obj = [MQFMDB.versionCacheDict objectForKey:self.dbConfig.identify];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        if ([obj isKindOfClass:[NSMutableDictionary class]]) {
            return obj;
        }
        
        id mobj = [obj mutableCopy];
        [MQFMDB.versionCacheDict setObject:mobj forKey:self.dbConfig.identify];
        return mobj;
    }
    
    NSMutableDictionary * mDict = [[NSMutableDictionary alloc] init];
    if ([obj isKindOfClass:[NSString class]]) {
        [mDict setObject:obj forKey:@"version"];
    }
    [MQFMDB.versionCacheDict setObject:mDict forKey:self.dbConfig.identify];
    return mDict;
}

- (NSString *)version {
    return [[self dbCacheDict] objectForKey:@"version"];
}

- (void)setVersion:(NSString *)version {
    [[self dbCacheDict] setObject:version forKey:@"version"];
}

- (NSInteger)upgradeSqlIndex {
    return [[[self dbCacheDict] objectForKey:@"upgradeSqlIndex"] integerValue];
}

- (void)setUpgradeSqlIndex:(NSInteger)index {
    [[self dbCacheDict] setObject:@(index) forKey:@"upgradeSqlIndex"];
}

// MARK: - 升级

- (NSInteger)integerForVersion:(NSString *)version {
    return [[version stringByReplacingOccurrencesOfString:@"." withString:@""] integerValue];
}

- (BOOL)executeUpgradeCommands:(NSArray <NSString *> *)commands  {
    if (!commands) return YES;
    
    for (NSInteger i = [self upgradeSqlIndex]; i < commands.count; i ++) {
        
        
        if (![self.database executeUpdate:commands[i]]) {
            [self setUpgradeSqlIndex:i];
            [MQFMDB synchronizeVersionCache];
            return NO;
        }
        
        [self setUpgradeSqlIndex:i + 1];
        [MQFMDB synchronizeVersionCache];
    }
    
    [self setUpgradeSqlIndex:0];
    [MQFMDB synchronizeVersionCache];
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
            
            BOOL isOk = [self executeUpgradeCommands:[[self.dbConfig.upgradeConfig objectForKey:key] objectForKey:@"commands"]];
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
            [MQFMDB synchronizeVersionCache];
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
    [self.waiteOpertionObjects setObject:object forKey:[[self class] keyWithClass:[object class] _Id:object._Id]];
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
    
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
    dispatch_barrier_sync(_opertion_queue_t, ^{
        NSString * cur = [cls tableCreateCommand];
        if (!isSucceed) {
            isSucceed = [self.database executeUpdate:cur];
        }
    });
    return isSucceed;
}

+ (BOOL)equalCreateString:(NSString *)str1 createString2:(NSString *)str2 {
    
    str1 = [[[str1 componentsSeparatedByString:@"("] lastObject] stringByReplacingOccurrencesOfString:@")" withString:@""];
    str2 = [[[str2 componentsSeparatedByString:@"("] lastObject] stringByReplacingOccurrencesOfString:@")" withString:@""];
    
    NSArray * arr1 = [str1 componentsSeparatedByString:@","];
    NSArray * arr2 = [str2 componentsSeparatedByString:@","];
    
    if (arr1.count != arr2.count) {
        return NO;
    }
    return YES;
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
    
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
        [self.waiteOpertionObjects setObject:object forKey:key];
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
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
        [self.waiteOpertionObjects removeObjectForKey:key];
        isSucceed = YES;
    }
    
    if (!isSucceed) {
        NSString * command = [NSString stringWithFormat:@"DELETE FROM %@ WHERE _Id = %ld",[[object class] tablename], object._Id];
        
        isSucceed = [self.database executeUpdate:command];
        if (isSucceed) {
            [self.objects removeObjectForKey:key];
            [self.waiteOpertionObjects removeObjectForKey:key];
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
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
    
    dispatch_barrier_sync(_opertion_queue_t, ^{
        NSString * key = [MQFMDB keyWithClass:[object class] _Id:object._Id];
        [self.objects removeObjectForKey:key];
    });
}

/**
 清空缓存
 */
- (void)clearCache {
    [self saveOpertion];
    dispatch_barrier_sync(_opertion_queue_t, ^{
        [self.waiteOpertionObjects removeAllObjects];
        [self.objects removeAllObjects];
    });
}
/**
 删除一张表数据
 
 @param cls
 */
- (BOOL)deleteTable:(Class)cls {
    
    __block BOOL succeed = NO;
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
    
    
    dispatch_barrier_sync(_opertion_queue_t, ^{
        if (self.waiteOpertionObjects.count == 0) {
            return;
        }
        
        BOOL isTransaction = NO;
        if (self.waiteOpertionObjects.count > 1) {
            [self.database beginTransaction];
            isTransaction = YES;
        }
        
        @try {
            for (MQFMDBObject * object in self.waiteOpertionObjects.allValues) {
                
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
            [self.waiteOpertionObjects removeAllObjects];
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
    dispatch_barrier_sync(_opertion_queue_t, ^{
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
    dispatch_barrier_sync(_opertion_queue_t, ^ {
        
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
@synthesize dbPath = _dbPath;

@synthesize upgradeConfig = _upgradeConfig;

- (void)readConfigString:(NSString *)configString {
    
    NSDictionary * configDict = [NSJSONSerialization JSONObjectWithData:[configString dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
    
    _identify = [configDict objectForKey:@"identify"];
    _version = [configDict objectForKey:@"version"];
    
    _dbPath = [configDict objectForKey:@"path"];
    
    _dbPath = [_dbPath stringByReplacingOccurrencesOfString:@"<App>" withString:[[NSBundle mainBundle] bundlePath]];
    _dbPath = [_dbPath stringByReplacingOccurrencesOfString:@"<MQFMDB>" withString:[MQFMDB MQFMDBFolder]];
    
    _key = [configDict objectForKey:@"key"];
    _upgradeConfig = [configDict objectForKey:@"upgrade"];
}



@end

@implementation MQFMDB (Config)

- (MQFMDBConfig *)readConfigContent:(NSString *)configString {
    
    MQFMDBConfig * config = [[MQFMDBConfig alloc] init];
    [config readConfigString:configString];
    return config;
}
@end