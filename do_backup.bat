@echo off

REM استخراج التاريخ والوقت
for /f "tokens=2 delims==" %%I in ('"wmic os get localdatetime /value"') do set dt=%%I
set yyyy=%dt:~0,4%
set mm=%dt:~4,2%
set dd=%dt:~6,2%
set hh=%dt:~8,2%
set nn=%dt:~10,2%
set ss=%dt:~12,2%
set today=%yyyy%-%mm%-%dd%
set time=%hh%-%nn%-%ss%

REM مجلد التخزين
set dest=C:\work\done\%today%
if not exist "%dest%" mkdir "%dest%"

REM اسم الملف النهائي مع التاريخ والوقت
set backup_name=mic_visualization_%today%_%time%.7z

REM ضغط الملفات الأساسية
c:\tools\7zc\7z a -y -ssw -t7z %backup_name% ^
pubspec.yaml ^
analysis_options.yaml ^
lib ^
patrol_test ^
integration_test ^
assets ^
README.md ^
android\key.properties ^
android\local.properties ^
android\app\src\main ^
android\app\build.gradle.kts ^
android\app\src\androidTest ^
linux ^
web\index.html ^
ios\Runner\Info.plist ^
do_backup.bat

REM نقل الملف
move /Y %backup_name% "%dest%"

echo Done. Backup saved as %backup_name% in %dest%
