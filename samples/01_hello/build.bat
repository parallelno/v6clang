set s=samples\01_hello\
set compiler=llvm-build\bin\clang
if "%V6EMUL%"=="" (
	echo Set V6EMUL to the separately installed v6emul executable.
	exit /b 1
)
set emulator=%V6EMUL%

set target=-target i8080-unknown-v6clang
set stack_addr=0x8000
set stack_def=-Wl,--defsym=__stack_top=%stack_addr%

REM Build the ROM.
%compiler% %target% -O2 %stack_def% %s%main.c -o %s%main.rom

REM Check for build errors.
if %errorlevel% neq 0 exit /b %errorlevel%

REM Run the ROM in the emulator.
%emulator% --rom %s%main.rom --load-addr 0x0100 --halt-exit --dump-cpu --run-cycles 30000000
