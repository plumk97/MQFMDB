## MQFMDB
在[FMDB](https://github.com/ccgus/fmdb)上封装了一层以对象的方式操作数据库类似CoreData

由于使用了SQLCipher来加密数据库所以你需要安装FMDB/SQLCipher版本

`pod 'FMDB/SQLCipher'`

Demo提供了一个增删查找演示

### Conf 文件说明
* `identify`__数据库标识符 一个App里面每个数据库标识符必须是唯一的__
* `version`__数据库版本号__
* `path`__数据库存放位置__

内置了两个目录`<App>`、`<MQFMDB>`<br>
`<App>`在App根目录下一般用于读取内置数据库<br>
`<MQFMDB>`在Documents目录下的__MQFMDB__文件夹如果没有则会自动创建

* `key`__数据库密码__
* `upgrade`__数据库升级的相关__

### upgrade字段

假设TDSession类在1.0.0版本是这样的

```
@interface TDSession : MQFMDBObject

@property (nonatomic, copy) NSString * name;
@end
```
现在升级到1.0.1版本在这个类加了一个count属性

```
@interface TDSession : MQFMDBObject

@property (nonatomic, copy) NSString * name;

/** version-1.0.1 */
@property (nonatomic, assign) NSInteger count;
@end
```

那么需要在工程里面添加一个sql升级脚本，并在配置文件里面填入路径，如下所示

```
{
  "identify": "MQFMDB_Demo",
  "version": "1.0.1",
  "path": "<MQFMDB>/MQFMDB_Demo.sqlite",
  "key": "123456789",
  "upgrade": {
      "1.0.0": {
          "script": "<App>/db_upgrade_101.sql"
      }
  }
}
```

再次运行就完成了从1.0.0到1.0.1的升级,Demo中已经配置好了需要测试请按下面操作

1. 取消TDSession.h文件中`@property (nonatomic, assign) NSInteger count;`注释
2. 取消TDSession.m文件中`@dynamic count;`注释
3. 注释ViewController中使用**MQFMDB_Demo**一行并且取消使用**MQFMDB_Demo-1.0.1**的注释

然后运行就可以了，**运行之前需要保证当前数据库版本处于1.0.0版本**

### 使用方法
> 具体使用方法请查看Demo 以下只是部分代码提取


__创建数据库表__

每个表都对应一个`MQFMDBObject`的子类，`MQFMDBObject`的`_Id`属性为主键不能手动去修改

`MQFMDBObject`的子类的属性如果使用`@dynamic`声明则视为表字段,__并且属性名称不能以大写开头__.

```
@interface TDSession : MQFMDBObject

@property (nonatomic, copy) NSString * name;
@end
```
```
@implementation TDSession
@dynamic name;


@end
```

__创建数据库__

```
/** 生成数据库并且打开相关配置在conf文件 */
self.userDB = [[MQFMDB alloc] initWithConfigContent:configContent];
[self.userDB openDatabaseWithOpertions:^(MQFMDB *db) {
/** 在这里创建表如果不存在才创建 */
[db insertNewTable:[TDMessage class]];
[db insertNewTable:[TDSession class]];
}];
```
__查询__

```
// 下面语句等于 SELECT * FROM TDMessage WHERE session == 1
// [self.dataArray setArray:[self.userDB queryTable:[TDMessage class] condition:[NSString stringWithFormat:@"session == 1"]]];
// 下面语句等于 SELECT * FROM TDMessage
[self.dataArray setArray:[self.userDB queryTable:[TDMessage class] condition:nil]];
```
__插入__

```
// 使用这种方法创建的对象才会保存进数据库
TDSession * session = [self.userDB insertNewObjectForTable:[TDSession class]];
session.name = @"session";

TDMessage * message = [self.userDB insertNewObjectForTable:[TDMessage class]];
message.session = session;
message.type = arc4random() % 10;
message.state = arc4random() % 3;
message.time = [NSDate date];
message.content = @"插入测试";

message.latitude = arc4random() % 1000;
message.longitude = arc4random() % 1000;

message.params = @{@"123":@(123), @"345" : @(345), @"params": @{@"123":@(123), @"345" : @(345)}};
message.array = @[@"1", @"2", @"3", @"4"];
// 执行这个方法只会才会保存操作
[self.userDB saveOpertion];
```
__修改__

```
TDMessage * message = [self.dataArray objectAtIndex:selectedIndexPath.row];
message.type = arc4random() % 10;
message.state = arc4random() % 3;
message.time = [NSDate date];
message.content = @"插入测试";

message.longitude = arc4random() % 1000;
message.latitude = arc4random() % 1000;

message.params = @{@"123":@(123), @"345" : @(345), @"params": @{@"123":@(123), @"345" : @(345)}};
message.array = @[@"1", @"2", @"3", @"4"];

[self.userDB saveOpertion];
```

__删除__

```
TDMessage * message = [self.dataArray objectAtIndex:selectedIndexPath.row];
[self.userDB deleteObject:message];
```
