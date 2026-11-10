# Bank Batch Processing in COBOL

[![tests](https://github.com/muffindonor/cobol-bank-batch/actions/workflows/tests.yml/badge.svg)](https://github.com/muffindonor/cobol-bank-batch/actions/workflows/tests.yml)

A nightly batch job that posts a day's transactions to customer accounts. It uses the classic balanced-line pattern: old master plus sorted transactions gives a new master.

```
ACCTMAST.DAT ─┐                  ┌─ ACCTMAST.NEW  new master
              ├─ BANKBTCH ───────┼─ REJECTS.DAT   failed transactions, with reasons
TRANS.DAT ────┘                  └─ REPORT.TXT    account report, control totals
```

## Features

- Exact decimal money handling with packed decimal (`COMP-3`).
- Validation with nine reject reasons, so one bad transaction doesn't stop the run.
- Control totals that compare the money moved with the balances written.
- Checkpoint and restart, tested by killing the process at every file operation.
- Output files that are verified and only given their final names if the job succeeds.
- A control file that detects a cut-off master.
- 142 automated tests, including the failure paths.

## Run

Needs GnuCOBOL (`sudo apt install gnucobol3` on Ubuntu or WSL).

```bash
./run.sh              # normal run
./run.sh restart      # resume a failed run from its last checkpoint
tests/run_tests.sh    # run all tests
```

Set `CKPT_INTERVAL` to change how many accounts are processed between checkpoints. The default is 1000, and 0 turns checkpoints off.

## Sample report

```
ACCOUNT     NAME                        TXNS             OPENING             CLOSING
1000000001  ALICE COHEN                    2            2,500.00            2,800.00
1000000002  BOB MIZRAHI                    2           12,000.00            9,030.00

CONTROL TOTALS
OPENING BALANCE                               27,550.50
DEPOSITS                                         625.50
INTEREST                                          50.00
WITHDRAWALS                                    3,200.00
EXPECTED CLOSING                              25,026.00
ACTUAL CLOSING                                25,026.00

IN BALANCE
```

## Rules

| Code | Reject reason |
|------|---------------|
| R1 | Account not on the master file |
| R2 | Transaction code is not DEP, WDR or INT |
| R3 | Amount is not numeric, or is zero |
| R4 | Withdrawal is more than the balance |
| R5 | Account is frozen or closed |
| R6 | Date is not a real calendar date |
| R7 | Interest on a non-savings account, or a balance of zero or less |
| R8 | New balance would be too large for the account record |
| R9 | Sequence number is not numeric |

Interest is 3.00% a year, posted monthly and rounded to the cent.

The closing balance is summed from the accounts as written, then compared with opening + deposits + interest - withdrawals. This catches lost or duplicated money, but not a wrong business rule, such as a wrong interest rate.

| Return code | Meaning |
|---|---|
| 0 | Clean run |
| 4 | Run succeeded, some transactions rejected |
| 12 | Out of balance, or the master doesn't match its control file |
| 16 | File error, invalid data, invalid restart, or incomplete output |

A blank transaction line, an over-long record or an empty master stops the job with return code 16.

## Measured results

Measured with GnuCOBOL 3.1.2 on Ubuntu 22.04. It has not been run on a mainframe, and power loss has not been tested.

| Test | Result |
|---|---|
| Automated tests | 142 passed |
| Random datasets against a separate Python recalculation | 400 of 400 identical |
| Killed at every file operation, then restarted | 8,838 restarts, all byte-identical to an unbroken run |
| Real `kill -9` on 20,000 accounts | 548 kills, 0 wrong results |
| Planted bugs caught by the tests | 84 of 95 |

## Roadmap

- [x] Checkpoint and restart after a failure
- [ ] Run on z/OS through IBM Z Xplore, with JCL and a VSAM master
- [ ] DB2 or CICS online balance inquiry
- [ ] Python or REST layer over the balances
