HT_MK1 firmware - 2026-11-18 - "fault-reporting"
================================================

Includes everything in Built_Image_2026-11-17_selfcheck PLUS the change below.

Why: the selfcheck image left the board completely silent (no reply to >STATUS,
no console text). Every failure path in the firmware used to end in
"while (1) {}" - HardFault, MemManage, BusFault, UsageFault, NMI, stack overflow,
heap exhaustion, configASSERT, Error_Handler, and any interrupt without a handler
(startup Default_Handler) - so a crash looked identical to "board dead".

What changed (new files Core/Src/app/fault.c, Core/Inc/app/fault.h):
 1. All of those paths now print WHAT failed and WHERE on the console (polled
    USART2: works with the RTOS dead / interrupts off / before the logger exists),
    keep a copy in no-init RAM, and RESET the MCU so the board comes back.
      #E[0] FAULT: HardFault FORCED PRECISERR task=tComms in-irq=..
      #E[0] FAULT: pc=0x08004A3C lr=0x08004A21 psr=... sp=...
      #E[0] FAULT: CFSR=0x... HFSR=0x... BFAR=0x... MMFAR=0x...
      #E[0] FAULT: file:line -> arm-none-eabi-addr2line -f -i -e HT_MK1.elf 0x08004A3C 0x08004A21
      #E[0] FAULT: resetting (crash #1)
    assert / Error_Handler / heap / stack overflow:
      #E[0] FAULT: assert task=tSequencer : tasks.c:123 queue != NULL
      #E[0] FAULT: MallocFailed ...      #E[0] FAULT: StackOverflow task <name>
    A CPU fault gives the faulting PC: run the printed addr2line command against
    the matching HT_MK1.elf (kept in this folder) for file:line.
 2. The Usage/Bus/MemManage fault handlers are enabled, so a fault is reported as
    what it is instead of a bare HardFault.
 3. An interrupt with no handler is reported once, disabled, and the system carries
    on (it used to spin forever in Default_Handler).
 4. The crash survives the reset: on the next boot (and on every host >ID) the
    logger prints  CRASH: previous run died ... pc=... line: addr2line ...
    so it shows in the GUI log / Save Log even if the GUI was not connected.
 5. Boot trace on the console: "#I[0] BOOT: main: ...", "Board_Init: stage matrix",
    "... stage ads124s08", "... stage frontend", "stage hv", "stage temp",
    "Tasks_Init: ...". If the board ever goes silent again with no FAULT line, the
    LAST BOOT line is where it stopped (a plain hang, not a fault).
 6. Crash-loop guard: two crashes in a row (no 8 s of uptime between) => SAFE MODE
    on the next boot: continue-on-fail init, boot bus scans and the self-check
    thread are skipped, so the plain known-good start-up runs and commands work.
    The first crash line still prints, plus "SAFE MODE".

Unchanged: all DIAG file:line failure logging, command handling, protocol.

To remove the boot trace: FAULT_BOOT_TRACE 0 in Core/Inc/app/fault.h.

NOT run on hardware (no board here). The reporter itself is untested on the
target; if a fault happens its text is the first thing to send back.
Build: 0 errors, 0 warnings. text 100824 B, data 116 B, bss 41556 B.
Linker script: new .noinit section (after .bss) for the crash record.
Startup: Default_Handler now jumps to Fault_UnhandledIrq.
