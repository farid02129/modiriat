"""بعد از flutter create اجرا شود: مجوزها، گیرنده‌ی بوت و desugaring را به پروژه‌ی اندروید اضافه می‌کند."""
import os, re
man = 'android/app/src/main/AndroidManifest.xml'
s = open(man, encoding='utf8').read()
perms = '''<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <queries><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent><intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent></queries>
    <application'''
s = s.replace('<application', perms, 1)
recv = '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
    </application>'''
s = s.replace('</application>', recv, 1)
s = s.replace('android:label="my_goals_app"', 'android:label="روتینو"')
open(man, 'w', encoding='utf8').write(s)

for name, kts in (('build.gradle.kts', True), ('build.gradle', False)):
    p = 'android/app/' + name
    if not os.path.exists(p): continue
    g = open(p, encoding='utf8').read()
    if kts:
        g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', g, 1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', g, 1)
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(p, 'w', encoding='utf8').write(g)
    break
print('patched')
