//
//  MQFMDBObject.h
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MQFMDBObjectState) {
    
    MQFMDBObjectStateNone,
    MQFMDBObjectStateInsert,
    MQFMDBObjectStateUpdate,
};


/**
 数据模型 需要继承此类
 属性需要声明 @dynamic 才会当成 column
 属性名不能大写开头
 
 目前支持数据类型 NSInteger NSString NSDate NSData BOOL float double MQFMDBObject NSDictionary NSArray
 */

@class MQFMDB;
@interface MQFMDBObject : NSObject

+ (MQFMDBObject *)objectWithDictionary:(NSDictionary *)dictionary inDB:(MQFMDB *)inDB;

@property (nonatomic, weak, readonly) MQFMDB * affiliationDB;
/** 主键ID 不能改属性名 */
@property (nonatomic, assign, readonly) NSUInteger _Id;
/** 当前状态 */
@property (nonatomic, assign, readonly) MQFMDBObjectState objectState;

/**
 *  生成插入当前对象的数据库语句
 *
 *  @return
 */
- (NSString *)objectInsertCommandValues:(NSArray **)outValues;

/**
 *  生成更新当前对象的数据库语句
 *
 *  @return
 */
- (NSString *)objectUpdateCommandValues:(NSArray **)outValues;

/**
 *  表名
 *
 *  @return
 */
+ (NSString *)tablename;


/**
 *  生成当前表创建命令
 *
 *  @return
 */
+ (NSString *)tableCreateCommand;

/**
 *  当前类的实列属性
 *
 *  @return
 */
+ (NSArray <NSString *> *)instanceAttributes;
@end

