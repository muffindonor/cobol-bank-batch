      *---------------------------------------------------------------
      * CTLREC - master file control record (31 bytes)
      * Travels beside a master file and states how many accounts it
      * holds and what they add up to, so a cut-off file is detected.
      *---------------------------------------------------------------
       01  CTL-REC.
           05  CTL-COUNT               PIC 9(12).
           05  CTL-TOTAL               PIC S9(16)V99
                                       SIGN IS LEADING SEPARATE.
