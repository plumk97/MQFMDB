//
//  TDMessage.h
//  MQFMDB
//
//  Created by li on 16/3/3.
//  Copyright © 2016年 li. All rights reserved.
//

#import "MQFMDBObject.h"
#import "TDSession.h"

@interface TDMessage : MQFMDBObject

@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) NSInteger state;
@property (nonatomic, assign) BOOL isSender;

@property (nonatomic, strong) NSDate * time;
@property (nonatomic, strong) NSData * data;
@property (nonatomic, copy) NSString * content;

@property (nonatomic, assign) float latitude;
@property (nonatomic, assign) double longitude;

@property (nonatomic, strong) NSDictionary * params;
@property (nonatomic, strong) NSArray * array;

@property (nonatomic, strong) TDSession * session;

@end
