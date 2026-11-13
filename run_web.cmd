@echo off
rem Runs StudySync in Chrome WITHOUT losing data between runs.
rem `flutter run -d chrome` normally starts Chrome with a new temporary profile each time,
rem which wipes the app's saved data. This uses a fixed port and a permanent profile folder.
cd /d "%~dp0"
flutter run -d chrome --web-port=8800 --web-browser-flag="--user-data-dir=%LOCALAPPDATA%\StudySyncChrome"
