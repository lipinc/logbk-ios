# SLASH-7 iOS library

[SLASH-7](http://www.slash-7.com/)にログを送信するためのライブラリです。

## セットアップ

まずレポジトリからライブラリのコードを取得します。

````
git clone http://github.com/pLucky-Inc/slash7-ios.git
````

Xcodeで組み込みたいプロジェクトを開いた状態にし、`Slash7`ディレクトリをFinderからドラッグ・アンド・ドロップします。
「Copy items into destination group's folder (if needed)」にチェックを入れ、Finishを押下します。

![Copy][copy]

TARGETS > Build Phases > Link Binary に以下のフレームワークのうち足りないものを追加してください。

* Foundation.framework
* UIKit.framework
* SystemConfiguration.framework
* CoreTelephony.framework

![Frameworks][frameworks]

## 初期化

Application delegate の `application:didFinishLaunchingWithOptions` または `applicationDidFinishLaunching:` でライブラリの初期化を行います。

````
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    [Slash7 sharedInstanceWithCode:TRACKING_CODE];
    return YES;
}
````

`TRACKING_CODE`は[SLASH-7](http://www.slash-7.com/)にログイン後、プロジェクト情報から取得します。

## イベント送信

イベントを送信するには以下のようにします。

````
Slash7 *slash7 = [Slash7 sharedInstance];
[slash7 track:@"login"];
````

イベントパラメータを指定するには `track:withParams:` を使います。

````
Slash7 *slash7 = [Slash7 sharedInstance];
NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:@"Premium", @"Plan", nil]
[slash7 track:@"login" withParams:params];
````

課金イベントを送信するには `track:withTransaction:` を使います。

````
Slash7TransactionItem *item = [[[Slash7TransactionItem alloc] initWithId:@"item1" withPrice:100] autorelease];
Slash7Transaction *transaction = [[[Slash7Transaction alloc] initWithId:@"transaction012345" withItem:item1] autorelease];
Slash7 *slash7 = [Slash7 sharedInstance];
[slash7 track:@"login" withTransaction:transaction];
````

## ユーザIDの指定

デフォルトではランダムなユーザIDが生成・保存され、使用されます。
ユーザIDを指定する場合には `identify:` を使います。

````
Slash7 *slash7 = [Slash7 sharedInstance];
[slash7 identify:@"user012345"];
````

## ユーザ属性

ユーザ属性を指定する場合には `setUserAttribute:to:` または `setUserAttributes:` を使います。

````
Slash7 *slash7 = [Slash7 sharedInstance];
[slash7 setUserAttribute:@"gender" to:@"male"];
````

指定されたユーザ属性は、次のイベント送信時にサーバへ送付されます。 
 
## ARC
 
本ライブラリは ARC を使用していません。
ARCを使用しているプロジェクトで使う場合には、TARGETS > Build Phases > Compile Sources から Slash7 が提供するソースファイルをダブルクリックし、 `-fno-objc-arc` を入力してください。

![ARC][arc]

[copy]: https://raw.github.com/pLucky-Inc/slash7-ios/master/Docs/Images/copy.png "Copy"
[frameworks]: https://raw.github.com/pLucky-Inc/slash7-ios/master/Docs/Images/frameworks.png "Frameworks"
[arc]: https://raw.github.com/pLucky-Inc/slash7-ios/master/Docs/Images/arc.png "ARC"

