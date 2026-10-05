REM Update the path to emulator devector.exe if needed.
set s=samples\03_demo\
set e=bin\devector.exe

REM
set compiler=llvm-build\bin\clang
set emulator=%V6EMUL%

set target=-target i8080-unknown-v6clang
set stack_addr=0x8000
set stack_def=-Wl,--defsym=__stack_top=%stack_addr%

REM Build the ROM.
%compiler% %target% -O2 %stack_def% %s%main.c -o %s%main.rom

REM Check for build errors.
if %errorlevel% neq 0 exit /b %errorlevel%

REM Run the ROM in the emulator.
%e% %s%\main.rom