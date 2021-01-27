//
//  MQFMDB.h
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import <FMDB.h>
#import "MQFMDBObject.h"


/**
 *  此类在FMDB上封装了一层让数据库操作更简单
 *  除了查询要写条件之外 基本不需要写SQL语句
 *
 *  本类方法所有参数cls 为 [MQFMDBObject class] 或继承 MQFMDBObject 的子类 class
 */
@class MQFMDBConfig;
@interface MQFMDB : NSObject

/** 当前数据库配置信息 */
@property (nonatomic, readonly) MQFMDBConfig * dbConfig;
/** 当前数据库版本 */
@property (nonatomic, readonly) NSString * version;
@property (nonatomic, readonly) FMDatabase * database;


/**
 *  根据配置文件初始化数据库
 *
 *  @param configFile 数据库配置文件
 *
 *  @return
 */
- (instancetype)initWithConfigContent:(NSString *)configContent;

/**
 *  打开数据库
 *
 *  @return
 */
- (BOOL)openDatabaseWithOpertions:(void (^) (MQFMDB * db))opertions;

/**
 打开数据库

 @param forceOpen 如果数据库升级失败, 是否强制打开
 @param opertions 在此block里面进行insertNewTable操作
 @return
 */
- (BOOL)openDataBaseWithForceOpenIfUpgradeFail:(BOOL)forceOpen opertions:(void (^) (MQFMDB * db))opertions;

/**
 *  关闭数据库
 */
- (void)closeDatabase;

/**
 *  判断表是否存在
 *
 *  @param cls
 *
 *  @return
 */
- (BOOL)tableExists:(Class)cls;

/**
 *  插入一张表到数据库
 *
 *  @param tableName
 *
 *  @return
 */
- (BOOL)insertNewTable:(Class)cls;

/**
 *  插入一条数据到指定表
 *
 *  @param tableName 表名
 *
 *  @return 返回插入的数据
 */
- (__kindof MQFMDBObject *)insertNewObjectForTable:(Class)cls;

/**
 *  插入一条数据到指定表
 *
 *  @param cls        表名
 *  @param dictionary 赋值字典
 *
 *  @return
 */
- (__kindof MQFMDBObject *)insertNewObjectForTable:(Class)cls withDictionary:(NSDictionary *)dictionary;

/**
 *  删除一条数据
 *
 *  @param object
 */
- (BOOL)deleteObject:(MQFMDBObject *)object;

/**
 *  批量删除数据
 *
 *  @param objects
 *  @param completion
 */
- (void)deleteObjects:(NSArray <MQFMDBObject *> *)objects;

/**
 *  从内存缓冲中删除 缓存的 object
 *
 *  @param object
 */
- (void)deleteCacheObject:(MQFMDBObject *)object;

/**
 清空缓存
 */
- (void)clearCache;

/**
 删除一张表数据
 
 @param cls
 */
- (BOOL)deleteTable:(Class)cls;

/**
 删除一张表
 
 @param cls
 @return
 */
- (BOOL)dropTable:(Class)cls;

/**
 *  保存所有操作 - 删除不需要调用
 */
- (void)saveOpertion;

/**
 *  查询一个表有多少条数据
 *
 *  @param cls
 *
 *  @return
 */
- (NSInteger)countTable:(Class)cls;

/**
 *  查询一个表有多少条数据
 *
 *  @param cls
 *  @param condition 条件
 *
 *  @return
 */
- (NSInteger)countTable:(Class)cls condition:(NSString *)condition;

/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *
 *  @return 数组形式
 */
- (NSArray *)queryTable:(Class)cls condition:(NSString *)condition;


/// 查询数据库
/// @param cls
/// @param condition 查询条件
/// @param values 以?占位的值
- (NSArray *)queryTable:(Class)cls condition:(NSString *)condition values:(NSArray *)values;

/// 查询数据库并获取第一个查询到的值
/// @param cls
/// @param condition 查询条件
- (MQFMDBObject *)firstQueryTable:(Class)cls condition:(NSString *)condition;

/// 查询数据库并获取第一个查询到的值
/// @param cls
/// @param condition 查询条件
/// @param values 以?占位的值
- (MQFMDBObject *)firstQueryTable:(Class)cls condition:(NSString *)condition values:(NSArray *)values;

/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *
 *  @return 字典形式 key 是cls 加上他的 id 比如 MQFMDBObject_1
 */
- (NSDictionary <NSString *, MQFMDBObject *> *)dict_queryTable:(Class)cls condition:(NSString *)condition;

/**
 *  查询数据库
 *
 *  @param cls
 *  @param condition 查询条件
 *  @param field 使用字段做key 如果为nil key 是cls 加上他的 id 比如 MQFMDBObject_1
 *
 *  @return
 */
- (NSDictionary <NSString *, MQFMDBObject *> *)dict_queryTable:(Class)cls condition:(NSString *)condition keyWithField:(NSString *)field;
@end


@interface MQFMDBConfig : NSObject

@property (nonatomic, readonly) NSString * identify;
@property (nonatomic, readonly) NSString * version;

@property (nonatomic, readonly) NSString * key;
@property (nonatomic, readonly) NSString * dbDir;
@property (nonatomic, readonly) NSString * dbPath;

@property (nonatomic, readonly) NSDictionary * upgradeConfig;
@end


@interface MQFMDB (Config)
- (MQFMDBConfig *)readConfigContent:(NSString *)configString;
@end
