#!/usr/bin/env bash
# Regression tests for BANKBTCH. Each case runs the real job and checks
# its return code and output files.
set -uo pipefail
cd "$(dirname "$0")/.."

WORK=build/test
rm -rf "$WORK"
mkdir -p "$WORK"

if ! cobc -x -fixed -Wall -I copybooks -o build/bankbtch src/BANKBTCH.cbl; then
    echo "FAILED: program does not compile"
    exit 1
fi

passed=0
failed=0

ok() {
    passed=$((passed + 1))
    echo "  pass  $1"
}

bad() {
    failed=$((failed + 1))
    echo "  FAIL  $1"
}

expect_eq() { # description expected actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

expect_same_file() { # description expected-file actual-file
    if diff -q "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}

expect_no_file() { # description file
    if [ ! -e "$2" ]; then ok "$1"; else bad "$1"; fi
}

expect_file() { # description file
    if [ -e "$2" ]; then ok "$1"; else bad "$1"; fi
}

# job <case> <master> <trans> [run.sh argument]; sets rc and out
job() {
    out=$WORK/run/$1
    mkdir -p "$out"
    MASTER_IN=$2 TRANS_IN=$3 OUTDIR=$out NO_BUILD=1 ./run.sh "${4:-}" >"$out/log" 2>&1
    rc=$?
}

# job with a 1 KB file size limit, to imitate a full disk
job_full_disk() { # case master trans
    (
        trap '' XFSZ
        ulimit -f 1
        job "$1" "$2" "$3"
        echo "$rc" >"$WORK/$1.rc"
    )
    out=$WORK/run/$1
    rc=$(cat "$WORK/$1.rc")
}

# direct <case> [NAME=value ...] runs the program itself, without run.sh
direct() {
    local dir=$WORK/run/$1
    shift
    mkdir -p "$dir"
    env DD_ACCTIN=$GOOD_MASTER DD_TXNIN=$GOOD_TRANS DD_CTLIN=$dir/none \
        DD_ACCTOUT=$dir/a DD_REJOUT=$dir/r DD_RPTOUT=$dir/p \
        DD_CTLOUT=$dir/c DD_CKPTFILE=$dir/k DD_CKPTNEW=$dir/n CKPT_INTERVAL=1000 \
        "$@" build/bankbtch ${PARM:-} >"$dir.log" 2>&1
    rc=$?
}

master_line() { # id type status balance [date]
    printf '%-10s%-25s%s%s%s%s\n' "$1" "TEST CUSTOMER" "$2" "$3" "$4" "${5:-20261101}"
}

txn_line() { # id seq code amount [date]
    printf '%-10s%s%s%s%s\n' "$1" "$2" "$3" "$4" "${5:-20261108}"
}

many_accounts() { # count balance
    awk -v n="$1" -v b="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%010d%-25sCA%s20261101\n", i, "TEST CUSTOMER", b }'
}

balance_of() { # master-file account-id
    grep "^$2" "$1" | cut -c38-51
}

reasons_in() {
    cut -c40-41 "$1" | tr '\n' ' ' | sed 's/ $//'
}

# mutant <name> <sed-expression>: builds a copy with a deliberate defect
mutant() {
    sed "$2" src/BANKBTCH.cbl >"$WORK/$1.cbl"
    if cmp -s src/BANKBTCH.cbl "$WORK/$1.cbl"; then
        bad "defect could not be injected: $1"
        return 1
    fi
    if ! cobc -x -fixed -I copybooks -o "$WORK/$1.bin" "$WORK/$1.cbl"; then
        bad "defective copy did not compile: $1"
        return 1
    fi
}

GOOD_MASTER=data/ACCTMAST.DAT
GOOD_TRANS=data/TRANS.DAT
A=1000000001
B=1000000002
NOWHERE=/nonexistent-directory/file
: >"$WORK/empty"

echo "Sample run"
job sample "$GOOD_MASTER" "$GOOD_TRANS"
expect_eq "return code is 4" 4 "$rc"
expect_same_file "new master matches baseline" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
expect_same_file "rejects match baseline" tests/expected/REJECTS.DAT "$out/REJECTS.DAT"
expect_same_file "report matches baseline" tests/expected/REPORT.TXT "$out/REPORT.TXT"
expect_eq "control record states count and closing total" "000000000007+000000000002502600" "$(cat "$out/ACCTMAST.NEW.CTL")"
expect_no_file "temporary master removed" "$out/ACCTMAST.TMP"
expect_no_file "temporary report removed" "$out/REPORT.TMP"
job sample "$GOOD_MASTER" "$GOOD_TRANS"
expect_same_file "running again replaces old rejects" tests/expected/REJECTS.DAT "$out/REJECTS.DAT"
expect_eq "new master has the latest date" 20261108 "$(grep ^$A "$out/ACCTMAST.NEW" | cut -c52-59)"

echo "Clean run"
master_line $A C A +0000000100000 >"$WORK/m"
txn_line $A 000001 DEP 00000010000 >"$WORK/t"
job clean "$WORK/m" "$WORK/t"
expect_eq "return code is 0" 0 "$rc"
expect_eq "deposit posted" +0000000110000 "$(balance_of "$out/ACCTMAST.NEW" $A)"

echo "Empty files"
job no_trans "$WORK/m" "$WORK/empty"
expect_eq "no transactions gives return code 0" 0 "$rc"
expect_same_file "master unchanged" "$WORK/m" "$out/ACCTMAST.NEW"
job no_master "$WORK/empty" "$WORK/t"
expect_eq "empty master gives return code 16" 16 "$rc"
expect_no_file "no new master from an empty master" "$out/ACCTMAST.NEW"
job dir_master "$WORK" "$WORK/t"
expect_eq "directory as master gives 16" 16 "$rc"
job dir_trans "$WORK/m" "$WORK"
expect_eq "directory as transactions gives 16" 16 "$rc"

echo "Boundaries and rounding"
txn_line $A 000001 WDR 00000100000 >"$WORK/t"
job exact "$WORK/m" "$WORK/t"
expect_eq "withdrawing the exact balance is allowed" +0000000000000 "$(balance_of "$out/ACCTMAST.NEW" $A)"
txn_line $A 000001 WDR 00000100001 >"$WORK/t"
job cent_over "$WORK/m" "$WORK/t"
expect_eq "one cent over the balance is rejected" R4 "$(reasons_in "$out/REJECTS.DAT")"
master_line $A S A +0000000000200 >"$WORK/m2"
txn_line $A 000001 INT 00000000000 >"$WORK/t"
job rounding "$WORK/m2" "$WORK/t"
expect_eq "half a cent of interest rounds up" +0000000000201 "$(balance_of "$out/ACCTMAST.NEW" $A)"
master_line $A S A +0000000100000 >"$WORK/m2"
{ txn_line $A 000001 DEP 00000100000; txn_line $A 000002 INT 00000000000; } >"$WORK/t"
job current_balance "$WORK/m2" "$WORK/t"
expect_eq "interest uses the current balance" +0000000200500 "$(balance_of "$out/ACCTMAST.NEW" $A)"
master_line $A C A +9999999999900 >"$WORK/m3"
txn_line $A 000001 DEP 00000000099 >"$WORK/t"
job at_limit "$WORK/m3" "$WORK/t"
expect_eq "reaching the balance limit exactly is allowed" +9999999999999 "$(balance_of "$out/ACCTMAST.NEW" $A)"

echo "Rejected transactions"
reject_case() { # description expected-reason case type status balance code amount [date] [seq]
    master_line $A "$4" "$5" "$6" >"$WORK/rm"
    txn_line $A "${10:-000001}" "$7" "$8" "${9:-20261108}" >"$WORK/rt"
    job "$3" "$WORK/rm" "$WORK/rt"
    expect_eq "$1" "$2" "$(reasons_in "$out/REJECTS.DAT")"
}
reject_case "impossible date is rejected" R6 bad_date C A +0000000100000 DEP 00000010000 20261399
reject_case "30 February is rejected" R6 feb30 C A +0000000100000 DEP 00000010000 20260230
reject_case "non-numeric sequence is rejected" R9 bad_seq C A +0000000100000 DEP 00000010000 20261108 00A001
reject_case "zero amount is rejected" R3 zero_amt C A +0000000100000 DEP 00000000000
reject_case "frozen account is rejected" R5 frozen C F +0000000100000 DEP 00000010000
reject_case "closed account is rejected" R5 closed C C +0000000100000 DEP 00000010000
reject_case "a bad code is reported before account status" R2 order S F +0000000100000 XFR 00000010000
reject_case "interest on checking is rejected" R7 int_checking C A +0000000100000 INT 00000000000
reject_case "interest on a zero balance is rejected" R7 int_zero S A +0000000000000 INT 00000000000
reject_case "interest on a negative balance is rejected" R7 int_negative S A -0000000000100 INT 00000000000
reject_case "balance overflow is rejected" R8 overflow C A +9999999999900 DEP 00000000100
expect_eq "overflowing balance is unchanged" +9999999999900 "$(balance_of "$out/ACCTMAST.NEW" $A)"

echo "Control file"
cp "$WORK/run/sample/ACCTMAST.NEW" "$WORK/chain"
cp "$WORK/run/sample/ACCTMAST.NEW.CTL" "$WORK/chain.CTL"
job chain "$WORK/chain" "$WORK/empty"
expect_eq "yesterday's master and control file are accepted" 0 "$rc"
head -3 "$GOOD_MASTER" >"$WORK/cut"
cp "$GOOD_MASTER.CTL" "$WORK/cut.CTL"
job cut_master "$WORK/cut" "$GOOD_TRANS"
expect_eq "a cut-off master gives return code 12" 12 "$rc"
expect_no_file "no new master from a cut-off master" "$out/ACCTMAST.NEW"
cp "$GOOD_MASTER" "$WORK/wrong_total"
echo "000000000007+000000000002755051" >"$WORK/wrong_total.CTL"
job wrong_total "$WORK/wrong_total" "$GOOD_TRANS"
expect_eq "a wrong control total gives return code 12" 12 "$rc"
cp "$GOOD_MASTER" "$WORK/wrong_count"
echo "000000000008+000000000002755050" >"$WORK/wrong_count.CTL"
job wrong_count "$WORK/wrong_count" "$GOOD_TRANS"
expect_eq "a wrong control count gives return code 12" 12 "$rc"
cp "$GOOD_MASTER" "$WORK/garbage"
echo "not a control record" >"$WORK/garbage.CTL"
job garbage_ctl "$WORK/garbage" "$GOOD_TRANS"
expect_eq "an invalid control file gives 16" 16 "$rc"
cp "$GOOD_MASTER" "$WORK/blank_ctl"
: >"$WORK/blank_ctl.CTL"
job blank_ctl "$WORK/blank_ctl" "$GOOD_TRANS"
expect_eq "an empty control file gives 16" 16 "$rc"

echo "Bad input stops the job"
job missing data/NOT-THERE.DAT "$GOOD_TRANS"
expect_eq "missing input gives return code 16" 16 "$rc"
expect_no_file "no new master after failure" "$out/ACCTMAST.NEW"
{ master_line $B C A +0000000100000; master_line $A C A +0000000100000; } >"$WORK/m4"
job master_order "$WORK/m4" "$WORK/empty"
expect_eq "master out of sequence gives 16" 16 "$rc"
{ txn_line $A 000001 DEP 00000010000; txn_line $A 000001 DEP 00000010000; } >"$WORK/t"
job dup_txn "$WORK/m" "$WORK/t"
expect_eq "duplicate transaction gives 16" 16 "$rc"
bad_master_case() { # description case line
    echo "$3" >"$WORK/bm"
    job "$2" "$WORK/bm" "$WORK/empty"
    expect_eq "$1" 16 "$rc"
}
bad_master_case "invalid account type gives 16" bad_type "$(master_line $A X A +0000000100000)"
bad_master_case "invalid account status gives 16" bad_status "$(master_line $A C X +0000000100000)"
bad_master_case "non-numeric balance gives 16" bad_balance "$(master_line $A C A +00000000ABC00)"
bad_master_case "non-numeric master date gives 16" bad_mdate "$(master_line $A C A +0000000100000 ABCDEFGH)"
bad_master_case "impossible master date gives 16" bad_mdate2 "$(master_line $A C A +0000000100000 20261399)"
bad_master_case "missing master date gives 16" no_mdate "$(master_line $A C A +0000000100000 | cut -c1-51)"
good_txn=$(txn_line $A 000001 DEP 00000010000)
later_txn=$(txn_line $A 000002 DEP 00000010000)
printf '\n%s\n' "$good_txn" >"$WORK/t"
job blank_first "$WORK/m" "$WORK/t"
expect_eq "blank first transaction gives 16" 16 "$rc"
printf '%s\n\n%s\n' "$good_txn" "$later_txn" >"$WORK/t"
job blank_middle "$WORK/m" "$WORK/t"
expect_eq "blank middle transaction gives 16" 16 "$rc"
printf '%s\n\n' "$good_txn" >"$WORK/t"
job blank_last "$WORK/m" "$WORK/t"
expect_eq "blank last transaction gives 16" 16 "$rc"
sed '1s/$/EXTRA/' "$GOOD_MASTER" >"$WORK/long"
job long_master "$WORK/long" "$GOOD_TRANS"
expect_eq "over-long master record gives 16" 16 "$rc"
sed '1s/$/EXTRA/' "$GOOD_TRANS" >"$WORK/long"
job long_trans "$GOOD_MASTER" "$WORK/long"
expect_eq "over-long transaction record gives 16" 16 "$rc"
sed 's/$/\r/' "$GOOD_MASTER" >"$WORK/crlf_m"
sed 's/$/\r/' "$GOOD_TRANS" >"$WORK/crlf_t"
job crlf "$WORK/crlf_m" "$WORK/crlf_t"
expect_same_file "Windows line endings give the same result" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"

echo "run.sh safety"
job guard "$GOOD_MASTER" "$GOOD_TRANS"
job guard "$WORK/run/guard/ACCTMAST.NEW" "$GOOD_TRANS"
expect_eq "using an output as the input gives 16" 16 "$rc"
expect_file "the file is not deleted" "$WORK/run/guard/ACCTMAST.NEW"
job guard "$GOOD_MASTER" "$WORK/run/guard/REJECTS.DAT"
expect_eq "using an output as the transactions gives 16" 16 "$rc"
for value in abc 3x 1.5 -5 10000000; do
    CKPT_INTERVAL=$value job "interval_$value" "$GOOD_MASTER" "$GOOD_TRANS"
    expect_eq "CKPT_INTERVAL=$value gives 16" 16 "$rc"
done
CKPT_INTERVAL=0 job interval_0 "$GOOD_MASTER" "$GOOD_TRANS"
expect_same_file "CKPT_INTERVAL=0 still gives the right master" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
MASTER_IN=$GOOD_MASTER TRANS_IN=$GOOD_TRANS OUTDIR=$WORK/m NO_BUILD=1 ./run.sh >/dev/null 2>&1
expect_eq "an output folder that is really a file gives 16" 16 "$?"

echo "Output failures"
many_accounts 30 +0000000010000 >"$WORK/m30"
job_full_disk full30 "$WORK/m30" "$WORK/empty"
expect_eq "full disk at close gives 16" 16 "$rc"
expect_no_file "no new master after a full disk" "$out/ACCTMAST.NEW"
many_accounts 100 +0000000010000 >"$WORK/m100"
CKPT_INTERVAL=5 job_full_disk full100 "$WORK/m100" "$WORK/empty"
expect_eq "full disk at a checkpoint gives 16" 16 "$rc"
expect_no_file "no new master after a checkpoint failure" "$out/ACCTMAST.NEW"
direct open_txn DD_TXNIN=$NOWHERE
expect_eq "unreadable transactions give 16" 16 "$rc"
direct open_a DD_ACCTOUT=$NOWHERE
expect_eq "unwritable master gives 16" 16 "$rc"
direct open_r DD_REJOUT=$NOWHERE
expect_eq "unwritable rejects give 16" 16 "$rc"
direct open_p DD_RPTOUT=$NOWHERE
expect_eq "unwritable report gives 16" 16 "$rc"
direct open_c DD_CTLOUT=$NOWHERE
expect_eq "unwritable control file gives 16" 16 "$rc"
direct open_k DD_CKPTFILE=$NOWHERE CKPT_INTERVAL=1
expect_eq "an irreplaceable checkpoint gives 16" 16 "$rc"
direct open_n DD_CKPTNEW=$NOWHERE CKPT_INTERVAL=1
expect_eq "unwritable new checkpoint gives 16" 16 "$rc"
many_accounts 5000 +0000000010000 >"$WORK/m5000"
awk 'BEGIN { for (i = 1; i <= 5000; i++) printf "9%09d000001DEP0000000010020261108\n", i }' >"$WORK/t5000"
direct full_a DD_ACCTIN=$WORK/m5000 DD_TXNIN=$WORK/empty DD_ACCTOUT=/dev/full
expect_eq "master write failure gives 16" 16 "$rc"
direct full_p DD_ACCTIN=$WORK/m5000 DD_TXNIN=$WORK/empty DD_RPTOUT=/dev/full
expect_eq "report write failure gives 16" 16 "$rc"
direct full_r DD_ACCTIN=$WORK/m5000 DD_TXNIN=$WORK/t5000 DD_REJOUT=/dev/full
expect_eq "rejects write failure gives 16" 16 "$rc"

echo "Large numbers"
{ master_line $A C A +0000000100000; } >"$WORK/m1"
awk -v id=$A 'BEGIN { for (i = 1; i <= 1000; i++) printf "%s%06dDEP0000000000120261108\n", id, i }' >"$WORK/t1000"
job thousand "$WORK/m1" "$WORK/t1000"
expect_eq "an account with 1000 transactions is counted" 1000 "$(awk -v id=$A '$1 == id { print $(NF - 2) }' "$out/REPORT.TXT")"
many_accounts 100001 +9999999999999 >"$WORK/m_huge"
job huge_totals "$WORK/m_huge" "$WORK/empty"
expect_eq "control total overflow gives 16" 16 "$rc"
expect_no_file "no new master after total overflow" "$out/ACCTMAST.NEW"

echo "Control totals catch a broken program"
broken_case() { # description name sed-expression
    if mutant "$2" "$3"; then
        BIN=$WORK/$2.bin job "$2_run" "$GOOD_MASTER" "$GOOD_TRANS"
        expect_eq "$1 gives return code 12" 12 "$rc"
        expect_no_file "$1 gives no new master" "$out/ACCTMAST.NEW"
    fi
}
broken_case "lost withdrawals" lost_wdr 's/ADD WS-TXN-AMT TO TOT-WDR/ADD ZERO TO TOT-WDR/'
broken_case "a miscounted transaction" lost_applied 's/ADD 1 TO CNT-APPLIED CNT-ACCT-TXNS/ADD 1 TO CNT-ACCT-TXNS/'
broken_case "a miscounted account" lost_written 's/ADD 1 TO CNT-MAST-WRITTEN/ADD ZERO TO CNT-MAST-WRITTEN/'

if mutant lost_line '/MOVE RPT-DETAIL    TO RPT-LINE/{n;s/PERFORM 7000-WRITE-REPORT/CONTINUE/}'; then
    BIN=$WORK/lost_line.bin job lost_line_run "$GOOD_MASTER" "$GOOD_TRANS"
    expect_eq "a report with missing lines gives 16" 16 "$rc"
    expect_no_file "a report with missing lines gives no new master" "$out/ACCTMAST.NEW"
fi

echo "Checkpoint and restart"
CKPT_INTERVAL=1 job every_acct "$GOOD_MASTER" "$GOOD_TRANS"
expect_same_file "checkpointing does not change the master" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
expect_same_file "checkpointing does not change the report" tests/expected/REPORT.TXT "$out/REPORT.TXT"

# Account 6 is made out of sequence, so the job fails after writing
# account 5. The last checkpoint is after account 4.
sed '6s/^1000000006/1000000001/' "$GOOD_MASTER" >"$WORK/crash_master"
crash() { # case
    CKPT_INTERVAL=2 job "$1" "$WORK/crash_master" "$GOOD_TRANS"
}
restart() { # case [master] [trans]
    CKPT_INTERVAL=2 job "$1" "${2:-$GOOD_MASTER}" "${3:-$GOOD_TRANS}" restart
}
crash restart
expect_eq "failed run gives return code 16" 16 "$rc"
expect_eq "checkpoint is after account 4" 1000000004 "$(cut -c1-10 "$out/CHECKPOINT.DAT")"
expect_eq "failed run wrote past the checkpoint" 5 "$(wc -l <"$out/ACCTMAST.TMP")"
expect_no_file "no new master after crash" "$out/ACCTMAST.NEW"
expect_no_file "no final report after crash" "$out/REPORT.TXT"
restart restart
expect_eq "restarted run gives return code 4" 4 "$rc"
expect_same_file "restart master matches an unbroken run" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
expect_same_file "restart rejects match an unbroken run" tests/expected/REJECTS.DAT "$out/REJECTS.DAT"
expect_same_file "restart report matches an unbroken run" tests/expected/REPORT.TXT "$out/REPORT.TXT"
expect_no_file "checkpoint removed after success" "$out/CHECKPOINT.DAT"

job no_ckpt "$GOOD_MASTER" "$GOOD_TRANS" restart
expect_eq "restart without a checkpoint gives 16" 16 "$rc"

CKPT_INTERVAL=0 job interval_0_crash "$WORK/crash_master" "$GOOD_TRANS"
expect_no_file "CKPT_INTERVAL=0 takes no checkpoints" "$out/CHECKPOINT.DAT"

job stale "$GOOD_MASTER" "$GOOD_TRANS"
job stale "$WORK/crash_master" "$GOOD_TRANS"
expect_no_file "a failed run removes the previous new master" "$out/ACCTMAST.NEW"

crash leftover
echo "half written" >"$out/CHECKPOINT.NEW"
CKPT_INTERVAL=1000 job leftover "$GOOD_MASTER" "$GOOD_TRANS" restart
expect_same_file "an unfinished new checkpoint is ignored" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
expect_no_file "an unfinished new checkpoint is removed" "$out/CHECKPOINT.NEW"

# A kill while the finished files are being renamed.
crash half_renamed
mv "$out/REJECTS.TMP" "$out/REJECTS.DAT"
mv "$out/ACCTMAST.TMP" "$out/ACCTMAST.NEW"
restart half_renamed
expect_eq "restart after a half-finished rename succeeds" 4 "$rc"
expect_same_file "restart after a half-finished rename is correct" tests/expected/REJECTS.DAT "$out/REJECTS.DAT"

# The transactions run out before the checkpoint is taken.
head -2 "$GOOD_TRANS" >"$WORK/short_t"
job txn_eof_whole "$GOOD_MASTER" "$WORK/short_t"
CKPT_INTERVAL=2 job txn_eof "$WORK/crash_master" "$WORK/short_t"
restart txn_eof "$GOOD_MASTER" "$WORK/short_t"
expect_same_file "restart after the transactions ended is correct" "$WORK/run/txn_eof_whole/REPORT.TXT" "$out/REPORT.TXT"

# The process dies without any cleanup, losing whatever was buffered.
if mutant hard_exit 's/MOVE 16 TO RETURN-CODE/CALL "_exit" USING BY VALUE 9/'; then
    BIN=$WORK/hard_exit.bin CKPT_INTERVAL=2 job hard "$WORK/crash_master" "$GOOD_TRANS"
    expect_eq "the process really died" 9 "$rc"
    restart hard
    expect_same_file "restart after a hard exit matches an unbroken run" tests/expected/ACCTMAST.NEW "$out/ACCTMAST.NEW"
    expect_same_file "report after a hard exit matches an unbroken run" tests/expected/REPORT.TXT "$out/REPORT.TXT"
fi

corrupt_restart() { # description case command-using-$out [master] [trans]
    crash "$2"
    eval "$3"
    restart "$2" "${4:-$GOOD_MASTER}" "${5:-$GOOD_TRANS}"
    expect_eq "$1 gives 16" 16 "$rc"
    expect_no_file "$1 gives no new master" "$out/ACCTMAST.NEW"
}
corrupt_restart "a key moved forward" key_forward 'sed -i "1s/^1000000004/1000000006/" "$out/CHECKPOINT.DAT"'
corrupt_restart "a key moved back" key_back 'sed -i "1s/^1000000004/1000000002/" "$out/CHECKPOINT.DAT"'
corrupt_restart "a blank key" key_blank 'sed -i "1s/^1000000004/          /" "$out/CHECKPOINT.DAT"'
corrupt_restart "an empty checkpoint" ckpt_empty ': >"$out/CHECKPOINT.DAT"'
corrupt_restart "a cut-off checkpoint" ckpt_cut 'truncate -s 30 "$out/CHECKPOINT.DAT"'
corrupt_restart "non-numeric counters" ckpt_alpha 'sed -i "1s/^\(.\{22\}\)0/\1X/" "$out/CHECKPOINT.DAT"'
corrupt_restart "a short master output" short_a 'sed -i "2,\$d" "$out/ACCTMAST.TMP"'
corrupt_restart "a short report output" short_p 'sed -i "2,\$d" "$out/REPORT.TMP"'
corrupt_restart "a missing rejects output" no_r 'rm "$out/REJECTS.TMP"'
sed '1s/+0000000250000/+0000000250001/' "$GOOD_MASTER" >"$WORK/changed_m"
corrupt_restart "a changed master" changed_m ':' "$WORK/changed_m"
sed 1d "$GOOD_TRANS" >"$WORK/changed_t"
corrupt_restart "changed transactions" changed_t ':' "$GOOD_MASTER" "$WORK/changed_t"
: >"$WORK/changed_e"
corrupt_restart "an empty master at restart" changed_e ':' "$WORK/changed_e"

crash typo
MASTER_IN=$GOOD_MASTER TRANS_IN=$GOOD_TRANS OUTDIR=$out NO_BUILD=1 ./run.sh Restart >/dev/null 2>&1
expect_eq "a mistyped argument gives 16" 16 "$?"
expect_file "a mistyped argument keeps the checkpoint" "$out/CHECKPOINT.DAT"

# The program must check the checkpoint itself, not only run.sh.
crash direct_ckpt
sed -i '1s/^\(.\{22\}\)0/\1X/' "$out/CHECKPOINT.DAT"
PARM=RESTART direct direct_run DD_CKPTFILE=$out/CHECKPOINT.DAT DD_ACCTOUT=$out/ACCTMAST.TMP DD_REJOUT=$out/REJECTS.TMP DD_RPTOUT=$out/REPORT.TMP
expect_eq "the program rejects an invalid checkpoint" 16 "$rc"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
