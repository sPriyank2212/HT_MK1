# 3 - Test Results

## Files

| File | What it is |
|---|---|
| `Test_Results_Record.xlsx` | A record sheet for the Functional Test Procedure: TC-01 to TC-08 with expected results and columns for the actual value, Pass/Fail, tester and date; plus unit/session details, deviations and the overall verdict. The same tables are in `../0_Documents/5_Functional_Test_Procedure.docx`. |
| `Sample_Reports/` | Example reports exactly as the GUI writes them - see below. |

## Reports the GUI writes

Export from the **RESULTS** screen (select a run, then Export). Each report has a header block (DUT ID,
operator, netlist, verdict, date/time), a summary, and a results table (the PDF also gives the test duration):

| Report | Files | Status values |
|---|---|---|
| Continuity | `report_..._HT-0008.csv`, `report_..._HT-0004.pdf` | `CONNECTED` / `NOT CONNECTED` |
| Resistance | `..._resistance.csv`, `.pdf` | `PASS` / `FAIL_HIGH` / `FAIL_LOW`, with the measured mOhm |
| Insulation | `..._insulation.csv`, `.pdf` | `PASS` / `FAIL`, with leakage and insulation MOhm |

Enter the **DUT ID** and **Operator** in the status bar before the run so they appear in the report.

The GUI also keeps a run history and a session log on the PC, under
`%LOCALAPPDATA%\HT_MK1\history` and `\sessions`.
The samples here are from earlier development runs, shown for their format only.
