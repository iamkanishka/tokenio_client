@echo off
REM Run this script once from inside your tokenio_client project folder
REM It deletes stale files left over from older versions of the package

echo Cleaning up stale files from tokenio_client project...

IF EXIST "lib\tokenio_client\structs.ex" (
    del /F /Q "lib\tokenio_client\structs.ex"
    echo   Deleted: lib\tokenio_client\structs.ex
) ELSE (
    echo   OK: lib\tokenio_client\structs.ex not present
)

IF EXIST "lib\tokenio_client\apis.ex" (
    echo   OK: lib\tokenio_client\apis.ex present
) ELSE (
    echo   WARNING: lib\tokenio_client\apis.ex missing - re-unzip the package
)

IF EXIST "lib\tokenio_client\payments\payment.ex" (
    echo   OK: lib\tokenio_client\payments\payment.ex present
) ELSE (
    echo   WARNING: lib\tokenio_client\payments\payment.ex missing - re-unzip the package
)

IF EXIST "lib\tokenio_client\vrp\consent.ex" (
    echo   OK: lib\tokenio_client\vrp\consent.ex present
) ELSE (
    echo   WARNING: lib\tokenio_client\vrp\consent.ex missing - re-unzip the package
)

echo.
echo Cleanup complete. Run: mix compile
pause
