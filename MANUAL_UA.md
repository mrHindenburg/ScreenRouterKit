# ScreenRouterKit — Інтеграція

Бібліотека показує splash, робить запит до сервера і відкриває WebView або нативний екран.
Виберіть сценарій що відповідає вашому проекту і вставте код у потрібні файли.

---

## Огляд сценаріїв

| Сценарій | Метод | Сервер | Push | ATT | AppsFlyer |
|---|---|:---:|:---:|:---:|:---:|
| 1 — Тільки нативний | `whiteClean()` | — | — | — | — |
| 1б — Нативний + дозволи | `whiteWithPermissions()` | — | ✅ | ✅ | — |
| 2 — Сервер без трекінгу | `blackClean()` | ✅ | — | — | — |
| 3 — Сервер + push + ATT | `blackWithPermissions()` | ✅ | ✅ | ✅ | — |
| 4 — Повна інтеграція | `blackFullIntegration()` | ✅ | ✅ | ✅ | ✅ |

---

## Підключення бібліотеки до проєкту

> **Увага:** ScreenRouterKit підключається як локальна папка вихідного коду — **не через Swift Package Manager**. Не додавайте її через `File → Add Package Dependencies` або `Package.swift`. Це не SPM-пакет.

### Крок 1 — Скопіюйте папку `Sources` у ваш проєкт

Перемістіть або скопіюйте папку `ScreenRouterKit/Sources/ScreenRouterKit` до кореня вашого Xcode-проєкту (поруч із `MyApp.xcodeproj`).

```
MyProject/
├── MyApp.xcodeproj
├── MyApp/
│   ├── ContentView.swift
│   └── ...
└── ScreenRouterKit/          ← скопіюйте сюди
    ├── ScreenRouterKit.swift
    ├── SRKFlowCoordinator.swift
    └── ...
```

### Крок 2 — Додайте файли до таргету в Xcode

1. Відкрийте Xcode → клацніть правою кнопкою на папку вашого проєкту у навігаторі
2. Оберіть **Add Files to "MyApp"...**
3. Виберіть папку `ScreenRouterKit` і поставте галочку **Copy items if needed** (якщо ще не скопійовано)
4. Переконайтеся що **Add to targets** вказує на ваш основний таргет (`MyApp`)
5. Натисніть **Add**

### Крок 3 — Перевірте Target Membership

Виберіть будь-який файл бібліотеки у навігаторі → у правій панелі **File Inspector** → **Target Membership** — має стояти галочка навпроти вашого таргету.

### Що не треба робити

- Не додавайте через `File → Add Package Dependencies` — бібліотека не є SPM-пакетом
- Не додавайте `.xcframework` або `.framework` — це вихідний код, не бінарний фреймворк
- Не додавайте `Package.swift` до проєкту — він не потрібен для інтеграції

---

## Сценарій 1 — `whiteClean()`: тільки сплеш + нативний екран

**Коли використовувати:** немає бекенду, потрібен лише красивий сплеш перед нативним екраном.
AppDelegate, Firebase і push не потрібні. ATT не запитується.

### `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.whiteClean(
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

## Сценарій 1б — `whiteWithPermissions()`: нативний + ATT + push (без сервера)

**Коли використовувати:** немає бекенду, але потрібні системні дозволи — ATT-діалог і push-нотифікації.


### `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.whiteWithPermissions(
                splash:      { onComplete in SplashView(onComplete: onComplete) },
                mainView:    { ContentView() },
                debugMode:   .disabled,
                attHandling: .managedByLibrary,  // за замовчуванням
                attDelay:    1.5,                // ATT через 0.1с (старт) + 0.6с (після splash) + 1.5с = ~2.2с
                pushEnabled: true                // за замовчуванням
            )
        }
    }
}
```

> Якщо потрібно вимкнути один із дозволів — явно передайте відповідний параметр:
> - Тільки ATT, без push → `pushEnabled: false`
> - Тільки push, без ATT → `attHandling: .skip`

---

## Сценарій 2 — `blackClean()`: сервер без push і без ATT

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
            ScreenRouterKit.shared.blackClean(
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

## Сценарій 3 — `blackWithPermissions()`: сервер + push + ATT (Firebase FCM, без AppsFlyer)

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
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        didReceiveFCMToken(token)
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
            ScreenRouterKit.shared.blackWithPermissions(
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

## Сценарій 4 — `blackFullIntegration()`: повна інтеграція (Firebase + ATT + AppsFlyer)

**Коли використовувати:** потрібен весь стек — сервер, Firebase FCM, ATT, IDFA і AppsFlyer.

`AppConstants.appId` використовується в двох місцях автоматично:
- `AppsFlyerLib.shared().appleAppID = AppConstants.appId` — в `AppDelegate`
- `appId: AppConstants.appId` — в `blackFullIntegration`

Достатньо змінити один рядок щоб оновити обидва.

**Що SRK робить автоматично (вам НЕ потрібно робити вручну):**
- `.onOpenURL` / `.onContinueUserActivity` — SRK сам передає URL в AppsFlyer
- `extraInstallFields` — AppsFlyer conversion data збирається і вставляється в запит автоматично
- ATT — управляється через AppDelegate, `appsFlyerEnabled = true` достатньо

### Крок 1 — Додайте пакет AppsFlyerLib

При додаванні через SPM вкажіть версію **6.18** — не обирайте "Up to Next Major", бо наступні версії можуть містити несумісні зміни.

### Крок 2 — `AppConstants.swift`

```swift
enum AppConstants {
    static let appId    = "YOUR_APP_ID"             // App Store Connect numeric ID
    static let afDevKey = "YOUR_APPSFLYER_DEV_KEY"  // AppsFlyer Dev Key
    static let host     = "YOUR_DOMAIN"             // без https://, напр. "api.myapp.com"
}
```

### Крок 3 — `Info.plist`

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

### Крок 4 — `AppDelegate.swift`

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
        appsFlyerEnabled = true  // ← обов'язково ДО super
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = AppConstants.afDevKey
        AppsFlyerLib.shared().appleAppID      = AppConstants.appId   // той самий що в blackFullIntegration
        AppsFlyerLib.shared().delegate        = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        AppsFlyerLib.shared().start()
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        didReceiveFCMToken(token)
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

### Крок 5 — `MyApp.swift`

```swift
import SwiftUI

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.blackFullIntegration(
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

| Поле | Сц. 1 | Сц. 1б | Сц. 2 | Сц. 3 | Сц. 4 |
|---|:---:|:---:|:---:|:---:|:---:|
| `appId` | — | — | ✅ | ✅ | ✅ |
| `host` | — | — | ✅ | ✅ | ✅ |
| `afDevKey` | — | — | — | — | ✅ |

`AppConstants.appId` — числовий ID застосунку з App Store Connect.
В Сценарії 4 він використовується одночасно в `appleAppID` (AppsFlyer) і в `appId:` (SRK).

Якщо API нестандартне — замість `host:` використовуйте `registerURL:` і `syncURL:` напряму у `SRKConfiguration`.

---

### `attHandling`

Визначає хто керує запитом ATT. Доступно **тільки** у `whiteWithPermissions()` як явний параметр.

У решті методів ATT-поведінка фіксована:
- `whiteClean()` — ATT не запитується
- `blackClean()` — ATT не запитується
- `blackWithPermissions()` — ATT керує бібліотека (`.managedByLibrary`)
- `blackFullIntegration()` — ATT керується через AppDelegate і ATT-сигнал (`.managedByHost`)

| Значення | Опис |
|---|---|
| `.skip` | ATT не запитується |
| `.managedByLibrary` | ATT запитується автоматично після `attDelay` (за замовчуванням для `whiteWithPermissions()`) |
| `.managedByHost(signal:)` | ATT керується хостом — передайте `SRKATTSignal` і викличте `.complete(authorized:)` вручну |

---

### `attDelay`

Затримка в секундах перед показом системного ATT-діалогу. Передайте `0` щоб показати одразу.
Доступно в `whiteWithPermissions()`, `blackWithPermissions()` і `blackFullIntegration()`.

| Метод | За замовчуванням | Обов'язковий |
|---|:---:|:---:|
| `whiteWithPermissions()` | — | ✅ |
| `blackWithPermissions()` | `2.0` | — |
| `blackFullIntegration()` | `2.0` | — |

Якщо вас влаштовує 2 секунди — для `blackWithPermissions` і `blackFullIntegration` параметр можна не передавати. Щоб змінити — вкажіть явно:

```swift
// blackWithPermissions / blackFullIntegration: ATT через ~1с (мережа + старт) + attDelay
attDelay: 2.0   // дефолт — ~3с до ATT
attDelay: 4.0   // більше часу — ~5с до ATT
attDelay: 0     // одразу після старту — не рекомендовано

// whiteWithPermissions: ATT через ~0.7с (старт + splash) + attDelay
attDelay: 1.5   // ~2.2с до ATT (обов'язково вказати)
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

### `requestReviewEnabled`

Керує показом системного діалогу оцінки App Store (StoreKit `requestReview`). Доступно в сценаріях 2, 3, 4. За замовчуванням вимкнено.

```swift
requestReviewEnabled: true
```

Якщо `true` — діалог з'являється через 4 секунди після відкриття WebView, але лише один раз за весь термін використання застосунку (контролюється через `@AppStorage("isAskedReview")`). iOS сам вирішує чи показати діалог — передача `true` не гарантує показ, а лише дозволяє бібліотеці зробити запит.

> **За замовчуванням:** `false` — діалог не показується. Щоб увімкнути — передайте явно `requestReviewEnabled: true`.

---

## Типові помилки

| Симптом | Причина | Рішення |
|---|---|---|
| Splash ніколи не зникає | `onComplete()` не викликається | Переконайтеся що `onComplete()` викликається після анімації або через `asyncAfter` |
| Push не реєструються | Firebase swizzling не вимкнено | Додайте `FirebaseAppDelegateProxyEnabled = NO` у `Info.plist` |
| ATT або AppsFlyer не ініціалізуються | `appsFlyerEnabled = true` відсутній | Додайте `appsFlyerEnabled = true` у `didFinishLaunchingWithOptions` ДО `super` |
| Білий екран замість нативного | `mainView` повертає пусте View | Переконайтесь що `ContentView()` не порожній |
| Орієнтація не змінюється у WebView | `AppDelegate` не успадковує `SRKAppDelegate` | Змініть `class AppDelegate: NSObject` на `class AppDelegate: SRKAppDelegate` |

---

## Діагностика за логами

Увімкніть `debugMode: .verbose` щоб бачити всі повідомлення. У консолі вони мають префікс `[SRK]` з іконкою рівня: `✅` info, `⚠️` warning, `❌` error, `🔑` ключові мілстоуни.

### Маршрутизація

| Повідомлення | Що означає |
|---|---|
| `✅ ViewModel: → web(URL)` | Сервер повернув URL — відкривається WebView |
| `✅ ViewModel: → main` | Відкривається нативний екран |
| `✅ Coordinator: found lock=web` | Маршрут взято з кешу попереднього запуску — сервер не запитується |
| `✅ Coordinator: no network → main (no lock)` | Мережа недоступна при першому запуску — показано нативний без збереження маршруту |
| `✅ Coordinator: nativeOnly=true — suppressing WebView` | `nativeOnly: true` — WebView заблокований, завжди нативний |
| `⚠️ Coordinator: invalid URL → main` | Сервер повернув рядок що не є валідним `http/https` URL |
| `⚠️ Coordinator: network timeout` | Мережа не відповіла за 10 секунд |

### ATT і ідентифікатор пристрою

| Повідомлення | Що означає |
|---|---|
| `✅ ATT: response — authorized=true/false` | Користувач відповів на ATT-діалог |
| `✅ ATT: already determined — authorized=...` | Дозвіл вже вирішено раніше — діалог не показувався |
| `🔑 device = IDFA → ...` | ATT дозволено — IDFA отримано і надіслано на сервер |
| `🔑 device = stable UUID (no IDFA) → ...` | ATT відхилено або недоступно — використовується анонімний UUID |

### Push і FCM

| Повідомлення | Що означає |
|---|---|
| `✅ Push: user responded — granted=true/false` | Результат системного запиту push-дозволу |
| `✅ Sync: new FCM → POST /sync` | FCM-токен оновився після першого запуску — надсилається на сервер |
| `⚠️ Push: FCM token not received within ...s — sending empty` | Firebase не надав FCM-токен до відправки `/install` — перевірте `GoogleService-Info.plist` і Firebase SDK |
| `⚠️ Push: stability timeout — using best available token` | FCM-токен нестабільний — надіслано кращий наявний варіант |
| `❌ AppDelegate: APNs error — ...` | Реєстрація APNs провалилась — перевірте **Push Notifications** capability і сертифікати в Apple Developer Portal |

### Сервер

| Повідомлення | Що означає |
|---|---|
| `✅ Coordinator: register success — url=...` | `/install` виконано — ось URL що відкриється |
| `❌ server error 4xx/5xx — response: ...` | Сервер повернув помилку — деталі у `response` |
| `❌ decoding error — ...` | Відповідь сервера не відповідає очікуваному формату JSON |

### Конфігурація

| Повідомлення | Що означає |
|---|---|
| `⚠️ AppDelegate: firebaseConfigure() not overridden — Firebase not configured` | Забули `override func firebaseConfigure()` — Firebase не ініціалізований |
| `⚠️ startWithTracking: _appDelegate not set yet` | `blackFullIntegration` викликаний до того як AppDelegate встиг підключитись до SRK — зазвичай не проблема |
| `⚠️ startWithTracking asyncAfter: _appDelegate not found` | AppDelegate не знайдено при відправці ATT-запиту — перевірте що `@UIApplicationDelegateAdaptor` оголошений у App struct |
