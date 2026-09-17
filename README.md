# iphone_duo_layout

![iPhone Duo layout package overview](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/docs/media/hero.png)

為 **iPhone Duo 佈局適配（layout）**建立的 Flutter package，橋接原生佈局、保留區域、鉸鏈資訊及系統工具列。

將 iOS 原生的 **Reserved Regions（保留區域）** 與 **Hinge（鉸鏈）** 資訊提供給 Flutter。
目前實作①區域查詢與觀察、③原生工具列，以及④中的鉸鏈狀態／角度橋接。
②新增實驗性 split／span 原型：Swift 探測 Arrangement 布局結果，Flutter 呈現內容。
此布局橋接尚未完成 SDK 編譯／裝置驗證；多視窗及外螢幕 UI 留待後續模組。

## 功能示意

![Illustrated split, span, reserved regions and native toolbar preview](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/docs/media/layout-preview.gif)

以上為使用範例資料繪製的概念介面與動畫，**不是模擬器或真機錄影**；
原生新 SDK 的編譯與裝置行為仍待驗證，動畫不代表逐幀原生同步。

[查看 split／span 對照圖](https://raw.githubusercontent.com/samchancanada1/iphone_duo_layout/main/docs/media/layout-modes.png) · [素材與重新產生方式](docs/media/README.md)

## 目前狀態

**原生 API 已直接啟用；Dart 分析與測試已通過，原生新 SDK 編譯及裝置驗證仍待完成。**

- `read()` 直接呼叫 `UIView.reservedRegions(kind:)`。
- `NativeReservedRegions.watch()` 在支援的 iOS 版本訂閱並回報區域變更。
- `NativeHinge.watch()` 透過 SwiftUI `onHingeChange` 回報鉸鏈狀態與角度。
- `NativeToolbarHost` 接收 Dart 設定，建立原生導航工具列並回傳按鈕事件。
- 已移除自訂 SDK 編譯開關，不需要額外設定 Swift flag。
- 使用包含相應 API 宣告的 SDK 編譯；執行時保留 iOS 27.1 版本檢查。
- 只傳遞原生 API 回傳的資料，不以螢幕尺寸推測摺痕。
- `publish_to: none`；目前是本地開發 package。

## 安裝

在使用端的 `pubspec.yaml` 加入（調整為 package 的實際路徑）：

```yaml
dependencies:
  iphone_duo_layout:
    path: ../iphone_duo_layout
```

## 使用

```dart
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

final regionsApi = NativeReservedRegions();
final snapshot = await regionsApi.read();

if (snapshot.isAvailable) {
  // 空集合表示「查詢成功，目前沒有啟用中的保留區域」。
  for (final region in snapshot.regions!) {
    print('${region.kind}: ${region.bounds}');
  }
} else {
  // 不支援不代表沒有摺疊或鏡頭區域。
  print(snapshot.availability);
}

final subscription = regionsApi.watch().listen(
  (snapshot) {
    // 將原生區域資訊交給既有 Flutter 頁面使用。
  },
  onError: (Object error) {
    // 通道或資料格式錯誤不會被轉成空區域。
  },
);

// 頁面離開或不再需要資料時：
await subscription.cancel();
```

`watch()` 的所有訂閱者共用一個原生訂閱。第一個訂閱者取得原生初始結果；
後加入的訂閱者先收到最近一次成功接收的快照，再接收後續變更，不必另行
呼叫 `read()`。若尚未收到初始結果，所有訂閱者共同等待該結果。
重播的是最近收到的取樣資料，不是每次訂閱都重新同步查詢。

通道啟動失敗（包括 plugin 未註冊）會傳給 `onError`，並結束該次觀察；
重新訂閱即可重試。個別原生事件或資料格式錯誤會傳給 `onError`，串流仍可
繼續接收後續事件。`read()` 找不到 plugin 時仍回傳 `pluginUnavailable`。

最後一個訂閱取消時會清除快照快取並釋放原生訂閱；下次訂閱取得新的原生
初始資料。原生啟動與取消按順序執行，避免快速切換頁面時舊取消動作干擾
新訂閱。需要知道原生取消是否成功時，請 `await subscription.cancel()`。

## Arrangement split／span 原型（②，實驗性）

```dart
// 分區：兩個不同 Flutter widgets；位置由原生 Arrangement 的測量結果決定。
NativeArrangement.split(
  axis: NativeArrangementAxis.horizontal,
  primary: VideoWidget(),
  secondary: PlaylistWidget(),
);

// 跨區：同一個 widget 佔滿整個容器，不查詢原生 Arrangement。
NativeArrangement.span(child: MapWidget());
```

兩種模式都只有一個 Flutter engine。這裡的左右區域屬於同一 App 的視窗，
不是內外顯示器或其他 App 的視窗。span 填滿的是 widget 可用空間，不會隱藏原生工具列。

需要切換模式並保留兩區 State 時，使用同一個元件並保持兩個 child 的類型及 key：

```dart
Expanded(
  child: NativeArrangement(
    mode: splitEnabled ? NativeArrangementMode.split : NativeArrangementMode.span,
    primary: VideoWidget(key: const ValueKey('video')),
    secondary: PlaylistWidget(key: const ValueKey('playlist')),
    onSnapshotChanged: (snapshot) => print(snapshot.availability),
    onError: (error, stack) => print(error),
  ),
);
```

span 使用 primary；保留的 secondary 會 Offstage，停用觸控、焦點、semantics 和
TickerMode。此方式保留一般 Widget State；不會自動暫停你的 Timer、網路或媒體播放。
若改變 child 的類型／key，或不再傳入 secondary，仍遵循 Flutter 一般卸載規則。
子內容應以 LayoutBuilder 的 constraints 適應區域大小，MediaQuery 仍描述 Flutter view。

**split 資料流程**

1. Flutter 在 layout 後取得容器位置、大小，以及 Flutter view 的邏輯尺寸。
2. Swift 在同一個 Flutter view 內加入透明、不接收輸入的 UIArrangementViewController，
   其 frame 與該容器一致；primary／secondary 是空白原生 view controllers。
3. 使用 `.split` 或 `.split.axes(...)` 排列，讀取子 view 實際 bounds 的座標轉換結果、
   placement state 的 zIndex，以及階層中可觀察到的可見狀態。
4. Dart 收到符合本次 viewport 的結果，再用 Positioned 放置真正的 widgets。

`axis` 支援 automatic、horizontal、vertical；系統可能只保留一區，
不是永遠保證兩區同時可見。這版不提供 overlay style。
前景最多每 100 ms 查詢一次；同時只有一個未完成查詢。此為布局快照原型，
**不宣稱逐幀動畫同步，也不是 Apple 官方提供的 Flutter 布局 API。**

`ArrangementSnapshot` 包含：availability、viewport（相對 Flutter view）、viewSize，
以及 primary／secondary 的 bounds（相對 viewport）、visible、zIndex。
未取得資料時，pane 欄位為 null。span 不產生假的原生 snapshot。
`onSnapshotChanged` 只回報 split 的快照變化。

**範圍與錯誤處理**

- 需要有限且非零的寬高，請用 Expanded／SizedBox；第一版只支援平移、無旋轉或縮放，
  且 viewport 完整位於 Flutter view 內。不要把整個 Arrangement 放在捲動容器內；
  每一區的內容可以自行捲動。
- 預設缺少原生資料時顯示狀態，不自行產生 50/50 分區。可以透過
  `unavailableBuilder(context, snapshot, error)` 提供自己的替代 UI。
- availability：available、waiting、osUnavailable、unsupportedPlatform、viewUnavailable、
  inactive、geometryMismatch、unsupportedGeometry。新 API 要求 iOS 27.1。
- 不支援的平台／系統停止輪詢。通道或格式錯誤透過 onError／FlutterError 回報並停止輪詢；
  可透過模式切換、axis 更新或重新掛載重試。暫時尚未附著／幾何不符時前景持續重試。
- 切換 span、退背景、祖先 TickerMode 停用或卸載會釋放原生探測容器；
  恢復 split／前景／TickerMode 後重新建立。只設定 Offstage 不會停用取樣，
  自訂隱藏容器請同時使用 TickerMode(enabled: false)。
  UI client 初始化會清除 Dart hot restart 留下的舊探測容器。
- 不替換 window root，可以與③的原生工具列容器並存；整合行為仍待真機驗證。

**尚待驗證的核心假設**：空白原生 child 是否與真實內容獲得一致的 Arrangement 決策；
透明容器內部是否完全無可見裝飾；safe area、區域可見性、轉場和座標是否與 Flutter 同步。
目前以原生階層和 placement state 判斷 visible，不是已確認完整的 Arrangement 可見性語意。
原型沒有把 Flutter intrinsic size 回傳給原生 child，也沒有同步原生 presentation-layer 動畫。

範例入口：`example/lib/arrangement_demo.dart`；原診斷畫面也有
「Open split / span prototype」按鈕。包含計數器、文字輸入與捲動內容，方便後續檢查
切換時的狀態保存。原生 split 無法使用的平台上仍可試 span。

## 原生工具列（③）

在 App 層放置一個 `NativeToolbarHost`。Flutter 提供內容與動作，Swift 使用
`UINavigationController` 管理的原生工具列，外觀和適應布局交給 iOS。

```dart
MaterialApp(
  builder: (context, child) => NativeToolbarHost(
    configuration: NativeToolbarConfiguration(
      title: '文件',
      items: const [
        NativeToolbarItem(
          id: 'share',
          title: '分享',
          systemImage: 'square.and.arrow.up',
          priority: NativeToolbarPriority.high,
        ),
        NativeToolbarItem(
          id: 'refresh',
          title: '重新整理',
          systemImage: 'arrow.clockwise',
          placement: NativeToolbarPlacement.bottom,
          axis: NativeToolbarAxis.verticalPreferred,
        ),
      ],
      overflowItems: const [
        NativeToolbarItem(id: 'settings', title: '設定', systemImage: 'gearshape'),
      ],
    ),
    onAction: (id) {
      // 交給自己的 Flutter 業務邏輯，例如 share / refresh / settings。
    },
    onStatusChanged: (status) => print(status.availability),
    onError: (error, stack) => print(error),
    child: child!,
  ),
  home: const MyPage(),
);
```

`NativeToolbarItem` 提供：

| 參數 | 說明 |
| --- | --- |
| `id` / `title` | 必填；id 在一般項目和更多選單之間也不能重複 |
| `systemImage` | 選填 SF Symbols 名稱；系統找不到圖示時保留文字 |
| `enabled` | 是否可操作，預設 true |
| `visible` | 是否加入工具列／選單，預設 true |
| `placement` | leading、trailing（預設）、bottom |
| `priority` | automatic、low、high；影響收進更多選單的先後 |
| `axis` | automatic、horizontalOnly、verticalPreferred |

`overflowItems` 是持續放在系統「⋯」的動作；它們的 placement／priority／axis
不參與工具列布局。`high` 表示盡量較晚收起，並非永遠保持顯示。
直向工具列的實際出現、位置和收納時機仍由系統按空間決定。
目前沒有提供自訂外觀、Dart widget 作為原生按鈕、badge、群組或原生分頁列。

**容器與頁面整合**

- 第一版支援一般 Flutter App：registrar 的 Flutter controller 必須是自己 window
  的 root controller，且沒有其他父容器。既有 UIKit 導航／分頁／add-to-app
  階層會回報 `hostUnsupported`，不擅自重組既有階層。
- 每個 engine 同時只能有一個工具列 owner；衝突回報 `busy`。請在 App builder
  放置一次，隨 Flutter route 更新 configuration，不要每一頁都建立 host。
- 原生容器將 Flutter view 約束在原生內容 safe area，跟隨頂部／底部／側邊工具列
  調整尺寸。Dart 不需要猜測 bar 高度或額外加一次工具列 Padding。
  這版 Flutter 內容不延伸到原生 bar 後方；①的座標相對於縮放後的 Flutter view。
- Flutter Navigator 繼續管理 routes。需要返回按鈕時提供一個 action，並在 Dart
  呼叫自己 Navigator 的 maybePop。沒有自動同步 route 標題，也沒有建立 UIKit
  的返回堆疊／原生 interactive-pop 手勢。
- 更新設定不重建容器；舊版本、已移除、隱藏或停用的按鈕事件會被忽略。
- widget 移除時釋放原生容器，恢復原 Flutter root。若 App 已替換 window root，
  清理不會覆蓋新 root。若仍有原生 modal 或轉場，等待其結束後才還原，
  不會自行 dismiss 使用者的原生畫面。

`NativeToolbarController` 也可直接使用：訂閱 `actions`、呼叫 `setConfiguration()`，
用完後 `await dispose()`。dispose 會等待實際還原；native modal 未關閉時可能持續等待。
由 widget 管理時，dispose 的非同步錯誤會交給 onError 或 FlutterError。

| 狀態 | 意義 |
| --- | --- |
| `available` | 已建立／更新原生工具列，不代表目前必定顯示在側邊 |
| `viewUnavailable` | window 尚未附著、不是前景，或原生呈現／轉場中；Host 會在前景重試 |
| `hostUnsupported` | Flutter controller 已在其他原生容器中，或不是 window root |
| `busy` | 另一個工具列 owner 使用中 |
| `osUnavailable` | 本模組要求 iOS 27.1；未建立工具列 |
| `unsupportedPlatform` | 非 iOS；保留 Flutter child，不繪製替代工具列 |
| `detached` | 工具列 owner 已釋放 |

缺少 plugin 或通道失敗會拋出錯誤。請在 main UI isolate 使用。
hot reload 可更新設定；Dart hot restart 後，新 UI client 會先還原舊原生 owner，
再建立新工具列。若原生 modal 尚未關閉，此初始化會等待其結束。

## 鉸鏈狀態與角度（④）

```dart
final subscription = const NativeHinge().watch().listen(
  (snapshot) {
    if (snapshot.isAvailable) {
      print('${snapshot.status}: ${snapshot.angleDegrees}°');
      // angleRadians 也可用；交給動畫、音效或其他互動。
    } else {
      print(snapshot.availability);
    }
  },
  onError: (Object error) => print(error),
);
await subscription.cancel();
```

| availability | 意義 |
| --- | --- |
| `available` | 有原生狀態與角度；`status` 和 `angleDegrees` 都非 null |
| `waiting` | 原生觀察器已附著，但尚未收到鉸鏈回呼 |
| `noHinge` | 原生回呼明確表示沒有鉸鏈 |
| `inactive` | 所屬 scene 暫停作用，清除舊角度 |
| `viewUnavailable` | 尚無可附著的 Flutter controller/view/window |
| `osUnavailable` | 執行系統低於 iOS 27.1 |
| `unsupportedPlatform` | 目前不是 iOS |

`status` 包含 `closed`、`partiallyOpen`、`fullyOpen`、`unknown`。
角度直接使用原生的 degrees；不裁切為 0–180、不推測螢幕位置。
資料不可用時角度是 `null`，真實 0 度仍是有效數值。
`watch().first` 可能取得 `waiting`，不保證已取得硬體測量。
未有初始回呼時保持 `waiting`；不以逾時推斷沒有鉸鏈。

Swift 在目前 engine 的 Flutter controller 內掛載透明、不接收觸控和輔助使用焦點的
`UIHostingController`，由 `onHingeChange` 取得資料。角度由原生回呼推送；
每 250 ms 的前景檢查只用來偵測 host 附著／更換，不是輪詢角度。
背景或 view 分離會移除 observer；重新附著後等待新的回呼。
取消最後一位訂閱者時移除 controller、生命週期監聽與快取；舊 observer 的延遲回呼會被忽略。

兩個模組各自共用其原生訂閱，並各自管理快取／取消，不互相停止。
鉸鏈沒有 `read()`：目前來源是回呼，不把快取包裝成即時硬體查詢。
通道啟動失敗會送出 stream error 並關閉該次觀察，可重新訂閱。
原生端結束串流後若清理失敗，錯誤會先送到 onError，再發出 onDone；
主動取消訂閱的清理錯誤則由 cancel() 的 Future 回報。

**角度用於互動與效果；內容避讓仍使用①的區域資料。**

## 回傳資料與座標

- `division`：例如將內容分成兩側的摺疊區域。
- `occlusion`：例如鏡頭造成的遮擋區域。
- 只查詢目前 **active** 的區域；不提供 inactive 區域或姿態推測。鉸鏈角度由獨立 API 提供。
- `bounds` 使用目前 Flutter host view 的座標，以 UIKit points 表示。
  在標準 iOS Flutter embedder 中，它對應 Flutter logical pixels。
- `viewSize` 是被查詢 view 的尺寸，不是整台裝置的螢幕尺寸。
- Swift 透過該 engine 的 registrar 取得 view；不查詢全域 key window。
  本版限標準單一 Flutter view／engine；未宣稱支援每個 engine 多 view。

若 widget 位於 SafeArea、AppBar 或 Padding 之內，必須轉換座標：

```dart
final box = context.findRenderObject() as RenderBox;
final origin = box.localToGlobal(Offset.zero);
final localBounds = region.boundsRelativeTo(origin);
```

這個輔助方法只處理平移。旋轉／縮放的 widget 要另外套用完整 transform。
查詢結果是非同步快照；旋轉、resize 期間不要把上一個 viewSize 的快照當成
目前畫面的精確位置。範例將 overlay 放在整個 Flutter view 的 Stack 中。

## 支援狀態

| 狀態 | 意義 |
| --- | --- |
| `available` | API 查詢成功，`regions` 一定是集合，可能為空 |
| `inactive` | view 所屬 scene 目前不是 foregroundActive，幾何資料為 null |
| `osUnavailable` | 執行系統低於 iOS 27.1 |
| `viewUnavailable` | engine 尚未附著可查詢的原生 view |
| `unsupportedPlatform` | 此 iOS plugin 不處理目前平台 |
| `pluginUnavailable` | `read()` 找不到原生通道實作 |

不支援時 `regions` 是 `null`，避免把「不知道」誤當成「沒有」。
`available` 表示 API 可查詢，並不表示裝置一定有鉸鏈。

## 觀察方式與限制

原生訂閱以前景最多 10 Hz 取樣，去除相同快照。
以目前 Flutter view 所屬 scene 的生命週期控制取樣，不借用其他視窗的 active 狀態。
scene 暫停時送出 `inactive` 快照，清除幾何資料並停止 timer；恢復時重新查詢。
尚未附著 view 時，前景持續檢查 attachment；沒有訂閱時移除 timer 與生命週期觀察。
同種類的原生區域按座標排序，避免只是陣列順序改變就重複發送事件。
這是第一版的 observation 策略，**不是 Apple 的原生區域變更通知 API**，
不保證逐幀同步，也不適合拿來驅動鉸鏈動畫。
執行系統版本不足時回報 `osUnavailable`，不啟動取樣。

## 編譯需求與後續驗證

Swift 原始碼直接引用新 API，CocoaPods 與 Swift Package Manager 都不需要
額外啟用條件。編譯時需使用包含 `UIView.reservedRegions(kind:)`、
`.division`、`.occlusion`、`frame`，以及 SwiftUI `onHingeChange`／鉸鏈狀態與角度宣告的 SDK。

`#available(iOS 27.1, *)` 保留舊系統的執行時回退行為；它不會讓舊 SDK
取得缺少的宣告。2026-09-17 已執行 Dart 靜態分析、41 個 package 測試及 1 個範例
widget 測試，全部通過；Swift 僅通過語法解析，新 SDK 的編譯與裝置驗證仍待完成。
詳見 [VALIDATION.md](VALIDATION.md)。

後續驗證包含：新 API 編譯、摺疊／展開、內外螢幕、分割視窗、鏡頭開關、
旋轉、前背景、SafeArea 座標轉換，以及訂閱取消與 view 附著／分離。
鉸鏈還需驗證初始回呼時機、狀態 case 宣告、角度單位、透明 SwiftUI observer 的
事件接收與觸控／輔助使用無干擾，以及取消後不再回報舊事件。

## 驗證

```sh
flutter pub get --offline
flutter analyze
flutter test
cd example
flutter pub get --offline
flutter test
flutter build ios --simulator --debug --no-codesign
# 有可用 iOS simulator / device 後：
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

Dart mock tests 驗證通道協定，不代表新 Apple API 已通過硬體測試。
具體已執行的檢查見 `VALIDATION.md`。

## 官方依據

- [Apple：Reserved Regions 與 Arrangement views](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Apple：原生工具列與 Duo 側邊排列](https://developer.apple.com/videos/play/tech-talks/111462/)
- [Apple：鉸鏈、場景與多螢幕](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Apple：Duo 工具與 SDK 狀態](https://developer.apple.com/iphone-duo/)
- [Flutter：displayFeatures 目前只在 Android 填入資料](https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html)
