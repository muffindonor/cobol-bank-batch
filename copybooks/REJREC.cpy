      *---------------------------------------------------------------
      * REJREC - rejected transaction record (72 bytes)
      * Holds the original transaction plus the reason it failed.
      *---------------------------------------------------------------
       01  REJ-REC.
           05  REJ-TXN                 PIC X(38).
           05  FILLER                  PIC X(01).
           05  REJ-CODE                PIC X(02).
           05  FILLER                  PIC X(01).
           05  REJ-TEXT                PIC X(30).
