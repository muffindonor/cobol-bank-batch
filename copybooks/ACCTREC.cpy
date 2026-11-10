      *---------------------------------------------------------------
      * ACCTREC - customer account master record (59 bytes)
      * Master file is sorted ascending by ACCT-ID, with no duplicates.
      *---------------------------------------------------------------
       01  ACCT-REC.
           05  ACCT-ID                 PIC X(10).
           05  ACCT-NAME               PIC X(25).
           05  ACCT-TYPE               PIC X(01).
               88  ACCT-CHECKING       VALUE "C".
               88  ACCT-SAVINGS        VALUE "S".
           05  ACCT-STATUS             PIC X(01).
               88  ACCT-ACTIVE         VALUE "A".
               88  ACCT-FROZEN         VALUE "F".
               88  ACCT-CLOSED         VALUE "C".
           05  ACCT-BALANCE            PIC S9(11)V99
                                       SIGN IS LEADING SEPARATE.
           05  ACCT-LAST-TXN-DATE      PIC 9(08).
