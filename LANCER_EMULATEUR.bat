@echo off
chcp 65001 >nul
title VIGIMAT - Lancement Emulateur Android
echo ======================================================================
echo          VIGIMAT : DEMARRAGE DE L'EMULATEUR ANDROID STUDIO           
echo ======================================================================
echo.
echo [1/3] Demarrage de la fenetre de l'emulateur (Medium_Phone_API_37.0)...
start "" "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0 -gpu host

echo [2/3] En attente du demarrage complet du systeme Android...
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 wait-for-device shell 'while [[ "$(getprop sys.boot_completed)" != "1" ]]; do sleep 1; done'

echo [3/3] Installation et ouverture de l'application VIGIMAT...
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 install -r "%~dp0build\app\outputs\flutter-apk\app-debug.apk"
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 shell am start -n com.example.vigimat/.MainActivity

echo.
echo ======================================================================
echo   L'application est ouverte et prete sur l'emulateur !
echo ======================================================================
timeout /t 5 >nul
