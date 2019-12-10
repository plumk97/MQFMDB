//
//  MQFMDBIDAutoincrement.h
//  MQFMDBExample
//
//  Created by li on 16/3/4.
//  Copyright © 2016年 li. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MQFMDBIDAutoincrement : NSObject

- (id)initWithStartId:(NSInteger)startId;

- (NSInteger)next;

@end
