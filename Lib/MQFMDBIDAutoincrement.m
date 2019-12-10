//
//  MQFMDBIDAutoincrement.m
//  MQFMDBExample
//
//  Created by li on 16/3/4.
//  Copyright © 2016年 li. All rights reserved.
//

#import "MQFMDBIDAutoincrement.h"

@interface MQFMDBIDAutoincrement ()

@property (nonatomic, strong) NSLock * theLock;
@property (nonatomic, assign) NSInteger currentId;
@end
@implementation MQFMDBIDAutoincrement

- (id)initWithStartId:(NSInteger)startId {
    
    self = [super init];
    if (self) {
        self.theLock = [[NSLock alloc] init];
        self.currentId = startId;
    }
    return self;
}

- (NSInteger)next {
    
    NSInteger _id = 0;
    @synchronized(self.theLock) {
        _id = ++self.currentId;
    }

    return _id;
}



@end
