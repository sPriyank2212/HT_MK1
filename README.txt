HT_MK1 - firmware and GUI for the customer
==========================================

Folder contents
  Firmware\   HT_MK1.bin      flash at 0x08000000 (STM32CubeProgrammer)
              HT_MK1.hex      same image, Intel HEX
              HT_MK1.elf      same image with debug symbols
              FIRMWARE_INFO.txt   version, build date, what changed
  GUI\        HT_MK1_GUI.exe        operator GUI for the real instrument
              HT_MK1_GUI_Demo.exe   same GUI with a built-in simulator, no instrument needed
              README.md             how to run it
  Quick_Test_After_Flashing.pdf     short GUI check after flashing (screenshots are from the demo build)
  SHA256SUMS.txt                    checksums of the five files above

Versions
  Firmware   fw 0.1.0, protocol 1, built 2026-11-13 from commit 959de5a (Debug configuration)
  GUI        built 2026-11-13

How to use
  1. Flash Firmware\HT_MK1.bin (full steps: Customer_Package\0_Documents\4_Flashing_Procedure.pdf).
  2. Connect the instrument with a USB Type-C cable (connector J8).
  3. Start GUI\HT_MK1_GUI.exe and follow Quick_Test_After_Flashing.pdf.

Check the files
  In PowerShell, run:  Get-FileHash .\Firmware\HT_MK1.bin -Algorithm SHA256
  The value must match the line for that file in SHA256SUMS.txt.

Other documents (User Manual, System Overview, GUI description) are in Customer_Package\0_Documents.
