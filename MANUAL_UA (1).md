# ScreenRouterKit — Повний мануал з інтеграції

> Версія для початківців. Не потрібно знати Swift на рівні експерта —
> кожен крок пояснений з нуля.

---

## Швидкий старт — що, куди і навіщо

Якщо не хочете читати все одразу — ось мінімум для старту.
Деталі і пояснення кожного пункту — нижче в розділах.

---

### 1 — Info.plist — вимикаємо Firebase swizzling

**Куди:** файл `Info.plist` у корені проекту додоати: 
| `FirebaseAppDelegateProxyEnabled` | Boolean | NO |
**Навіщо:** без цього Firebase перехоплює APNs-методи сам, конфліктує з бібліотекою, push не працюватимуть.

або як Source Code
```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

---

## 2. Встановлення — копіювання папки

Бібліотека підключається **не через Swift Package Manager**, а вручну —
простим копіюванням папки з вихідним кодом у ваш проект.

**Кроки:**

1. Відкрийте архів бібліотеки. Знайдіть папку:
   ```
   ScreenRouterKit/Sources/ScreenRouterKit/
   ```

2. Перетягніть цю папку у **Xcode** у дерево проекту (ліва панель).

3. Xcode покаже діалог — виберіть такі опції:
   - ✅ **Copy items if needed**
   - **Added folders:** виберіть «Create groups»
   - **Add to targets:** оберіть ваш основний таргет

4. Натисніть **Finish**.

5. Запустіть збірку **Cmd + B**. Якщо помилок немає — все готово.

> Ніякого `Package.swift`, ніяких залежностей — просто файли `.swift`
> прямо у вашому проекті.

---

### 3 — AppDelegate.swift — токени, логування, Firebase

**Куди:** ваш файл `AppDelegate.swift`.  
**Навіщо:** оскільки swizzling вимкнений, APNs-токен треба передати у Firebase вручну (`apnsToken`), а FCM-токен — у бібліотеку через `MessagingDelegate`. Без цього push і аналітика не працюватимуть.

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
        Messaging.messaging().apnsToken = deviceToken        // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)  // потім бібліотека
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

> Якщо використовуєте **AppsFlyer** — AppDelegate виглядає інакше.
> Дивіться [Розділ 4 → «Якщо використовуєте AppsFlyer»](#4-налаштування-appdelegate).

---

### 4 — MyApp.swift — запуск бібліотеки

**Куди:** ваш файл з `@main`, всередину `WindowGroup { }`.  
**Навіщо:** це головний виклик — бібліотека показує splash, звертається до сервера і вирішує що показати далі.

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:        "api.myapp.com",      // ← ваш домен
                bundleID:    "com.mycompany.app",  // ← ваш Bundle ID
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete)) // ← ваш spalsh
                },
                mainView: {
                    AnyView(ContentView())         // ← ваш головний екран
                },
                attDelay:    1.5 // ← затримка запиту трекінгу
            )
        }
    }
}
```

---

### 5 — SplashView.swift — ваша заставка

**Куди:** в ваш `SplashView.swift` у вашому проекті.  
**Навіщо:** бібліотека показує цей екран поки іде мережевий запит. Коли splash завершив анімацію — викличте `onComplete()`, щоб бібліотека перейшла далі.

```swift
import SwiftUI

struct SplashView: View {
    let onComplete: () -> Void   // ← цей callback ОБОВ'ЯЗКОВО викликати

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
        }
        .onAppear { 
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // краще Task.sleep(for:)
                onComplete()     // ← повідомляємо бібліотеку що splash завершено
            }
        }
    }
}
```

Додоаткові варінти виклику ios 17+ 

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.18).ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale   = 1.0  // що анімується
                logoOpacity = 1.0
            } completion: {
                onComplete()       // викликається ПІСЛЯ завершення анімації
            }
        }
    }
}
```


## Детальний опис
---

## Зміст

1. [Що робить ця бібліотека](#1-що-робить-ця-бібліотека)
2. [Встановлення — копіювання папки](#2-встановлення--копіювання-папки)
3. [Налаштування Info.plist — вимкнення Firebase Swizzling](#3-налаштування-infoplist--вимкнення-firebase-swizzling)
4. [Налаштування AppDelegate](#4-налаштування-appdelegate)
5. [SplashView та callback onComplete](#5-splashview-та-callback-oncomplete)
6. [Вибір функції запуску](#6-вибір-функції-запуску)
7. [Функція `present` — тільки нативний екран](#7-функція-present--тільки-нативний-екран)
8. [Функція `start` — з сервером](#8-функція-start--з-сервером)
9. [Функція `startWithTracking` — з AppsFlyer](#9-функція-startwithtracking--з-appsflyer)
10. [Опціональні параметри](#10-опціональні-параметри)
11. [FCM-токен — як передати Firebase token](#11-fcm-токен--як-передати-firebase-token)
12. [Додаткові API](#12-додаткові-api)
13. [Повні приклади інтеграції](#13-повні-приклади-інтеграції)
14. [Типові помилки](#14-типові-помилки)
15. [Коротка шпаргалка](#15-коротка-шпаргалка)

---

## 1. Що робить ця бібліотека

ScreenRouterKit — це «диспетчер» для вашого застосунку. При кожному старті він:

1. Показує **splash-екран** (заставку)
2. Перевіряє **наявність інтернету**
3. Запитує дозвіл **ATT** (відстеження реклами) — якщо потрібно
4. Запитує дозвіл на **push-сповіщення** — якщо потрібно
5. Звертається до **вашого сервера** і отримує відповідь:
   - сервер повернув URL → відкриває **WebView** з цим URL
   - URL порожній або немає інтернету → показує **нативний екран**

Вам **не потрібно** розбиратися у внутрішній логіці.
Ваше завдання — викликати одну з трьох функцій і передати потрібні параметри.

---

## 2. Встановлення — копіювання папки

Бібліотека підключається **не через Swift Package Manager**, а вручну —
простим копіюванням папки з вихідним кодом у ваш проект.

**Кроки:**

1. Відкрийте архів бібліотеки. Знайдіть папку:
   ```
   ScreenRouterKit/Sources/ScreenRouterKit/
   ```

2. Перетягніть цю папку у **Xcode** у дерево проекту (ліва панель).

3. Xcode покаже діалог — виберіть такі опції:
   - ✅ **Copy items if needed**
   - **Added folders:** виберіть «Create groups»
   - **Add to targets:** оберіть ваш основний таргет

4. Натисніть **Finish**.

5. Запустіть збірку **Cmd + B**. Якщо помилок немає — все готово.

> Ніякого `Package.swift`, ніяких залежностей — просто файли `.swift`
> прямо у вашому проекті.

---

## 3. Налаштування Info.plist — вимкнення Firebase Swizzling

Якщо у проекті є **Firebase** — він за замовчуванням «перехоплює» (swizzle)
методи AppDelegate для push-сповіщень. Це конфліктує з бібліотекою,
тому swizzling треба вимкнути вручну.

**Відкрийте `Info.plist` і додайте ключ:**

| Ключ | Тип | Значення |
|---|---|---|
| `FirebaseAppDelegateProxyEnabled` | Boolean | NO |

**У вигляді XML** (якщо редагуєте файл як Source Code):

```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

> Без цього налаштування Firebase буде конфліктувати з обробкою APNs-токена,
> і push-сповіщення можуть не реєструватися коректно.

---

## 4. Налаштування AppDelegate

Бібліотека надає готовий базовий клас `SRKAppDelegate`.
Ваш `AppDelegate` повинен **успадкувати** його і додати чотири методи.

### Чому потрібно override методи токенів

Оскільки Firebase swizzling вимкнений (крок 3), Firebase **сам не бачить** APNs-токен.
Тому в `didRegisterForRemoteNotificationsWithDeviceToken` ми робимо дві речі вручну:
1. Передаємо APNs-токен у Firebase Messaging — `Messaging.messaging().apnsToken = deviceToken`
2. Передаємо APNs-токен у бібліотеку — `ScreenRouterKit.shared.handleAPNSToken(deviceToken)`

Без першого рядка Firebase не зможе видати FCM-токен.

---

### Повний AppDelegate — копіюйте як є

```swift
// AppDelegate.swift
import UIKit
import Firebase
import FirebaseMessaging

final class AppDelegate: SRKAppDelegate, MessagingDelegate {

    // Ініціалізуємо Firebase і призначаємо себе делегатом FCM
    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    // Передаємо APNs-токен вручну і в Firebase, і в бібліотеку
    // (потрібно бо swizzling вимкнений — Firebase сам токен не бачить)
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken       // спочатку Firebase
        ScreenRouterKit.shared.handleAPNSToken(deviceToken) // потім бібліотека
    }

    // Логуємо якщо реєстрація push не вдалася
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SRKLogger.log(.error, "APNs error — \(error.localizedDescription)")
    }

    // Firebase отримав FCM-токен — передаємо його в бібліотеку
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        ScreenRouterKit.shared.handleFCMToken(token)
    }
}
```

Це повний AppDelegate. Більше нічого додавати не потрібно.

---

### Якщо використовуєте AppsFlyer

Додайте ці зміни тільки якщо викликаєте `startWithTracking(...)` (дивіться [Крок 9](#9-функція-startwithtracking--з-appsflyer)):

```swift
import UIKit
import Firebase
import FirebaseMessaging
import AppsFlyerLib

final class AppDelegate: SRKAppDelegate, MessagingDelegate {

    // Реєструємо делегат до того як SwiftUI запустить body
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ScreenRouterKit.shared._appDelegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    // Ключі AppsFlyer SDK
    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = "ВАШ_КЛЮЧ_APPSFLYER"
        AppsFlyerLib.shared().appleAppID      = "ВАШ_APPLE_APP_ID"
        AppsFlyerLib.shared().delegate        = self
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

    // Опційно: викликається після відповіді користувача на ATT-запит
    override func attDidComplete(authorized: Bool) {
        // authorized == true — користувач дозволив відстеження
    }
}

extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {}
    func onConversionDataFail(_ error: Error) {}
}
```

---

### Підключення AppDelegate до SwiftUI App

Якщо ваш проект використовує SwiftUI App lifecycle (файл з `@main` і `struct ... App`),
AppDelegate підключається через `UIApplicationDelegateAdaptor`:

```swift
// MyApp.swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // Тут виклик однієї з функцій бібліотеки (дивіться Крок 6+)
        }
    }
}
```

---

## 5. SplashView та callback `onComplete`

Це один з найважливіших розділів. Розберіть його уважно.

### Що таке `onComplete`

Кожна функція запуску бібліотеки приймає параметр `splash:` —
замикання, де ви повертаєте ваш `SplashView`.

Бібліотека передає у ваш SplashView спеціальну функцію-callback — `onComplete`.

```
splash: { onComplete in
    AnyView( ВАШ_SPLASH_VIEW(onComplete: onComplete) )
}
```

**`onComplete` — це сигнал від вашого SplashView до бібліотеки.**
Поки ви не викличете `onComplete()`, бібліотека буде чекати і **не перейде** до наступного екрана.

### Навіщо це потрібно

Бібліотека паралельно робить два завдання:
- чекає поки ваш splash програє анімацію (через `onComplete`)
- виконує мережевий запит до сервера

Перехід відбудеться тільки коли **обидва** завдання завершені.
Це гарантує що користувач не побачить миготіння або незавершений перехід.

```
Старт застосунку
       │
       ├──► Мережевий запит до сервера ──────────────────┐
       │                                                  │
       └──► Ваш SplashView грає анімацію ─► onComplete() ┘
                                                          │
                                              Перехід до наступного екрана
```

### Правило: `onComplete` треба викликати рівно один раз

| Ситуація | Як викликати |
|---|---|
| Фіксована тривалість (2 секунди) | Через `DispatchQueue.main.asyncAfter` або `Task.sleep(for:)` |
| Lottie або інша анімація | У callback завершення анімації |
| Складний splash з кількома етапами | Після останнього етапу |

> **Важливо:** якщо `onComplete()` не викликати — splash ніколи не зникне.
> Якщо викликати двічі — нічого страшного, бібліотека ігнорує повторні виклики.

---

### Приклади SplashView

#### Варіант 1 — Статичний екран з фіксованою тривалістю

```swift
struct SplashView: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
        }
        .onAppear {
            // Через 2.5 секунди повідомляємо бібліотеку що splash завершено
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onComplete()
            }
        }
    }
}
```

#### Варіант 2а — withAnimation + completion (iOS 17+, найчистіший спосіб)

`completion:` — це блок який SwiftUI викликає **точно після** того як анімація завершилась.
Не треба рахувати секунди вручну через `asyncAfter`.

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.18).ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale   = 1.0  // що анімується
                logoOpacity = 1.0
            } completion: {
                onComplete()       // викликається ПІСЛЯ завершення анімації
            }
        }
    }
}
```

#### Варіант 2б — withAnimation + asyncAfter (до iOS 17 або кілька фаз)

Якщо потрібно підтримувати iOS 16 або зробити кілька послідовних анімацій —
використовуйте `asyncAfter` з часом трохи більшим ніж тривалість анімації.

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.18).ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            // Фаза 1 — поява логотипу
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale   = 1.0
                logoOpacity = 1.0
            }
            // Фаза 2 — після паузи повідомляємо бібліотеку
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onComplete()
            }
        }
    }
}
```

#### Варіант 3 — Lottie-анімація

```swift
import Lottie

struct LottieSplashView: View {
    let onComplete: () -> Void

    var body: some View {
        LottieView(animation: .named("splash"))
            .playing(loopMode: .playOnce)
            .animationDidFinish { _ in
                // Lottie сам повідомляє коли анімація завершена
                onComplete()
            }
            .ignoresSafeArea()
            .background(Color.black)
    }
}
```

#### Варіант 4 — Splash з логотипом і прогрес-баром

```swift
struct SplashView: View {
    let onComplete: () -> Void

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 32) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                ProgressView(value: progress)
                    .frame(width: 200)
                    .tint(.blue)
            }
        }
        .onAppear {
            // Анімуємо прогрес-бар від 0 до 1 за 2 секунди
            withAnimation(.linear(duration: 2.0)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onComplete()
            }
        }
    }
}
```

---

## 6. Вибір функції запуску

Бібліотека має **три** різні функції запуску. Вибір залежить від того,
що має робити ваш застосунок.

| Функція | Коли використовувати |
|---|---|
| `present(...)` | Тільки splash + нативний екран. **Без сервера.** Підходить для простих застосунків без WebView. |
| `start(...)` | **Повний режим:** splash → сервер → WebView або нативний. Стандартний варіант. |
| `startWithTracking(...)` | Те саме що `start()`, але з **AppsFlyer** та IDFA. Використовуйте якщо підключено AppsFlyer SDK. |

---

## 7. Функція `present` — тільки нативний екран

Ця функція **не звертається до жодного сервера**. Вона просто показує ваш
splash-екран, чекає `onComplete()`, і переходить до нативного View.

### Параметри

```swift
ScreenRouterKit.shared.present(
    transition:          SRKTransitionConfig,         // ОПЦІЙНО  — анімація переходу від splash
    splash:              { onComplete in AnyView },   // ОБОВ'ЯЗКОВО — ваш splash-екран
    mainView:            { AnyView },                 // ОБОВ'ЯЗКОВО — ваш основний екран
    debugMode:           SRKDebugMode,                // ОПЦІЙНО  — рівень логів у консолі
    attHandling:         SRKATTHandling,              // ОБОВ'ЯЗКОВО — хто управляє ATT-діалогом
    attDelay:            TimeInterval,                // ОБОВ'ЯЗКОВО — затримка ATT (передайте 0 якщо .skip)
    defaultOrientations: UIInterfaceOrientationMask,  // ОПЦІЙНО  — орієнтація для нативного екрана
    webOrientations:     UIInterfaceOrientationMask   // ОПЦІЙНО  — не актуально для цього режиму
)
```

### Мінімальний приклад

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                attHandling: .skip,
                attDelay: 0
            )
        }
    }
}
```

---

## 8. Функція `start` — з сервером

Це основна функція. Вона звертається до вашого бекенду, отримує URL і вирішує що показати:
- є валідний URL → відкриває **WebView**
- URL порожній або немає інтернету → показує нативний **mainView**

Є два варіанти виклику.

### Варіант A — через `host` (простіше)

```swift
ScreenRouterKit.shared.start(
    host:        "api.myapp.com",     // домен без https:// і слешів
    bundleID:    "com.mycompany.app", // Bundle ID вашого застосунку
    splash:      { onComplete in AnyView(SplashView(onComplete: onComplete)) },
    mainView:    { AnyView(ContentView()) },
    attHandling: .managedByLibrary,
    attDelay:    1.5
)
```

Бібліотека сама побудує URL:
- `registerURL` = `https://api.myapp.com/v1/public/install`
- `syncURL` = `https://api.myapp.com/v1/public/refresh`

### Варіант B — через прямі URL

Використовуйте якщо структура вашого API нестандартна.

```swift
ScreenRouterKit.shared.start(
    registerURL: "https://api.myapp.com/install",
    syncURL:     "https://api.myapp.com/refresh",
    bundleID:    "com.mycompany.app",
    splash:      { onComplete in AnyView(SplashView(onComplete: onComplete)) },
    mainView:    { AnyView(ContentView()) },
    attHandling: .managedByLibrary,
    attDelay:    1.5
)
```

---

## 9. Функція `startWithTracking` — з AppsFlyer

Те саме що `start()`, але додатково:
- Автоматично запитує ATT через AppDelegate
- Отримує **IDFA** (ідентифікатор пристрою для реклами)
- Запускає **AppsFlyer** та зберігає `appsFlyerUID`
- Передає `appsFlyerID` разом з запитом до сервера

**Вимоги:** AppDelegate повинен успадкувати `SRKAppDelegate` і перевизначити
`appsFlyerConfigure()` (дивіться [Крок 4](#4-налаштування-appdelegate)).

> При `startWithTracking` параметр `attHandling` відсутній —
> бібліотека завжди управляє ATT через AppDelegate автоматично.

### Підключення AppDelegate перед викликом

`startWithTracking` звертається до AppDelegate щоб запустити AppsFlyer і ATT.
Тому посилання на делегат має бути передане **до** того як SwiftUI викличе `body`.

Правильний спосіб — зробити це всередині `didFinishLaunchingWithOptions` у самому AppDelegate.
Він гарантовано викликається першим, до будь-якого коду у SwiftUI:

```swift
// AppDelegate.swift
final class AppDelegate: SRKAppDelegate, MessagingDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ScreenRouterKit.shared._appDelegate = self  // реєструємо делегат першим
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ...решта методів
}
```

```swift
// MyApp.swift
@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:     "api.myapp.com",
                bundleID: "com.mycompany.app",
                splash:   { onComplete in AnyView(SplashView(onComplete: onComplete)) },
                mainView: { AnyView(ContentView()) },
                attDelay: 2.0
            )
        }
    }
}
```

> `super.application(...)` обов'язково — він запускає Firebase, AppsFlyer та push реєстрацію.

---

## 10. Опціональні параметри

Усі наступні параметри **не обов'язкові**. Якщо їх не передавати —
бібліотека використає значення за замовчуванням.

---

### `transition: SRKTransitionConfig`
**Замовчування:** `.fade`

Визначає анімацію переходу від splash-екрана до основного контенту.

| Значення | Ефект |
|---|---|
| `.fade` | Плавне зникнення (за замовчуванням) |
| `.slideUp` | Splash їде вгору |
| `.slideDown` | Splash їде вниз |
| `.scale` | Splash масштабується і зникає |

Можна задати власний варіант:

```swift
transition: SRKTransitionConfig.custom(
    type: .slide(.left),
    animation: .spring(duration: 0.4)
)
```

**Коли змінювати:** якщо стандартний fade не підходить до дизайну вашого splash.

```swift
ScreenRouterKit.shared.start(
    transition: .slideUp,
    host: "api.myapp.com",
    // ...
)
```

---

### `debugMode: SRKDebugMode`
**Замовчування:** `.minimal`

Керує тим, що бібліотека виводить у консоль Xcode.

| Значення | Що виводить |
|---|---|
| `.disabled` | Нічого |
| `.minimal` | Тільки ключові події: фінальний URL, FCM-токен, Device ID, помилки |
| `.verbose` | Все — кожен крок роботи бібліотеки |

**Коли використовувати:**
- Під час розробки → `.verbose`
- Перед релізом → `.disabled`
- Стандартно → `.minimal`

```swift
ScreenRouterKit.shared.start(
    // ...
    debugMode: .verbose,
    // ...
)
```

---

### `attHandling: SRKATTHandling`
**Замовчування:** `.managedByLibrary` (у `start`), `.skip` (у `present`)

Визначає хто і як показує системний діалог дозволу ATT
*(App Tracking Transparency — «Дозволити додатку відстежувати вас?»)*.

**`.managedByLibrary`**
Бібліотека сама показує системний діалог ATT у потрібний момент.
Використовуйте якщо у вас немає AppsFlyer або власної логіки ATT.

**`.skip`**
ATT взагалі не запитується. Пристрій ідентифікується через внутрішній UUID.
Використовуйте якщо застосунок не використовує рекламу/трекінг.

**`.managedByHost(signal: SRKATTSignal)`**
Ви самі показуєте діалог ATT (або власний попередній екран),
а потім сигналізуєте бібліотеці через `signal.complete(authorized:)`.
Використовуйте якщо хочете показати власний екран-пояснення
перед системним діалогом ATT.

```swift
// Створюємо сигнал
let attSignal = SRKATTSignal()

ScreenRouterKit.shared.start(
    // ...
    attHandling: .managedByHost(signal: attSignal),
    attDelay: 0,
    // ...
)

// Пізніше — після того як ваш екран-пояснення закрився:
ATTrackingManager.requestTrackingAuthorization { status in
    attSignal.complete(authorized: status == .authorized)
}
```

---

### `attDelay: TimeInterval`
**Обов'язковий**, але можна передати `0`

Затримка в секундах перед показом системного ATT-діалогу.

> Apple рекомендує не показувати ATT одразу при старті.
> Краще дати користувачеві секунду-дві побачити застосунок, і тоді
> запитати дозвіл — так вищий відсоток погоджень.

Передавайте `0` якщо `attHandling` = `.skip` або `.managedByHost`.

```swift
attDelay: 1.5   // показати ATT через 1.5 секунди
```

---

### `pushEnabled: Bool`
**Замовчування:** `true`

Чи запитувати у користувача дозвіл на push-сповіщення.

Передайте `false` якщо застосунок взагалі не використовує push.
Тоді бібліотека не буде показувати системний діалог дозволу.

```swift
pushEnabled: false
```

---

### `fallbackURL: String?`
**Замовчування:** `nil`

Резервна URL-адреса WebView, яка використовується якщо сервер
не повернув URL, але попередній запуск вже зберіг маршрут «web».

**Коли використовувати:** якщо хочете гарантовано показати WebView
навіть у разі тимчасової недоступності сервера (при повторних запусках).

```swift
fallbackURL: "https://myapp.com/fallback"
```

---

### `nativeOnly: Bool`
**Замовчування:** `false`

Якщо передати `true` — бібліотека **завжди** показує нативний екран,
навіть якщо сервер повернув URL для WebView.

**Коли використовувати:**
- У режимі налагодження
- Якщо хочете тимчасово вимкнути WebView без змін на сервері
- Для **App Review** — щоб ревьюери Apple бачили нативний контент

```swift
nativeOnly: true
```

---

### `defaultOrientations: UIInterfaceOrientationMask`
**Замовчування:** `.portrait`

Орієнтація екрана коли відображається нативний View або splash.

| Значення | Ефект |
|---|---|
| `.portrait` | Тільки вертикально (звичайно) |
| `.landscape` | Тільки горизонтально |
| `.all` | Будь-яка орієнтація |
| `.allButUpsideDown` | Всі крім перевернутого вертикального |

**Коли змінювати:** якщо нативний застосунок підтримує горизонтальний
режим (наприклад, гра або відеоплеєр).

```swift
defaultOrientations: .all
```

---

### `webOrientations: UIInterfaceOrientationMask`
**Замовчування:** `.all`

Орієнтація екрана коли відображається WebView.

За замовчуванням WebView підтримує всі орієнтації, бо веб-сайти
зазвичай підтримують обидва режими.

**Коли змінювати:** якщо ваш веб-сайт оптимізований тільки для
вертикального режиму і ви не хочете щоб користувач міг повертати екран.

```swift
webOrientations: .portrait
```

---

## 11. Як працює передача токенів

Повний код AppDelegate наведений у [Кроці 4](#4-налаштування-appdelegate).
Тут пояснення логіки для розуміння.

**Ланцюжок токенів через вимкнений swizzling:**

```
iOS реєструє push
       │
       ▼
didRegisterForRemoteNotificationsWithDeviceToken(deviceToken)
       │
       ├──► Messaging.messaging().apnsToken = deviceToken
       │         │
       │         └──► Firebase тепер знає APNs-токен
       │                   │
       │                   └──► Firebase видає FCM-токен
       │                               │
       │                               ▼
       │                   messaging(_:didReceiveRegistrationToken:)
       │                               │
       │                               └──► ScreenRouterKit.shared.handleFCMToken(token)
       │
       └──► ScreenRouterKit.shared.handleAPNSToken(deviceToken)
```

Якщо **не** виставити `Messaging.messaging().apnsToken` вручну — Firebase не отримає APNs-токен
(swizzling вимкнений), а значить не зможе видати FCM-токен взагалі.

---

## 12. Додаткові API

### `ScreenRouterKit.shared.presented`

Повертає поточний стан застосунку: `.loading`, `.main`, або `.web(url: "...")`.
Корисно якщо потрібно дізнатися що зараз показується на екрані.

```swift
let scene = ScreenRouterKit.shared.presented

switch scene {
case .loading:
    print("Іде завантаження")
case .main:
    print("Показано нативний екран")
case .web(let url):
    print("Показано WebView: \(url)")
}
```

---

### `ScreenRouterKit.shared.presentedPublisher`

Підписка Combine на зміни стану. Використовуйте якщо треба реагувати
на зміну екрана (наприклад, показати/сховати UI-елемент).

```swift
ScreenRouterKit.shared.presentedPublisher?
    .sink { scene in
        if case .web = scene {
            print("Відкрито WebView")
        }
    }
    .store(in: &cancellables)
```

---

### `ScreenRouterKit.shared.reset()`

Повністю скидає стан бібліотеки: очищає `UserDefaults`,
скидає лічильники, дозволяє запустити `start()` знову.

> Використовуйте тільки якщо треба «перезапустити» логіку з нуля
> (наприклад, після logout або для тестування).

```swift
ScreenRouterKit.shared.reset()
```

---

## 13. Повні приклади інтеграції

---

### Приклад 1 — Простий нативний застосунок
*Без сервера, без трекінгу, без push*

**`AppDelegate.swift`**

```swift
import UIKit
import Firebase

class AppDelegate: SRKAppDelegate {

    override func firebaseConfigure() {
        FirebaseApp.configure()
    }
}
```

**`MyApp.swift`**

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.present(
                transition:  .fade,
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                debugMode:   .minimal,
                attHandling: .skip,
                attDelay:    0
            )
        }
    }
}
```

---

### Приклад 2 — Стандартна інтеграція з сервером і Firebase FCM

**`AppDelegate.swift`**

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
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)
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

**`MyApp.swift`**

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.start(
                host:        "api.myapp.com",
                bundleID:    "com.mycompany.app",
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attHandling: .managedByLibrary,
                attDelay:    1.5,
                fallbackURL: "https://myapp.com"
            )
        }
    }
}
```

---

### Приклад 3 — Інтеграція з AppsFlyer

**`AppDelegate.swift`**

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
        ScreenRouterKit.shared._appDelegate = self  // до SwiftUI body
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func firebaseConfigure() {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    override func appsFlyerConfigure() {
        AppsFlyerLib.shared().appsFlyerDevKey = "YOUR_APPSFLYER_KEY"
        AppsFlyerLib.shared().appleAppID      = "YOUR_APPLE_APP_ID"
        AppsFlyerLib.shared().delegate        = self
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        ScreenRouterKit.shared.handleAPNSToken(deviceToken)
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

    override func attDidComplete(authorized: Bool) {}
}

extension AppDelegate: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {}
    func onConversionDataFail(_ error: Error) {}
}
```

**`MyApp.swift`**

```swift
import SwiftUI

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ScreenRouterKit.shared.startWithTracking(
                host:        "api.myapp.com",
                bundleID:    "com.mycompany.app",
                splash: { onComplete in
                    AnyView(SplashView(onComplete: onComplete))
                },
                mainView: {
                    AnyView(ContentView())
                },
                debugMode:   .minimal,
                pushEnabled: true,
                attDelay:    2.0,
                fallbackURL: "https://myapp.com"
            )
        }
    }
}
```

---

## 14. Типові помилки

| Помилка | Причина | Рішення |
|---|---|---|
| Splash ніколи не зникає | `onComplete()` не викликається у `SplashView` | Переконайтеся що `onComplete()` викликається — або після анімації, або через `asyncAfter` |
| Push не реєструються | Firebase swizzling не вимкнено | Додайте `FirebaseAppDelegateProxyEnabled = NO` у `Info.plist` |
| `startWithTracking` — «appDelegate not set yet» | `_appDelegate` не призначений до виклику | Додайте `ScreenRouterKit.shared._appDelegate = self` першим рядком у `didFinishLaunchingWithOptions` вашого AppDelegate, і обов'язково викличте `super` |
| Білий екран замість нативного контенту | `mainView` не передано або повертає пусте View | Переконайтеся що передаєте `mainView: { AnyView(ContentView()) }` |
| Орієнтація не змінюється у WebView | `AppDelegate` не успадковує `SRKAppDelegate` | Замість `class AppDelegate: NSObject` зробіть `class AppDelegate: SRKAppDelegate` |

---

## 15. Коротка шпаргалка

**Немає сервера, тільки нативний екран?**
```swift
present(splash:, mainView:, attHandling: .skip, attDelay: 0)
```

**Є сервер, може показувати WebView, без AppsFlyer?**
```swift
start(host:, bundleID:, splash:, mainView:, attHandling: .managedByLibrary, attDelay: 1.5)
```

**Є сервер + AppsFlyer?**
```swift
// 1. AppDelegate успадковує SRKAppDelegate
// 2. У didFinishLaunchingWithOptions: ScreenRouterKit.shared._appDelegate = self + super
// 3. Перевизначте appsFlyerConfigure() та додайте AppsFlyerLibDelegate через extension
startWithTracking(host:, bundleID:, splash:, mainView:, attDelay: 2.0)
```

**Потрібно тимчасово вимкнути WebView (для тестування або App Review)?**
```swift
// Додайте до будь-якої функції:
nativeOnly: true
```

**Проблеми з push або хочете бачити що відбувається?**
```swift
// Додайте до будь-якої функції:
debugMode: .verbose
```
