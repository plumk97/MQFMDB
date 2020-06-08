//
//  ViewController.m
//  MQFMDB
//
//  Created by li on 16/3/2.
//  Copyright © 2016年 li. All rights reserved.
//

#import "ViewController.h"
#import "MQFMDB.h"
#import "TDMessage.h"

@interface ViewController ()
<UITableViewDelegate, UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic, strong) MQFMDB * userDB;

@property (nonatomic, strong) NSMutableArray <TDMessage *> * dataArray;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSLog(@"%@", [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]);
    
    NSString * configContent = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MQFMDB_Demo" ofType:@"conf"] encoding:NSUTF8StringEncoding error:nil];
//    NSString * configContent = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MQFMDB_Demo-1.0.1" ofType:@"conf"] encoding:NSUTF8StringEncoding error:nil];
    
    /** 生成数据库并且打开相关配置在conf文件 */
    self.userDB = [[MQFMDB alloc] initWithConfigContent:configContent];
    [self.userDB openDataBaseWithForceOpenIfUpgradeFail:YES opertions:^(MQFMDB *db) {
        /** 在这里创建表和其他操作 */
        [db insertNewTable:[TDMessage class]];
        [db insertNewTable:[TDSession class]];
    }];
    
    
    self.dataArray = [[NSMutableArray alloc] init];
    [self.dataArray setArray:[self.userDB queryTable:[TDMessage class] condition:nil]];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (IBAction)insertMessage:(UIButton *)sender {
    
    // 使用这种方法创建的对象才会保存进数据库
    TDSession * session = [self.userDB insertNewObjectForTable:[TDSession class]];
    session.name = @"session";

    TDMessage * message = [self.userDB insertNewObjectForTable:[TDMessage class]];
    message.session = session;
    message.type = 0xFFFF;
    message.data = [@"123" dataUsingEncoding:NSUTF8StringEncoding];
    message.state = arc4random() % 3;
    message.time = [NSDate date];
    message.content = @"插入测试";
    
    message.latitude = arc4random() % 1000;
    message.longitude = arc4random() % 1000;
    
    message.params = @{@"123":@(123), @"345" : @(345), @"params": @{@"123":@(123), @"345" : @(345)}};
    message.array = @[@"1", @"2", @"3", @"4"];
    [self.userDB saveOpertion];
    
    
    [self.tableView beginUpdates];
    
    [self.dataArray addObject:message];

    NSIndexPath * indexPath = [NSIndexPath indexPathForRow:self.dataArray.count - 1 inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
    
    [self.tableView endUpdates];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:true];
}


- (IBAction)removeMessage:(UIButton *)sender {
    
    NSIndexPath * selectedIndexPath = [self.tableView indexPathForSelectedRow];
    if (selectedIndexPath) {
        [self.tableView beginUpdates];
        TDMessage * message = [self.dataArray objectAtIndex:selectedIndexPath.row];
        [self.userDB deleteObject:message.session];
        [self.userDB deleteObject:message];
        [self.dataArray removeObjectAtIndex:selectedIndexPath.row];

        [self.tableView deleteRowsAtIndexPaths:@[selectedIndexPath] withRowAnimation:UITableViewRowAnimationLeft];
        [self.tableView endUpdates];
    }
    
}
- (IBAction)modifyMessage:(UIButton *)sender {
    
    NSIndexPath * selectedIndexPath = [self.tableView indexPathForSelectedRow];
    if (selectedIndexPath) {
        for (int i = 0; i < 10; i ++) {
            dispatch_queue_t queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT);
            for (int j = 0; j < 10; j++) {
                
                dispatch_async(queue, ^{
                    TDMessage * message = [self.dataArray objectAtIndex:selectedIndexPath.row];
                     message.type = arc4random() % 10;
                     message.state = arc4random() % 3;
                     message.time = [NSDate date];
                     message.content = nil;
                     
                     message.longitude = arc4random() % 1000;
                     message.latitude = arc4random() % 1000;
                     
                     message.params = @{@"123":@(123), @"345" : @(345), @"params": @{@"123":@(123), @"345" : @(345)}};
                     message.array = @[@"1", @"2", @"3", @"4"];
                    
                     
                     [self.userDB saveOpertion];
                });
            }
        }
//        [self.tableView reloadData];
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"UITableViewCell"];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.textLabel.numberOfLines = 0;
    
    TDMessage * message = [self.dataArray objectAtIndex:indexPath.row];
    cell.textLabel.text = [[NSString stringWithFormat:@"type: %ld, state: %ld, isSender: %d, time: %@, content: %@, latitude: %.2f, longitude: %.2f, %@, %@", message.type, message.state, message.isSender, message.time, message.content, message.latitude, message.longitude, message.params, message.array] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 150;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"%@", [self.dataArray objectAtIndex:indexPath.row]);
    NSLog(@"%d", [self.dataArray objectAtIndex:indexPath.row].type);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.userDB deleteObject:[self.dataArray objectAtIndex:indexPath.row]];
    [self.dataArray removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
}

@end
