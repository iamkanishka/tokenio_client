@echo off
REM Run this script once from inside your tokenio project folder
REM It deletes stale files left over from older versions of the package

echo Cleaning up stale files from tokenio project...

IF EXIST "lib\tokenio\structs.ex" (
    del /F /Q "lib\tokenio\structs.ex"
    echo   Deleted: lib\tokenio\structs.ex
) ELSE (
    echo   OK: lib\tokenio\structs.ex not present
)

IF EXIST "lib\tokenio\apis.ex" (
    echo   OK: lib\tokenio\apis.ex present
) ELSE (
    echo   WARNING: lib\tokenio\apis.ex missing - re-unzip the package
)

IF EXIST "lib\tokenio\payments\payment.ex" (
    echo   OK: lib\tokenio\payments\payment.ex present
) ELSE (
    echo   WARNING: lib\tokenio\payments\payment.ex missing - re-unzip the package
)

IF EXIST "lib\tokenio\vrp\consent.ex" (
    echo   OK: lib\tokenio\vrp\consent.ex present
) ELSE (
    echo   WARNING: lib\tokenio\vrp\consent.ex missing - re-unzip the package
)

echo.
echo Cleanup complete. Run: mix compile
pause
