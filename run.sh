#!/usr/bin/env bash
# Compiles BANKBTCH and runs it.
#
#   ./run.sh           normal run
#   ./run.sh restart   resume a failed run from its last checkpoint
#
# File names are mapped through DD_* variables, the same way JCL DD
# statements map them on a mainframe. Outputs are written to temporary
# names, checked, and only renamed if the job succeeds.
#
# Exit codes: 0 clean, 4 rejects written, 12 out of balance, 16 failed.
# A job that is killed exits with the code of the signal that killed it.
set -Eeuo pipefail
trap 'exit 16' ERR
cd "$(dirname "$0")"

fail() {
    echo "run.sh: $*" >&2
    exit 16
}

MODE=${1:-}
case "$MODE" in
    "" | restart) ;;
    *) fail "unknown argument '$MODE'. The only option is: restart" ;;
esac

MASTER_IN=${MASTER_IN:-data/ACCTMAST.DAT}
TRANS_IN=${TRANS_IN:-data/TRANS.DAT}
OUTDIR=${OUTDIR:-output}
BIN=${BIN:-build/bankbtch}
CKPT_INTERVAL=${CKPT_INTERVAL:-1000}
mkdir -p build "$OUTDIR"

[[ $CKPT_INTERVAL =~ ^[0-9]{1,7}$ ]] || fail "CKPT_INTERVAL must be a whole number of up to 7 digits."
export CKPT_INTERVAL

if [ -z "${NO_BUILD:-}" ]; then
    cobc -x -fixed -Wall -I copybooks -o build/bankbtch src/BANKBTCH.cbl
fi

export DD_ACCTIN=$MASTER_IN
export DD_TXNIN=$TRANS_IN
export DD_CTLIN=$MASTER_IN.CTL
export DD_ACCTOUT=$OUTDIR/ACCTMAST.TMP
export DD_REJOUT=$OUTDIR/REJECTS.TMP
export DD_RPTOUT=$OUTDIR/REPORT.TMP
export DD_CTLOUT=$OUTDIR/CONTROL.TMP
export DD_CKPTFILE=$OUTDIR/CHECKPOINT.DAT
export DD_CKPTNEW=$OUTDIR/CHECKPOINT.NEW
NEW_MASTER=$OUTDIR/ACCTMAST.NEW
NEW_REJECTS=$OUTDIR/REJECTS.DAT
NEW_REPORT=$OUTDIR/REPORT.TXT
NEW_CONTROL=$OUTDIR/ACCTMAST.NEW.CTL
ALL_OUTPUTS=("$DD_ACCTOUT" "$DD_REJOUT" "$DD_RPTOUT" "$DD_CTLOUT" "$DD_CKPTFILE" "$DD_CKPTNEW"
             "$NEW_MASTER" "$NEW_REJECTS" "$NEW_REPORT" "$NEW_CONTROL")

# An input must be a real file, must not be overwritten by this run,
# and must not hold records that the program would silently cut off.
check_input() { # file record-length
    local bad
    [ -f "$1" ] || fail "input file not found: $1"
    for output in "${ALL_OUTPUTS[@]}"; do
        [ "$(realpath -m -- "$1")" != "$(realpath -m -- "$output")" ] ||
            fail "$1 is also an output of this run. Copy it somewhere else first."
    done
    if ! bad=$(LC_ALL=C awk -v max="$2" '{ sub(/\r$/, "") } length($0) > max { print FNR; exit 1 }' "$1"); then
        fail "$1 line $bad is longer than $2 characters."
    fi
}
check_input "$MASTER_IN" 59
check_input "$TRANS_IN" 38

keep_first_lines() { # file count
    [ -f "$1" ] || fail "cannot restart, $1 is missing."
    [ "$(wc -l <"$1")" -ge "$2" ] || fail "cannot restart, $1 is shorter than the checkpoint says."
    head -n "$2" "$1" >"$1.cut"
    mv "$1.cut" "$1"
}

undo_rename() { # temporary-name final-name
    if [ ! -f "$1" ] && [ -f "$2" ]; then
        mv "$2" "$1"
    fi
}

parm=
if [ "$MODE" = "restart" ]; then
    [ -f "$DD_CKPTFILE" ] || fail "no checkpoint at $DD_CKPTFILE, cannot restart."
    IFS= read -r checkpoint <"$DD_CKPTFILE" || fail "checkpoint is empty or incomplete."
    [[ $checkpoint =~ ^.{10}[0-9]{60}([+-][0-9]{18}){5}$ ]] || fail "checkpoint is invalid."
    written=$((10#${checkpoint:22:12}))
    rejected=$((10#${checkpoint:58:12}))
    # A run killed while renaming its finished files may have moved some.
    undo_rename "$DD_ACCTOUT" "$NEW_MASTER"
    undo_rename "$DD_REJOUT" "$NEW_REJECTS"
    undo_rename "$DD_RPTOUT" "$NEW_REPORT"
    # Drop anything written after the checkpoint. The failed run may
    # have got further than the checkpoint before it stopped.
    keep_first_lines "$DD_ACCTOUT" "$written"
    keep_first_lines "$DD_REJOUT" "$rejected"
    keep_first_lines "$DD_RPTOUT" "$((written + 3))" # 3 heading lines
    parm=RESTART
else
    rm -f "${ALL_OUTPUTS[@]}"
fi

report_count() { # label
    awk -v label="$1" 'index($0, label " ") == 1 { value = $NF; gsub(",", "", value); print value }' "$DD_RPTOUT"
}

# GnuCOBOL can report success when the final buffer of a file fails to
# reach the disk, so what actually landed in each file is checked here.
outputs_are_complete() {
    local written rejected
    written=$(report_count "ACCOUNTS WRITTEN")
    rejected=$(report_count "TRANSACTIONS REJECTED")
    [[ $written =~ ^[0-9]+$ && $rejected =~ ^[0-9]+$ ]] &&
        [ "$(tail -n 1 "$DD_RPTOUT")" = "IN BALANCE" ] &&
        [ "$(wc -l <"$DD_RPTOUT")" -eq "$((written + 18))" ] && # headings + totals
        [ "$(wc -l <"$DD_REJOUT")" -eq "$rejected" ] &&
        [ "$(wc -l <"$DD_CTLOUT")" -eq 1 ] &&
        [ "$(wc -c <"$DD_ACCTOUT")" -eq "$((written * 60))" ] # 59 + newline
}

rc=0
"$BIN" $parm || rc=$?

if [ "$rc" -le 4 ] && ! outputs_are_complete; then
    echo "run.sh: output files are incomplete or do not match the report." >&2
    rc=16
fi
echo "Return code: $rc"

if [ "$rc" -le 4 ]; then
    mv "$DD_REJOUT" "$NEW_REJECTS"
    mv "$DD_RPTOUT" "$NEW_REPORT"
    mv "$DD_CTLOUT" "$NEW_CONTROL"
    mv "$DD_ACCTOUT" "$NEW_MASTER" # last, so its presence means all are done
    rm -f "$DD_CKPTFILE" "$DD_CKPTNEW"
    cat "$NEW_REPORT" || true # the job is already complete
else
    echo "Job failed. New master was NOT produced. Partial files are named *.TMP."
fi
exit "$rc"
