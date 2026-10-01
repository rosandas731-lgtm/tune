@echo off
cd /d "%~dp0"
where flutter >nul 2>nul
if error-level 1 (
  echo Flutter was not found. Install Flutter and add C:\flutter\bin to PATH, then run this again.
  pause
  exit /b 1
)

if not exist android (
  echo Creating Android project files...
  copy /y lib\main.dart main.dart.bak >nul
  copy /y pubspec.yaml pubspec.yaml.bak >nul
  call flutter create --project-name tune_mobile --org com.example --platforms=android .
  if error-level 1 goto fail
  copy /y main.dart.bak lib\main.dart >nul
  copy /y pubspec.yaml.bak pubspec.yaml >nul
  del main.dart.bak pubspec.yaml.bak
  if exist test rmdir /s /q test
)

echo Applying background-playback settings...
copy /y custom_android\AndroidManifest.xml android\app\src\main\AndroidManifest.xml >nul
if not exist android\app\src\main\kotlin\com\example\tune_mobile mkdir android\app\src\main\kotlin\com\example\tune_mobile
copy /y custom_android\MainActivity.kt android\app\src\main\kotlin\com\example\tune_mobile\MainActivity.kt >nul

call flutter pub get
if error-level 1 goto fail
call flutter build apk --release
if error-level 1 goto fail

copy /y build\app\outputs\flutter-apk\app-release.apk Tune.apk >nul
echo.
echo DONE. Your app is Tune.apk in this folder. Copy it to your phone and install it.
pause
exit /b 0

:fail
echo.
echo Something failed. Copy the red error text above and send it to Claude.
pause
exit /b 1
