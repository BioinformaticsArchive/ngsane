#!/bin/bash -e

echo ">>>>> ChIPseq analysis with Homer"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -o OUTDIR [OPTIONS]"
exit
}

# Script for ChIP-seq peak calling using Homer.
# It takes read alignments in .bam format.
# It produces output files: peak regions in bed format
# author: Fabian Buske
# date: August 2013

# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME <DIR>/<TASK>/<SAMPLE>/tagLengthDistribution.txt

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir 
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
CHECKPOINT="programs"

for MODULE in $MODULE_HOMERCHIPSEQ; do module load $MODULE; done  # save way to load modules that itself load other modules

export PATH=$PATH_HOMERCHIPSEQ:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--samtools    --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--homer       --\n "$(which makeTagDirectory)
[ -z "$(which makeTagDirectory)" ] && echo "[ERROR] homer not detected" && exit 1

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f
n=${CHIPINPUT##*/}
SAMPLE=${n/%.$ASD.bam/}

if [ -z "$CHIPINPUT" ]; then
    echo "[ERROR] no CHIPINPUT detected: $CHIPINPUT"
    exit 1
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
    dmget -a $f
    dmget -a $OUTDIR/*
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="create tagdirectory"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else

    RUN_COMMAND="makeTagDirectory $OUTDIR/$SAMPLE $CHIPINPUT $HOMER_CHIPSEQ_TAGDIR_ADDPARAM"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    # mark checkpoint
    if [ -e $OUTDIR/$SAMPLE/tagLengthDistribution.txt ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
[ -e $OUTDIR/$SAMPLE/tagLengthDistribution.txt.dummy ] && rm $OUTDIR/$SAMPLE/tagLengthDistribution.txt.dummy
echo ">>>>> ChIPseq analysis with Homer - FINISHED"
echo ">>>>> enddate "`date`

