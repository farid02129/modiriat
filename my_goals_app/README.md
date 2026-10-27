# روتینو

اجرا (Flutter نصب باشد):

```
cd my_goals_app
flutter create . --platforms=android --org com.example
flutter pub get
flutter run
flutter build apk --release
```

در `android/app/src/main/AndroidManifest.xml` داخل `<manifest>` برای باز کردن لینک‌ها این را اضافه کن:

```
<queries><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent></queries>
```
