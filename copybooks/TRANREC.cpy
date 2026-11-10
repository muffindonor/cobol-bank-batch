      *---------------------------------------------------------------
      * TRANREC - daily transaction record (38 bytes)
      * Transaction file is sorted ascending by TXN-KEY.
      * TXN-AMOUNT is ignored for INT, which is calculated.
      *---------------------------------------------------------------
       01  TXN-REC.
           05  TXN-KEY.
               10  TXN-ACCT-ID         PIC X(10).
               10  TXN-SEQ             PIC 9(06).
           05  TXN-CODE                PIC X(03).
               88  TXN-DEPOSIT         VALUE "DEP".
               88  TXN-WITHDRAWAL      VALUE "WDR".
               88  TXN-INTEREST        VALUE "INT".
               88  TXN-VALID-CODE      VALUE "DEP" "WDR" "INT".
           05  TXN-AMOUNT              PIC 9(09)V99.
           05  TXN-DATE                PIC 9(08).
