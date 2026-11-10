      *---------------------------------------------------------------
      * CKPTREC - restart checkpoint record (165 bytes)
      * Holds everything needed to resume after the last account
      * written. run.sh reads MAST-WRITTEN (columns 23-34) and
      * REJECTED (columns 59-70) to trim the output files on restart.
      *---------------------------------------------------------------
       01  CKPT-REC.
           05  CKPT-LAST-KEY           PIC X(10).
           05  CKPT-MAST-READ          PIC 9(12).
           05  CKPT-MAST-WRITTEN       PIC 9(12).
           05  CKPT-TXN-READ           PIC 9(12).
           05  CKPT-APPLIED            PIC 9(12).
           05  CKPT-REJECTED           PIC 9(12).
           05  CKPT-TOT-OPEN           PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
           05  CKPT-TOT-DEP            PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
           05  CKPT-TOT-WDR            PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
           05  CKPT-TOT-INT            PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
           05  CKPT-TOT-CLOSE          PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
