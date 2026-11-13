@echo off
rem Links this app to the Firebase project studyapp-28624: creates lib\firebase_options.dart
rem and android\app\google-services.json. Output is also saved to build\firebase_link.log.
cd /d "%~dp0"
if not exist build mkdir build
call flutterfire configure --project=studyapp-28624 --platforms=android,web --android-package-name=lk.horizoncampus.studysync --yes > build\firebase_link.log 2>&1
set RC=%ERRORLEVEL%
type build\firebase_link.log
echo EXIT=%RC%>> build\firebase_link.log
echo EXIT=%RC%
