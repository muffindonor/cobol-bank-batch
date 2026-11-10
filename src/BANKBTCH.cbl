       IDENTIFICATION DIVISION.
       PROGRAM-ID. BANKBTCH.
      *---------------------------------------------------------------
      * Nightly account update, using a balanced-line (old master +
      * sorted transactions = new master) design.
      *
      * Input : ACCTIN   - old account master, sorted by account id
      *         TXNIN    - daily transactions, sorted by acct + seq
      * Output: ACCTOUT  - new account master
      *         REJOUT   - rejected transactions with reason codes
      *         RPTOUT   - account report and control totals
      * Both  : CKPTFILE - restart checkpoint
      * Option: CTLIN    - control record for the old master
      * Output: CTLOUT   - control record for the new master
      *
      * Parm  : RESTART on the command line resumes from CKPTFILE.
      * Env   : CKPT_INTERVAL = accounts between checkpoints
      *         (default 1000, 0 turns checkpoints off).
      *
      * Return codes:  0 clean run         4 run ok, rejects written
      *               12 out of balance   16 file or data error
      *---------------------------------------------------------------
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACCT-IN  ASSIGN TO "ACCTIN"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-ACCT-IN.
           SELECT TXN-IN   ASSIGN TO "TXNIN"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-TXN-IN.
           SELECT ACCT-OUT ASSIGN TO "ACCTOUT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-ACCT-OUT.
           SELECT REJ-OUT  ASSIGN TO "REJOUT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-REJ-OUT.
           SELECT RPT-OUT  ASSIGN TO "RPTOUT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-RPT-OUT.
           SELECT CKPT-FILE ASSIGN TO "CKPTFILE"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-CKPT.
           SELECT CKPT-NEW ASSIGN TO "CKPTNEW"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-CKPT-NEW.
           SELECT OPTIONAL CTL-IN ASSIGN TO "CTLIN"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-CTL-IN.
           SELECT CTL-OUT  ASSIGN TO "CTLOUT"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS FS-CTL-OUT.

       DATA DIVISION.
       FILE SECTION.
       FD  ACCT-IN.
           COPY ACCTREC.
       FD  TXN-IN.
           COPY TRANREC.
       FD  ACCT-OUT.
       01  ACCT-OUT-REC                PIC X(59).
       FD  REJ-OUT.
           COPY REJREC.
       FD  RPT-OUT.
       01  RPT-LINE                    PIC X(100).
       FD  CKPT-FILE.
       01  CKPT-IN-REC                 PIC X(165).
       FD  CKPT-NEW.
       01  CKPT-NEW-REC                PIC X(165).
       FD  CTL-IN.
       01  CTL-IN-REC                  PIC X(31).
       FD  CTL-OUT.
       01  CTL-OUT-REC                 PIC X(31).

       WORKING-STORAGE SECTION.
       01  WS-FILE-STATUSES.
           05  FS-ACCT-IN              PIC X(02).
           05  FS-TXN-IN               PIC X(02).
           05  FS-ACCT-OUT             PIC X(02).
           05  FS-REJ-OUT              PIC X(02).
           05  FS-RPT-OUT              PIC X(02).
           05  FS-CKPT                 PIC X(02).
           05  FS-CKPT-NEW             PIC X(02).
           05  FS-CTL-IN               PIC X(02).
           05  FS-CTL-OUT              PIC X(02).

       01  WS-RUN-CONTROL.
           05  WS-PARM                 PIC X(10) VALUE SPACES.
               88  WS-RESTART-RUN      VALUE "RESTART".
           05  WS-CKPT-ENV             PIC X(10) VALUE SPACES.
           05  WS-CKPT-INTERVAL        PIC 9(07) COMP VALUE 1000.
           05  WS-CKPT-PATH            PIC X(256) VALUE SPACES.
           05  WS-CKPT-NEW-PATH        PIC X(256) VALUE SPACES.
           05  WS-RENAME-RC            PIC S9(9) COMP-5 VALUE 0.
           05  WS-RESTART-KEY          PIC X(10) VALUE LOW-VALUES.
           05  WS-SKIP-LAST            PIC X(10) VALUE LOW-VALUES.
           05  WS-SKIP-MAST            PIC 9(12) COMP VALUE 0.
           05  WS-SKIP-TXN             PIC 9(12) COMP VALUE 0.
           05  WS-SKIP-OPEN            PIC S9(16)V99 COMP-3 VALUE 0.
           05  WS-CTL-STATE            PIC X(01) VALUE "N".
               88  WS-CTL-PRESENT      VALUE "Y".
           05  WS-CTL-RESULT           PIC X(01) VALUE "Y".
               88  WS-CTL-MATCHES      VALUE "Y".

       01  WS-KEYS.
           05  WS-MAST-KEY             PIC X(10) VALUE LOW-VALUES.
           05  WS-TXN-KEY              PIC X(10) VALUE LOW-VALUES.
           05  WS-PREV-MAST            PIC X(10) VALUE LOW-VALUES.
           05  WS-PREV-TXN             PIC X(16) VALUE LOW-VALUES.

       01  WS-MONEY.
           05  WS-CUR-BAL              PIC S9(11)V99 COMP-3 VALUE 0.
           05  WS-ACCT-OPEN            PIC S9(11)V99 COMP-3 VALUE 0.
           05  WS-TXN-AMT              PIC S9(11)V99 COMP-3 VALUE 0.
           05  WS-NEW-BAL              PIC S9(13)V99 COMP-3 VALUE 0.
      *    Largest balance ACCT-BALANCE can hold.
           05  WS-MAX-BAL              PIC S9(13)V99 COMP-3
                                       VALUE 99999999999.99.
      *    3.00% a year, posted monthly.
           05  WS-MONTHLY-RATE         PIC V9(4)     COMP-3 VALUE .0025.

       01  WS-TOTALS.
           05  TOT-OPEN                PIC S9(16)V99 COMP-3 VALUE 0.
           05  TOT-DEP                 PIC S9(16)V99 COMP-3 VALUE 0.
           05  TOT-WDR                 PIC S9(16)V99 COMP-3 VALUE 0.
           05  TOT-INT                 PIC S9(16)V99 COMP-3 VALUE 0.
           05  TOT-CLOSE               PIC S9(16)V99 COMP-3 VALUE 0.
           05  TOT-EXPECTED            PIC S9(16)V99 COMP-3 VALUE 0.

       01  WS-COUNTERS.
           05  CNT-MAST-READ           PIC 9(12) COMP VALUE 0.
           05  CNT-MAST-WRITTEN        PIC 9(12) COMP VALUE 0.
           05  CNT-TXN-READ            PIC 9(12) COMP VALUE 0.
           05  CNT-APPLIED             PIC 9(12) COMP VALUE 0.
           05  CNT-REJECTED            PIC 9(12) COMP VALUE 0.
           05  CNT-ACCT-TXNS           PIC 9(07) COMP VALUE 0.

       01  WS-REASON-CODE              PIC X(02) VALUE SPACES.
       01  WS-ABEND-MSG                PIC X(50) VALUE SPACES.
           COPY CTLREC.
           COPY CKPTREC.

       01  RPT-TITLE.
           05  FILLER                  PIC X(40)
               VALUE "BANKBTCH - NIGHTLY ACCOUNT UPDATE REPORT".

       01  RPT-HEADING.
           05  FILLER                  PIC X(12) VALUE "ACCOUNT".
           05  FILLER                  PIC X(25) VALUE "NAME".
           05  FILLER                  PIC X(07) VALUE "   TXNS".
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(18)
               VALUE "           OPENING".
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(18)
               VALUE "           CLOSING".

       01  RPT-DETAIL.
           05  RD-ID                   PIC X(10).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-NAME                 PIC X(25).
           05  RD-TXNS                 PIC ZZZZZZ9.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-OPEN                 PIC ---,---,---,--9.99.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-CLOSE                PIC ---,---,---,--9.99.

       01  RPT-AMT-LINE.
           05  RA-LABEL                PIC X(30).
           05  RA-VALUE                PIC --,---,---,---,---,--9.99.

       01  RPT-CNT-LINE.
           05  RC-LABEL                PIC X(40).
           05  RC-VALUE                PIC ZZZ,ZZZ,ZZZ,ZZ9.

       PROCEDURE DIVISION.
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS
               UNTIL WS-MAST-KEY = HIGH-VALUES
                 AND WS-TXN-KEY = HIGH-VALUES
           PERFORM 8000-FINISH
           STOP RUN.

       1000-INITIALIZE.
           ACCEPT WS-PARM FROM COMMAND-LINE
           ACCEPT WS-CKPT-ENV FROM ENVIRONMENT "CKPT_INTERVAL"
           IF WS-CKPT-ENV NOT = SPACES
               MOVE FUNCTION NUMVAL(WS-CKPT-ENV) TO WS-CKPT-INTERVAL
           END-IF
           ACCEPT WS-CKPT-PATH FROM ENVIRONMENT "DD_CKPTFILE"
           IF WS-CKPT-PATH = SPACES
               MOVE "CKPTFILE" TO WS-CKPT-PATH
           END-IF
           ACCEPT WS-CKPT-NEW-PATH FROM ENVIRONMENT "DD_CKPTNEW"
           IF WS-CKPT-NEW-PATH = SPACES
               MOVE "CKPTNEW" TO WS-CKPT-NEW-PATH
           END-IF
           OPEN INPUT ACCT-IN
           IF FS-ACCT-IN NOT = "00"
               MOVE "CANNOT OPEN ACCTIN" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           OPEN INPUT TXN-IN
           IF FS-TXN-IN NOT = "00"
               MOVE "CANNOT OPEN TXNIN" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           PERFORM 1050-READ-CONTROL
           IF WS-RESTART-RUN
               PERFORM 1200-RESTORE-CHECKPOINT
               PERFORM 1100-REOPEN-OUTPUTS
               PERFORM 1300-REPOSITION-INPUTS
           ELSE
               OPEN OUTPUT ACCT-OUT REJ-OUT RPT-OUT
               PERFORM 1110-CHECK-OUTPUTS-OPEN
               MOVE RPT-TITLE TO RPT-LINE
               PERFORM 7000-WRITE-REPORT
               MOVE SPACES TO RPT-LINE
               PERFORM 7000-WRITE-REPORT
               MOVE RPT-HEADING TO RPT-LINE
               PERFORM 7000-WRITE-REPORT
               PERFORM 2100-READ-MASTER
               IF WS-MAST-KEY = HIGH-VALUES
                   MOVE "ACCTIN IS EMPTY" TO WS-ABEND-MSG
                   PERFORM 9000-ABEND
               END-IF
               PERFORM 2200-READ-TXN
           END-IF.

      *---------------------------------------------------------------
      * The control record is optional, but one that exists must be
      * valid. Status 05 means an OPTIONAL file is not there.
      *---------------------------------------------------------------
       1050-READ-CONTROL.
           OPEN INPUT CTL-IN
           EVALUATE FS-CTL-IN
               WHEN "05"
                   CONTINUE
               WHEN "00"
                   READ CTL-IN INTO CTL-REC
                   END-READ
                   IF FS-CTL-IN NOT = "00"
                      OR CTL-COUNT NOT NUMERIC
                      OR CTL-TOTAL NOT NUMERIC
                       MOVE "CONTROL FILE IS INVALID" TO WS-ABEND-MSG
                       PERFORM 9000-ABEND
                   END-IF
                   MOVE "Y" TO WS-CTL-STATE
               WHEN OTHER
                   MOVE "CANNOT OPEN CTLIN" TO WS-ABEND-MSG
                   PERFORM 9000-ABEND
           END-EVALUATE
           CLOSE CTL-IN.

       1100-REOPEN-OUTPUTS.
           OPEN EXTEND ACCT-OUT REJ-OUT RPT-OUT
           PERFORM 1110-CHECK-OUTPUTS-OPEN.

       1110-CHECK-OUTPUTS-OPEN.
           IF FS-ACCT-OUT NOT = "00"
              OR FS-REJ-OUT NOT = "00"
              OR FS-RPT-OUT NOT = "00"
               MOVE "CANNOT OPEN OUTPUT FILES" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       1200-RESTORE-CHECKPOINT.
           OPEN INPUT CKPT-FILE
           IF FS-CKPT NOT = "00"
               MOVE "CANNOT OPEN CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           READ CKPT-FILE INTO CKPT-REC
           END-READ
           IF FS-CKPT NOT = "00"
              OR CKPT-MAST-READ NOT NUMERIC
              OR CKPT-MAST-WRITTEN NOT NUMERIC
              OR CKPT-TXN-READ NOT NUMERIC
              OR CKPT-APPLIED NOT NUMERIC
              OR CKPT-REJECTED NOT NUMERIC
              OR CKPT-TOT-OPEN NOT NUMERIC
              OR CKPT-TOT-DEP NOT NUMERIC
              OR CKPT-TOT-WDR NOT NUMERIC
              OR CKPT-TOT-INT NOT NUMERIC
              OR CKPT-TOT-CLOSE NOT NUMERIC
               MOVE "CHECKPOINT IS INVALID" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           MOVE CKPT-LAST-KEY     TO WS-RESTART-KEY WS-PREV-MAST
           MOVE CKPT-MAST-READ    TO CNT-MAST-READ
           MOVE CKPT-MAST-WRITTEN TO CNT-MAST-WRITTEN
           MOVE CKPT-TXN-READ     TO CNT-TXN-READ
           MOVE CKPT-APPLIED      TO CNT-APPLIED
           MOVE CKPT-REJECTED     TO CNT-REJECTED
           MOVE CKPT-TOT-OPEN     TO TOT-OPEN
           MOVE CKPT-TOT-DEP      TO TOT-DEP
           MOVE CKPT-TOT-WDR      TO TOT-WDR
           MOVE CKPT-TOT-INT      TO TOT-INT
           MOVE CKPT-TOT-CLOSE    TO TOT-CLOSE
           CLOSE CKPT-FILE
           DISPLAY "BANKBTCH: RESTARTED AFTER ACCOUNT " WS-RESTART-KEY.

      *---------------------------------------------------------------
      * A checkpoint is taken at an account boundary, so everything
      * up to and including the restart key has been fully processed.
      * What is skipped must add up to what the checkpoint recorded,
      * otherwise these are not the inputs of the failed run.
      *---------------------------------------------------------------
       1300-REPOSITION-INPUTS.
           PERFORM 1310-SKIP-MASTER WITH TEST AFTER
               UNTIL FS-ACCT-IN = "10"
                  OR ACCT-ID > WS-RESTART-KEY
           IF WS-SKIP-MAST NOT = CNT-MAST-READ
              OR WS-SKIP-LAST NOT = WS-RESTART-KEY
              OR WS-SKIP-OPEN NOT = TOT-OPEN
               MOVE "ACCTIN DOES NOT MATCH CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF FS-ACCT-IN = "10"
               MOVE HIGH-VALUES TO WS-MAST-KEY
           ELSE
               PERFORM 2110-LOAD-ACCOUNT
           END-IF
           PERFORM 1320-SKIP-TXN WITH TEST AFTER
               UNTIL FS-TXN-IN = "10"
                  OR TXN-ACCT-ID > WS-RESTART-KEY
           IF WS-SKIP-TXN NOT = CNT-TXN-READ
               MOVE "TXNIN DOES NOT MATCH CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF FS-TXN-IN = "10"
               MOVE HIGH-VALUES TO WS-TXN-KEY
           ELSE
               PERFORM 2210-LOAD-TXN
           END-IF.

       1310-SKIP-MASTER.
           READ ACCT-IN
           END-READ
           PERFORM 2190-CHECK-MASTER-READ
           IF FS-ACCT-IN = "00" AND ACCT-ID NOT > WS-RESTART-KEY
               IF ACCT-BALANCE IS NOT NUMERIC
                   MOVE "ACCTIN BALANCE NOT NUMERIC" TO WS-ABEND-MSG
                   PERFORM 9000-ABEND
               END-IF
               ADD 1 TO WS-SKIP-MAST
               ADD ACCT-BALANCE TO WS-SKIP-OPEN
               MOVE ACCT-ID TO WS-SKIP-LAST
           END-IF.

       1320-SKIP-TXN.
           READ TXN-IN
           END-READ
           PERFORM 2290-CHECK-TXN-READ
           IF FS-TXN-IN = "00" AND TXN-ACCT-ID NOT > WS-RESTART-KEY
               ADD 1 TO WS-SKIP-TXN
           END-IF.

      *---------------------------------------------------------------
      * Balanced line: always act on the lower of the two keys.
      *---------------------------------------------------------------
       2000-PROCESS.
           EVALUATE TRUE
               WHEN WS-TXN-KEY < WS-MAST-KEY
                   MOVE "R1" TO WS-REASON-CODE
                   PERFORM 4000-REJECT
                   PERFORM 2200-READ-TXN
               WHEN WS-TXN-KEY = WS-MAST-KEY
                   PERFORM 3000-APPLY-TXN
                   PERFORM 2200-READ-TXN
               WHEN OTHER
                   PERFORM 5000-WRITE-ACCOUNT
                   PERFORM 2100-READ-MASTER
           END-EVALUATE.

       2100-READ-MASTER.
           READ ACCT-IN
               AT END
                   MOVE HIGH-VALUES TO WS-MAST-KEY
               NOT AT END
                   PERFORM 2110-LOAD-ACCOUNT
           END-READ
           PERFORM 2190-CHECK-MASTER-READ.

       2110-LOAD-ACCOUNT.
           IF ACCT-ID NOT > WS-PREV-MAST
               MOVE "ACCTIN OUT OF SEQUENCE OR DUPLICATE"
                   TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF ACCT-BALANCE IS NOT NUMERIC
               MOVE "ACCTIN BALANCE NOT NUMERIC" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF NOT (ACCT-CHECKING OR ACCT-SAVINGS)
              OR NOT (ACCT-ACTIVE OR ACCT-FROZEN OR ACCT-CLOSED)
               MOVE "ACCTIN INVALID TYPE OR STATUS" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF ACCT-LAST-TXN-DATE IS NOT NUMERIC
               MOVE "ACCTIN INVALID DATE" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF FUNCTION TEST-DATE-YYYYMMDD(ACCT-LAST-TXN-DATE) NOT = ZERO
               MOVE "ACCTIN INVALID DATE" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           ADD 1 TO CNT-MAST-READ
           MOVE ACCT-ID TO WS-MAST-KEY WS-PREV-MAST
           MOVE ACCT-BALANCE TO WS-CUR-BAL WS-ACCT-OPEN
           ADD WS-CUR-BAL TO TOT-OPEN
               ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
           END-ADD
           MOVE ZERO TO CNT-ACCT-TXNS.

       2190-CHECK-MASTER-READ.
           IF FS-ACCT-IN NOT = "00" AND FS-ACCT-IN NOT = "10"
               MOVE "READ ERROR ON ACCTIN" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       2200-READ-TXN.
           READ TXN-IN
               AT END
                   MOVE HIGH-VALUES TO WS-TXN-KEY
               NOT AT END
                   PERFORM 2210-LOAD-TXN
           END-READ
           PERFORM 2290-CHECK-TXN-READ.

       2210-LOAD-TXN.
           IF TXN-REC = SPACES
               MOVE "TXNIN CONTAINS A BLANK RECORD" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           IF TXN-KEY NOT > WS-PREV-TXN
               MOVE "TXNIN OUT OF SEQUENCE OR DUPLICATE"
                   TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           ADD 1 TO CNT-TXN-READ
           MOVE TXN-ACCT-ID TO WS-TXN-KEY
           MOVE TXN-KEY TO WS-PREV-TXN.

       2290-CHECK-TXN-READ.
           IF FS-TXN-IN NOT = "00" AND FS-TXN-IN NOT = "10"
               MOVE "READ ERROR ON TXNIN" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       3000-APPLY-TXN.
           MOVE SPACES TO WS-REASON-CODE
           PERFORM 3100-VALIDATE-TXN
           IF WS-REASON-CODE = SPACES
               PERFORM 3150-CALC-NEW-BALANCE
           END-IF
           IF WS-REASON-CODE = SPACES
               PERFORM 3200-POST-TXN
           ELSE
               PERFORM 4000-REJECT
           END-IF.

       3100-VALIDATE-TXN.
           EVALUATE TRUE
               WHEN NOT TXN-VALID-CODE
                   MOVE "R2" TO WS-REASON-CODE
               WHEN TXN-SEQ IS NOT NUMERIC
                   MOVE "R9" TO WS-REASON-CODE
               WHEN NOT TXN-INTEREST AND TXN-AMOUNT IS NOT NUMERIC
                   MOVE "R3" TO WS-REASON-CODE
               WHEN NOT TXN-INTEREST AND TXN-AMOUNT = ZERO
                   MOVE "R3" TO WS-REASON-CODE
               WHEN TXN-DATE IS NOT NUMERIC
                   MOVE "R6" TO WS-REASON-CODE
               WHEN FUNCTION TEST-DATE-YYYYMMDD(TXN-DATE) NOT = ZERO
                   MOVE "R6" TO WS-REASON-CODE
               WHEN NOT ACCT-ACTIVE
                   MOVE "R5" TO WS-REASON-CODE
               WHEN TXN-INTEREST AND NOT ACCT-SAVINGS
                   MOVE "R7" TO WS-REASON-CODE
               WHEN TXN-INTEREST AND WS-CUR-BAL NOT > ZERO
                   MOVE "R7" TO WS-REASON-CODE
               WHEN TXN-WITHDRAWAL AND TXN-AMOUNT > WS-CUR-BAL
                   MOVE "R4" TO WS-REASON-CODE
           END-EVALUATE.

      *---------------------------------------------------------------
      * WS-NEW-BAL is wider than the balance field, so an overflow is
      * rejected here rather than silently cutting off high digits.
      *---------------------------------------------------------------
       3150-CALC-NEW-BALANCE.
           EVALUATE TRUE
               WHEN TXN-DEPOSIT
                   MOVE TXN-AMOUNT TO WS-TXN-AMT
                   COMPUTE WS-NEW-BAL = WS-CUR-BAL + WS-TXN-AMT
               WHEN TXN-WITHDRAWAL
                   MOVE TXN-AMOUNT TO WS-TXN-AMT
                   COMPUTE WS-NEW-BAL = WS-CUR-BAL - WS-TXN-AMT
               WHEN TXN-INTEREST
                   COMPUTE WS-TXN-AMT ROUNDED =
                       WS-CUR-BAL * WS-MONTHLY-RATE
                   COMPUTE WS-NEW-BAL = WS-CUR-BAL + WS-TXN-AMT
           END-EVALUATE
           IF WS-NEW-BAL > WS-MAX-BAL
               MOVE "R8" TO WS-REASON-CODE
           END-IF.

       3200-POST-TXN.
           MOVE WS-NEW-BAL TO WS-CUR-BAL
           EVALUATE TRUE
               WHEN TXN-DEPOSIT
                   ADD WS-TXN-AMT TO TOT-DEP
                       ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
                   END-ADD
               WHEN TXN-WITHDRAWAL
                   ADD WS-TXN-AMT TO TOT-WDR
                       ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
                   END-ADD
               WHEN TXN-INTEREST
                   ADD WS-TXN-AMT TO TOT-INT
                       ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
                   END-ADD
           END-EVALUATE
           MOVE TXN-DATE TO ACCT-LAST-TXN-DATE
           ADD 1 TO CNT-APPLIED CNT-ACCT-TXNS.

       4000-REJECT.
           MOVE SPACES TO REJ-REC
           MOVE TXN-REC TO REJ-TXN
           MOVE WS-REASON-CODE TO REJ-CODE
           EVALUATE WS-REASON-CODE
               WHEN "R1" MOVE "UNKNOWN ACCOUNT" TO REJ-TEXT
               WHEN "R2" MOVE "INVALID TRANSACTION CODE" TO REJ-TEXT
               WHEN "R3" MOVE "INVALID AMOUNT" TO REJ-TEXT
               WHEN "R4" MOVE "INSUFFICIENT FUNDS" TO REJ-TEXT
               WHEN "R5" MOVE "ACCOUNT NOT ACTIVE" TO REJ-TEXT
               WHEN "R6" MOVE "INVALID DATE" TO REJ-TEXT
               WHEN "R7" MOVE "INTEREST NOT ALLOWED" TO REJ-TEXT
               WHEN "R8" MOVE "BALANCE LIMIT EXCEEDED" TO REJ-TEXT
               WHEN "R9" MOVE "INVALID SEQUENCE NUMBER" TO REJ-TEXT
           END-EVALUATE
           WRITE REJ-REC
           IF FS-REJ-OUT NOT = "00"
               MOVE "WRITE ERROR ON REJOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           ADD 1 TO CNT-REJECTED.

       5000-WRITE-ACCOUNT.
           MOVE WS-CUR-BAL TO ACCT-BALANCE
           WRITE ACCT-OUT-REC FROM ACCT-REC
           IF FS-ACCT-OUT NOT = "00"
               MOVE "WRITE ERROR ON ACCTOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           ADD 1 TO CNT-MAST-WRITTEN
           ADD WS-CUR-BAL TO TOT-CLOSE
               ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
           END-ADD
           MOVE ACCT-ID       TO RD-ID
           MOVE ACCT-NAME     TO RD-NAME
           MOVE CNT-ACCT-TXNS TO RD-TXNS
           MOVE WS-ACCT-OPEN  TO RD-OPEN
           MOVE WS-CUR-BAL    TO RD-CLOSE
           MOVE RPT-DETAIL    TO RPT-LINE
           PERFORM 7000-WRITE-REPORT
           IF WS-CKPT-INTERVAL > ZERO
              AND FUNCTION MOD(CNT-MAST-WRITTEN, WS-CKPT-INTERVAL)
                  = ZERO
               PERFORM 6000-TAKE-CHECKPOINT
           END-IF.

      *---------------------------------------------------------------
      * Closing and reopening hands the buffered output to the
      * operating system, so it survives this process being killed.
      * The next transaction has already been read, so it is taken
      * back out of the saved count and recounted after a restart.
      * The checkpoint is written to a new file and renamed over the
      * old one, so a crash here still leaves the last good one.
      *---------------------------------------------------------------
       6000-TAKE-CHECKPOINT.
           PERFORM 6100-CLOSE-OUTPUTS
           PERFORM 1100-REOPEN-OUTPUTS
           OPEN OUTPUT CKPT-NEW
           IF FS-CKPT-NEW NOT = "00"
               MOVE "CANNOT WRITE CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           MOVE WS-MAST-KEY      TO CKPT-LAST-KEY
           MOVE CNT-MAST-READ    TO CKPT-MAST-READ
           MOVE CNT-MAST-WRITTEN TO CKPT-MAST-WRITTEN
           MOVE CNT-TXN-READ     TO CKPT-TXN-READ
           IF WS-TXN-KEY NOT = HIGH-VALUES
               SUBTRACT 1 FROM CKPT-TXN-READ
           END-IF
           MOVE CNT-APPLIED      TO CKPT-APPLIED
           MOVE CNT-REJECTED     TO CKPT-REJECTED
           MOVE TOT-OPEN         TO CKPT-TOT-OPEN
           MOVE TOT-DEP          TO CKPT-TOT-DEP
           MOVE TOT-WDR          TO CKPT-TOT-WDR
           MOVE TOT-INT          TO CKPT-TOT-INT
           MOVE TOT-CLOSE        TO CKPT-TOT-CLOSE
           WRITE CKPT-NEW-REC FROM CKPT-REC
           IF FS-CKPT-NEW NOT = "00"
               MOVE "CANNOT WRITE CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           CLOSE CKPT-NEW
           IF FS-CKPT-NEW NOT = "00"
               MOVE "CANNOT WRITE CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           CALL "CBL_RENAME_FILE" USING WS-CKPT-NEW-PATH WS-CKPT-PATH
               RETURNING WS-RENAME-RC
           END-CALL
           IF WS-RENAME-RC NOT = ZERO
               MOVE "CANNOT REPLACE CHECKPOINT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       6100-CLOSE-OUTPUTS.
           CLOSE ACCT-OUT REJ-OUT RPT-OUT
           IF FS-ACCT-OUT NOT = "00"
              OR FS-REJ-OUT NOT = "00"
              OR FS-RPT-OUT NOT = "00"
               MOVE "CLOSE ERROR ON OUTPUT FILES" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       7000-WRITE-REPORT.
           WRITE RPT-LINE
           IF FS-RPT-OUT NOT = "00"
               MOVE "WRITE ERROR ON RPTOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       7100-PUT-AMOUNT.
           MOVE RPT-AMT-LINE TO RPT-LINE
           PERFORM 7000-WRITE-REPORT.

       7200-PUT-COUNT.
           MOVE RPT-CNT-LINE TO RPT-LINE
           PERFORM 7000-WRITE-REPORT.

      *---------------------------------------------------------------
      * TOT-CLOSE is summed from the accounts as written, so it is an
      * independent check on the movement totals.
      *---------------------------------------------------------------
       8000-FINISH.
           COMPUTE TOT-EXPECTED = TOT-OPEN + TOT-DEP + TOT-INT - TOT-WDR
               ON SIZE ERROR PERFORM 9100-TOTAL-OVERFLOW
           END-COMPUTE
           IF WS-CTL-PRESENT
              AND (CTL-COUNT NOT = CNT-MAST-READ
                   OR CTL-TOTAL NOT = TOT-OPEN)
               MOVE "N" TO WS-CTL-RESULT
               DISPLAY "BANKBTCH: MASTER DOES NOT MATCH CONTROL FILE"
           END-IF
           MOVE SPACES TO RPT-LINE
           PERFORM 7000-WRITE-REPORT
           MOVE "CONTROL TOTALS" TO RPT-LINE
           PERFORM 7000-WRITE-REPORT

           MOVE "OPENING BALANCE"  TO RA-LABEL
           MOVE TOT-OPEN           TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT
           MOVE "DEPOSITS"         TO RA-LABEL
           MOVE TOT-DEP            TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT
           MOVE "INTEREST"         TO RA-LABEL
           MOVE TOT-INT            TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT
           MOVE "WITHDRAWALS"      TO RA-LABEL
           MOVE TOT-WDR            TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT
           MOVE "EXPECTED CLOSING" TO RA-LABEL
           MOVE TOT-EXPECTED       TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT
           MOVE "ACTUAL CLOSING"   TO RA-LABEL
           MOVE TOT-CLOSE          TO RA-VALUE
           PERFORM 7100-PUT-AMOUNT

           MOVE "ACCOUNTS READ"          TO RC-LABEL
           MOVE CNT-MAST-READ            TO RC-VALUE
           PERFORM 7200-PUT-COUNT
           MOVE "ACCOUNTS WRITTEN"       TO RC-LABEL
           MOVE CNT-MAST-WRITTEN         TO RC-VALUE
           PERFORM 7200-PUT-COUNT
           MOVE "TRANSACTIONS READ"      TO RC-LABEL
           MOVE CNT-TXN-READ             TO RC-VALUE
           PERFORM 7200-PUT-COUNT
           MOVE "TRANSACTIONS APPLIED"   TO RC-LABEL
           MOVE CNT-APPLIED              TO RC-VALUE
           PERFORM 7200-PUT-COUNT
           MOVE "TRANSACTIONS REJECTED"  TO RC-LABEL
           MOVE CNT-REJECTED             TO RC-VALUE
           PERFORM 7200-PUT-COUNT

           MOVE SPACES TO RPT-LINE
           PERFORM 7000-WRITE-REPORT
           IF TOT-EXPECTED NOT = TOT-CLOSE
              OR CNT-TXN-READ NOT = CNT-APPLIED + CNT-REJECTED
              OR CNT-MAST-READ NOT = CNT-MAST-WRITTEN
              OR NOT WS-CTL-MATCHES
               MOVE "*** OUT OF BALANCE ***" TO RPT-LINE
               MOVE 12 TO RETURN-CODE
           ELSE
               MOVE "IN BALANCE" TO RPT-LINE
               IF CNT-REJECTED > ZERO
                   MOVE 4 TO RETURN-CODE
               END-IF
           END-IF
           DISPLAY "BANKBTCH: " RPT-LINE(1:30)
           PERFORM 7000-WRITE-REPORT
           PERFORM 8100-WRITE-CONTROL
           PERFORM 6100-CLOSE-OUTPUTS
           CLOSE ACCT-IN TXN-IN.

       8100-WRITE-CONTROL.
           OPEN OUTPUT CTL-OUT
           IF FS-CTL-OUT NOT = "00"
               MOVE "CANNOT OPEN CTLOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           MOVE CNT-MAST-WRITTEN TO CTL-COUNT
           MOVE TOT-CLOSE        TO CTL-TOTAL
           WRITE CTL-OUT-REC FROM CTL-REC
           IF FS-CTL-OUT NOT = "00"
               MOVE "WRITE ERROR ON CTLOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF
           CLOSE CTL-OUT
           IF FS-CTL-OUT NOT = "00"
               MOVE "CLOSE ERROR ON CTLOUT" TO WS-ABEND-MSG
               PERFORM 9000-ABEND
           END-IF.

       9000-ABEND.
           DISPLAY "BANKBTCH ABEND: " WS-ABEND-MSG
           MOVE 16 TO RETURN-CODE
           STOP RUN.

       9100-TOTAL-OVERFLOW.
           MOVE "CONTROL TOTAL OVERFLOW" TO WS-ABEND-MSG
           PERFORM 9000-ABEND.
