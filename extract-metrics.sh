#!/bin/bash
# Extract key startup metrics from a JFR recording
# Usage: ./extract-metrics.sh <jfr-file> [output-dir]

set -e

JFR_FILE="${1:?Usage: extract-metrics.sh <jfr-file> [output-dir]}"
OUT_DIR="${2:-$(dirname "$JFR_FILE")}"
NAME=$(basename "$JFR_FILE" .jfr)

mkdir -p "$OUT_DIR"

echo "=== Startup Profile: $NAME ==="
echo ""

# Summary
echo "--- Recording ---"
jfr summary "$JFR_FILE" 2>&1 | grep -E "Duration:|Start:"
echo ""

# Thread count
THREADS=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.ThreadStart /{print $2}')
echo "--- Threads: $THREADS started ---"
jfr print --events jdk.ThreadStart "$JFR_FILE" 2>&1 \
	| awk -F'"' '/thread =/{print $2}' \
	| sed 's/ForkJoinPool.commonPool-worker-[0-9]*/ForkJoinPool.commonPool-worker/;s/FelixResolver-[0-9]*/FelixResolver/;s/ForkJoinPool-1-worker-[0-9]*/ForkJoinPool-1-worker/' \
	| sort | uniq -c | sort -rn
echo ""

# GC
echo "--- GC ---"
GC_COUNT=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.GarbageCollection /{print $2}')
GC_PAUSE=$(jfr print --events jdk.GCPhasePause "$JFR_FILE" 2>&1 \
	| awk -F'= ' '/duration =/{gsub(/ ms/,"",$2); sum+=$2} END{printf "%.1f", sum}')
echo "Collections: $GC_COUNT, Total pause: ${GC_PAUSE}ms"
echo ""

# Class loading
CLASSES=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.ClassLoad /{print $2}')
DEFINES=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.ClassDefine /{print $2}')
echo "--- Class loading: $CLASSES loads, $DEFINES defines ---"
echo ""

# Contention
echo "--- Contention ---"
CONTENTION_EVENTS=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.JavaMonitorEnter /{print $2}')
CONTENTION_TOTAL=$(jfr print --events jdk.JavaMonitorEnter "$JFR_FILE" 2>&1 \
	| awk -F'= ' '/duration =/{gsub(/ ms/,"",$2); sum+=$2} END{printf "%.0f", sum}')
echo "Events: $CONTENTION_EVENTS, Total blocked: ${CONTENTION_TOTAL}ms"
echo ""
echo "By monitor class:"
jfr print --events jdk.JavaMonitorEnter "$JFR_FILE" 2>&1 \
	| awk -F'= ' '/monitorClass =/{gsub(/ \(classLoader.*/, "", $2); mc=$2} /duration =/{d=$2} /eventThread =/{print d, mc}' \
	| awk '{class=$2; for(i=3;i<=NF;i++) class=class" "$i; dur=$1; gsub(/ ms/,"",dur); classes[class]+=dur; count[class]++} END{for(c in classes) printf "  %8.1fms (%2d events) %s\n", classes[c], count[c], c | "sort -rn"}'
echo ""

# File I/O counts
READS=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.FileRead /{print $2}')
WRITES=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.FileWrite /{print $2}')
echo "--- File I/O: $READS reads, $WRITES writes ---"
echo ""

# Deoptimizations
DEOPTS=$(jfr summary "$JFR_FILE" 2>&1 | awk '/jdk.Deoptimization /{print $2}')
echo "--- Deoptimizations: $DEOPTS ---"
echo ""

# Write machine-readable summary
cat > "$OUT_DIR/${NAME}-metrics.txt" <<EOF
threads=$THREADS
gc_count=$GC_COUNT
gc_pause_ms=$GC_PAUSE
class_loads=$CLASSES
class_defines=$DEFINES
contention_events=$CONTENTION_EVENTS
contention_total_ms=$CONTENTION_TOTAL
file_reads=$READS
file_writes=$WRITES
deopts=$DEOPTS
EOF

echo "Metrics written to $OUT_DIR/${NAME}-metrics.txt"
