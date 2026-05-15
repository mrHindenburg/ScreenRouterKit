# ScreenRouterKit — Інтеграція

Бібліотека показує splash, робить запит до сервера і відкриває WebView або нативний екран.
Виберіть свій сценарій і вставте код у потрібні файли.

---

## Сценарій A — Firebase + push, без AppsFlyer

---

### Крок 1 — `Info.plist`

Відкрийте `Info.plist` як **Source Code** і вставте перед закриваючим `</dict>`:

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

---

### Крок 2 — `AppDelegate.swift`

Замініть весь вміст вашого `AppDelegate.swift` на:

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

---

### Крок 3 — `MyApp.swift` (файл з `@main`)

Замініть вміст `WindowGroup { }` на:

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:        "ВАШ_ДОМЕН",          // ← наприклад: "api.myapp.com"
                appId:       "ВАШ_BUNDLE_ID",      // ← наприклад: "com.company.app"
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attHandling: .managedByLibrary,
                attDelay:    1.5
            )
        }
    }
}
```

---

## Сценарій B — Firebase + push + AppsFlyer

---

### Крок 1 — `Info.plist`

Відкрийте `Info.plist` як **Source Code** і вставте перед закриваючим `</dict>`:

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

> Потрібно для обох сценаріїв — без цього Firebase конфліктує з APNs і push не працюватимуть.

---

### Крок 2 — `AppDelegate.swift`

Замініть весь вміст вашого `AppDelegate.swift` на:

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
        appsFlyerEnabled = true                    // ← обов'язково ДО super
        ScreenRouterKit.shared._appDelegate = self // ← обов'язково ДО super
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = "ВАШ_APPSFLYER_DEV_KEY"  // ← замінити
        AppsFlyerLib.shared().appleAppID      = "ВАШ_APPLE_APP_ID"       // ← замінити
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
        // authorized == true — користувач дозволив відстеження (IDFA доступний)
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

---

### Крок 3 — `MyApp.swift` (файл з `@main`)

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:        "ВАШ_ДОМЕН",          // ← наприклад: "api.myapp.com"
                appId:       "ВАШ_BUNDLE_ID",      // ← наприклад: "com.company.app"
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attDelay:    2.0   // ATT діалог з'явиться через ~3с після старту
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

### `host` і `appId`

```swift
host:  "api.myapp.com"      // домен без https:// — бібліотека побудує URL сама
appId: "com.company.app"    // Bundle ID застосунку
```

Якщо API нестандартне — використовуйте `registerURL:` і `syncURL:` напряму замість `host:`.

---

### `attDelay`

Затримка в секундах перед показом системного ATT-діалогу. Передайте `0` щоб показати одразу.

```swift
attDelay: 2.0  // у start()            → ATT через 2с
               // у startWithTracking() → ATT через 1с (старт) + 2с = ~3с
```

---

### `attHandling` (тільки для `start`, не для `startWithTracking`)

| Значення | Коли використовувати |
|---|---|
| `.managedByLibrary` | Бібліотека сама показує ATT діалог — стандарт |
| `.skip` | Без ATT — якщо застосунок не використовує рекламу |
| `.managedByHost(signal:)` | Ви самі показуєте ATT і сигналізуєте через `signal.complete(authorized:)` |

---

### `debugMode`

| Значення | Що виводить у консоль |
|---|---|
| `.disabled` | Нічого |
| `.minimal` | `FINAL_URL`, `FCM_FIRST`, `FCM_REFRESH`, `DEVICE_ID`, `APPS_FIELDS`, `ERROR` |
| `.verbose` | Кожен крок роботи бібліотеки |

Під час розробки → `.verbose`. Перед релізом → `.disabled`.

---

### `pushEnabled`

```swift
pushEnabled: false  // не показувати системний діалог push і не реєструватись
```

---

### `fallbackURL`

Резервна URL якщо сервер недоступний при повторних запусках, але маршрут "web" вже збережений.

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

### `transition`

Анімація переходу від splash до основного контенту.

```swift
transition: .fade      // за замовчуванням
transition: .slideUp
transition: .slideDown
transition: .scale
transition: .custom(type: .slide(.left), animation: .spring(duration: 0.4))
```

---

## Типові помилки

| Симптом | Причина | Рішення |
|---|---|---|
| Splash ніколи не зникає | `onComplete()` не викликається | Переконайтеся що `onComplete()` викликається після анімації або через `asyncAfter` |
| Push не реєструються | Firebase swizzling не вимкнено | Додайте `FirebaseAppDelegateProxyEnabled = NO` у `Info.plist` |
| `startWithTracking` — `appDelegate not set yet` | `_appDelegate = self` не встановлено до SwiftUI body | Встановіть у `didFinishLaunchingWithOptions` ДО `super` |
| ATT або AppsFlyer не ініціалізуються | `appsFlyerEnabled = true` відсутній | Додайте `appsFlyerEnabled = true` у `didFinishLaunchingWithOptions` ДО `super` |
| Білий екран замість нативного | `mainView` повертає пусте View | Передайте `mainView: { AnyView(ContentView()) }` |
| Орієнтація не змінюється у WebView | `AppDelegate` не успадковує `SRKAppDelegate` | Змініть `class AppDelegate: NSObject` на `class AppDelegate: SRKAppDelegate` |
