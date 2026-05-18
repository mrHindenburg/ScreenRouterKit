# ScreenRouterKit — Інтеграція

Бібліотека показує splash, робить запит до сервера і відкриває WebView або нативний екран.
Виберіть сценарій що відповідає вашому проекту і вставте код у потрібні файли.

---

## Огляд сценаріїв

| Сценарій | Метод | Сервер | Push | ATT | AppsFlyer |
|---|---|:---:|:---:|:---:|:---:|
| 1 — Тільки нативний | `present()` | — | — | — | — |
| 2 — Сервер без трекінгу | `start()` | ✅ | — | — | — |
| 3 — Сервер + push + ATT | `startWithPush()` | ✅ | ✅ | ✅ | — |
| 4 — Повна інтеграція | `startWithTracking()` | ✅ | ✅ | ✅ | ✅ |

---

## Сценарій 1 — `present()`: тільки сплеш + нативний екран

**Коли використовувати:** немає бекенду, потрібен лише красивий сплеш перед нативним екраном.
AppDelegate, Firebase і push не потрібні. ATT пропускається автоматично.

### `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                transition: .slideUp,
                splash:     { onComplete in SplashView(onComplete: onComplete) },
                mainView:   { ContentView() },
                debugMode:  .disabled  // при проблемах змініть на .verbose для детальних логів
            )
        }
    }
}
```

---

## Сценарій 2 — `start()`: сервер без push і без ATT

**Коли використовувати:** є бекенд що визначає маршрут (нативний або WebView), але push-сповіщення і рекламний трекінг не потрібні. AppDelegate і Firebase не потрібні.

### Крок 1 — `AppConstants.swift`

```swift
enum AppConstants {
    static let appId = "YOUR_APP_ID"  // App Store Connect numeric ID
    static let host  = "YOUR_DOMAIN"  // без https://, напр. "api.myapp.com"
}
```

### Крок 2 — `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:      AppConstants.host,
                appId:     AppConstants.appId,
                splash:    { onComplete in SplashView(onComplete: onComplete) },
                mainView:  { ContentView() },
                debugMode: .minimal  // при проблемах змініть на .verbose для детальних логів
            )
        }
    }
}
```

---

## Сценарій 3 — `startWithPush()`: сервер + push + ATT (Firebase FCM, без AppsFlyer)

**Коли використовувати:** є бекенд, потрібні push-сповіщення через Firebase FCM і діалог ATT.
AppsFlyer не потрібен. ATT і push бібліотека керує автоматично.

### Крок 1 — `AppConstants.swift`

```swift
enum AppConstants {
    static let appId = "YOUR_APP_ID"  // App Store Connect numeric ID
    static let host  = "YOUR_DOMAIN"  // без https://, напр. "api.myapp.com"
}
```

### Крок 2 — `Info.plist`

Відкрийте `Info.plist` як **Source Code** і вставте перед закриваючим `</dict>`:

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

> Без цього Firebase перехоплює APNs-делегат і push-токени не доходять до бібліотеки.

### Крок 3 — `AppDelegate.swift`

```swift
import UIKit
import Firebase
import FirebaseMessaging

final class AppDelegate: SRKAppDelegate, MessagingDelegate {

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken       // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken) // потім бібліотека
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "APNs error — \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        ScreenRouterKit.shared.handleFCMToken(token)
    }
}
```

### Крок 4 — `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithPush(
                host:      AppConstants.host,
                appId:     AppConstants.appId,
                splash:    { onComplete in SplashView(onComplete: onComplete) },
                mainView:  { ContentView() },
                debugMode: .minimal,  // при проблемах змініть на .verbose для детальних логів
                attDelay:  1.5  // ATT діалог через 1с (старт) + 1.5с = ~2.5с
            )
        }
    }
}
```

---

## Сценарій 4 — `startWithTracking()`: повна інтеграція (Firebase + ATT + AppsFlyer)

**Коли використовувати:** потрібен весь стек — сервер, Firebase FCM, ATT, IDFA і AppsFlyer.

`AppConstants.appId` використовується в двох місцях автоматично:
- `AppsFlyerLib.shared().appleAppID = AppConstants.appId` — в `AppDelegate`
- `appId: AppConstants.appId` — в `startWithTracking`

Достатньо змінити один рядок щоб оновити обидва.

**Що SRK робить автоматично (вам НЕ потрібно робити вручну):**
- `.onOpenURL` / `.onContinueUserActivity` — SRK сам передає URL в AppsFlyer
- `extraInstallFields` — AppsFlyer conversion data збирається і вставляється в запит автоматично
- ATT — управляється через AppDelegate, `appsFlyerEnabled = true` достатньо

### Крок 1 — `AppConstants.swift`

```swift
enum AppConstants {
    static let appId    = "YOUR_APP_ID"             // App Store Connect numeric ID
    static let afDevKey = "YOUR_APPSFLYER_DEV_KEY"  // AppsFlyer Dev Key
    static let host     = "YOUR_DOMAIN"             // без https://, напр. "api.myapp.com"
}
```

### Крок 2 — `Info.plist`

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

### Крок 3 — `AppDelegate.swift`

```swift
import UIKit
import Firebase
import FirebaseMessaging
import AppsFlyerLib

final class AppDelegate: SRKAppDelegate, MessagingDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        appsFlyerEnabled = true                      // ← обов'язково ДО super
        ScreenRouterKit.shared._appDelegate = self   // ← обов'язково ДО super
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = AppConstants.afDevKey
        AppsFlyerLib.shared().appleAppID      = AppConstants.appId   // той самий що в startWithTracking
        AppsFlyerLib.shared().delegate        = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        AppsFlyerLib.shared().start()
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken       // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken) // потім бібліотека
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "APNs error — \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        ScreenRouterKit.shared.handleFCMToken(token)
    }

    override func attDidComplete(authorized: Bool) {
        // authorized == true — користувач дозволив відстеження, IDFA доступний
    }
}

extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        onAppsFlyerConversionData(conversionInfo) // SRK зберігає і вставляє в /install сам
    }
    func onConversionDataFail(_ error: Error) {
        onAppsFlyerConversionFail()
    }
}
```

### Крок 4 — `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:      AppConstants.host,
                appId:     AppConstants.appId,   // той самий що AppsFlyerLib.shared().appleAppID
                splash:    { onComplete in SplashView(onComplete: onComplete) },
                mainView:  { ContentView() },
                debugMode: .minimal,  // при проблемах змініть на .verbose для детальних логів
                attDelay:  2.0  // ATT діалог через 1с (старт) + 2с = ~3с
            )
        }
    }
}
```

---

## SplashView — приклади

Бібліотека передає у ваш `SplashView` параметр `onComplete`.
**Обов'язково викличте `onComplete()` після завершення анімації** — без цього splash не зникне.

### Фіксована тривалість

```swift
struct SplashView: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppLogo").resizable().scaledToFit().frame(width: 160)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onComplete()
            }
        }
    }
}
```

### Анімація + completion (iOS 17+)

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var scale:   CGFloat = 0.5
    @State private var opacity: Double  = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppLogo")
                .resizable().scaledToFit().frame(width: 140)
                .scaleEffect(scale).opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0; opacity = 1.0
            } completion: {
                onComplete() // викликається точно після завершення анімації
            }
        }
    }
}
```

### Анімація + asyncAfter (iOS 16 і нижче, або кілька фаз)

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var scale:   CGFloat = 0.5
    @State private var opacity: Double  = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppLogo")
                .resizable().scaledToFit().frame(width: 140)
                .scaleEffect(scale).opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                scale = 1.0; opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onComplete()
            }
        }
    }
}
```

### Lottie

```swift
import Lottie

struct SplashView: View {
    let onComplete: () -> Void

    var body: some View {
        LottieView(animation: .named("splash"))
            .playing(loopMode: .playOnce)
            .animationDidFinish { _ in onComplete() }
            .ignoresSafeArea()
            .background(Color.black)
    }
}
```

---

## Довідка по параметрах

### Обов'язкові параметри

| Параметр | Сценарій |
|---|---|
| `host` | 2, 3, 4 |
| `appId` | 2, 3, 4 |
| `splash` | всі |
| `mainView` | всі |

### `AppConstants`

| Поле | Сц. 1 | Сц. 2 | Сц. 3 | Сц. 4 |
|---|:---:|:---:|:---:|:---:|
| `appId` | — | ✅ | ✅ | ✅ |
| `host` | — | ✅ | ✅ | ✅ |
| `afDevKey` | — | — | — | ✅ |

`AppConstants.appId` — числовий ID застосунку з App Store Connect.
В Сценарії 4 він використовується одночасно в `appleAppID` (AppsFlyer) і в `appId:` (SRK).

Якщо API нестандартне — замість `host:` використовуйте `registerURL:` і `syncURL:` напряму у `SRKConfiguration`.

---

### `attDelay`

Затримка в секундах перед показом системного ATT-діалогу. Передайте `0` щоб показати одразу.
Доступно в `present()`, `startWithPush()` і `startWithTracking()`.

```swift
attDelay: 2.0
// startWithPush / startWithTracking: ATT через 1с (внутрішній старт) + 2с = ~3с
// present: ATT через attDelay секунд
```

---

### `debugMode`

| Значення | Що виводить у консоль |
|---|---|
| `.disabled` | Нічого |
| `.minimal` | `FINAL_URL`, `FCM_FIRST`, `FCM_REFRESH`, `DEVICE_ID`, `IDFA`, `AF_INSTALL_TYPE`, `APPS_FIELDS`, `SYNC_RESULT`, `ERROR` |
| `.verbose` | Кожен крок роботи бібліотеки |

При проблемах або питаннях → `.verbose`. Перед релізом → `.disabled`.

---

### `transition`

Анімація переходу від splash до основного контенту. Доступна в усіх сценаріях.

```swift
transition: .fade       // за замовчуванням
transition: .slideUp
transition: .slideDown
transition: .scale
transition: .custom(type: .slide(.left), animation: .spring(duration: 0.4))
```

---

### `fallbackURL`

Резервна URL якщо сервер недоступний, але маршрут "web" вже збережений з попереднього запуску.
Доступна в сценаріях 2, 3, 4.

```swift
fallbackURL: "https://myapp.com"
```

---

### `nativeOnly`

```swift
nativeOnly: true  // завжди показувати нативний екран, навіть якщо сервер повернув URL
                  // використовуйте для App Review або тимчасового вимкнення WebView
```

---

## Типові помилки

| Симптом | Причина | Рішення |
|---|---|---|
| Splash ніколи не зникає | `onComplete()` не викликається | Переконайтеся що `onComplete()` викликається після анімації або через `asyncAfter` |
| Push не реєструються | Firebase swizzling не вимкнено | Додайте `FirebaseAppDelegateProxyEnabled = NO` у `Info.plist` |
| `startWithTracking` — `appDelegate not set yet` | `_appDelegate = self` не встановлено до SwiftUI body | Встановіть у `didFinishLaunchingWithOptions` ДО `super` |
| ATT або AppsFlyer не ініціалізуються | `appsFlyerEnabled = true` відсутній | Додайте `appsFlyerEnabled = true` у `didFinishLaunchingWithOptions` ДО `super` |
| Білий екран замість нативного | `mainView` повертає пусте View | Переконайтесь що `ContentView()` не порожній |
| Орієнтація не змінюється у WebView | `AppDelegate` не успадковує `SRKAppDelegate` | Змініть `class AppDelegate: NSObject` на `class AppDelegate: SRKAppDelegate` |
