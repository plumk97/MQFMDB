## MQFMDB
在[FMDB](https://github.com/ccgus/fmdb)上封装了一层实现ORM操作

由于使用了SQLCipher来加密数据库所以你需要安装FMDB/SQLCipher版本推荐使用2.7.5版本

`pod 'FMDB/SQLCipher', '=2.7.5'`

目前支持的数据类型

* NSString
* NSDate
* NSData
* NSDictionary
* NSArray
* C基本数据类型


### 使用说明

1. 创建[配置文件](#config_intro)

	```
	{
  		"identify": "MQFMDB_Demo",
	  	"version": "1.0.0",
  		"path": "<MQFMDB>/MQFMDB_Demo.sqlite",
	  	"key": "123456789",
  		"upgrade": {}
	}
	```

2. 根据表结构建立类并继承__MQFMDBObject__, 类的属性中对应数据库的必须使用__@dynamic__关键字声明该属性, 并且属性名__不能大写开头__

	```
	@interface TDSession : MQFMDBObject
	
	@property (nonatomic, copy) NSString * name;
	@end
	
	@implementation TDSession
	
	@dynamic name;
	@end
	```

3. 	读取配置文件并使用__MQFMDB__打开数据库, 并在opertions block中建立表

	```
	self.userDB = [[MQFMDB alloc] initWithConfigContent:configContent];
   [self.userDB openDataBaseWithForceOpenIfUpgradeFail:YES opertions:^(MQFMDB *db) {
        /** 在这里创建表和其他操作 */
        [db insertNewTable:[TDSession class]];
    }];
	```
	
4. 创建一条数据

	```
	TDSession * session = [self.userDB insertNewObjectForTable:[TDSession class]];
    session.name = @"session";
	```
	
5. 保存数据

	```
	[self.userDB saveOpertion];
	```

完成之后在`[MQFMDB MQFMDBFolder]`中已经创建一个数据库和一张名叫__TDSession__表并且表里有一条name等于session的数据。

#### 修改数据

1. 读取配置文件打开数据库

	```
	self.userDB = [[MQFMDB alloc] initWithConfigContent:configContent];
   [self.userDB openDataBaseWithForceOpenIfUpgradeFail:YES opertions:^(MQFMDB *db) {
        /** 在这里创建表和其他操作 */
        [db insertNewTable:[TDSession class]];
    }];
	```

2. 查询数据, 并获取查询到的第一条

	```
	TDSession * session = [[self.userDB queryTable:[TDSession class] condition:@"name == 'session'"] firstObject];
	```
	
3. 修改数据

	```
	session.name = "mmmm";
	```

4. 保存修改
	
	```
	[self.userDB saveOpertion];
	```

完成之后__TDSession__表中`name == 'session'`的第一条数据的name变为了mmmm

<a id="config_intro"></a>

### 配置文件字段说明 

* `identify`__数据库标识符 一个App里面每个数据库标识符必须是唯一的__
* `version`__数据库版本号__
* `key`__数据库密码__
* `upgrade`__数据库升级的相关语句__
* `path`__数据库存放位置__

	>
	内置了两个目录`<App>`、`<MQFMDB>`<br>
	`<App>`在App根目录下一般用于读取内置数据库<br>
	`<MQFMDB>`在Documents目录下的__MQFMDB__文件夹如果没有则会自动创建


### 数据库升级

1. 修改配置文件, 修改当前版本号, 并在__upgrade__建立一个在哪个版本升级的字段, 并在该字段里的__commands__里写入升级语句

	现在是从1.0.0升级到1.0.1，并在__TDSession__加入__count__字段
	

	```
	{
	  "identify": "MQFMDB_Demo",
	  "version": "1.0.1",
	  "path": "<MQFMDB>/MQFMDB_Demo.sqlite",
	  "key": "123456789",
	  "upgrade": {
	  	"1.0.0": {
	  		"commands": [
	  			"ALTER TABLE `TDSession` ADD COLUMN count INTEGER"
	  		]
	  	}
	  }
	}
	```

2. 修改__TDSession__类, 增加__count__属性，并且使用__@dynamic__声明该属性

	```
	@interface TDSession : MQFMDBObject
	
	@property (nonatomic, copy) NSString * name;
	/** version-1.0.1 */
	@property (nonatomic, assign) NSInteger count;
	@end
	
	@implementation TDSession
	
	@dynamic name;
	@dynamic count;
	@end
	```

3. 重新打开数据库就完成了升级**运行之前需要保证当前数据库版本处于1.0.0版本**

	>
	对于SQLite不支持删除字段，所以推荐的做法是忽略这个字段，比如在类中删除该字段对应的属性



Demo中有增删查改的演示