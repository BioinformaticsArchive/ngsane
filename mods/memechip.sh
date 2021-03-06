#!/bin/bash -e

echo ">>>>> Motif discovery with memechip"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -r REFERENCE -o OUTDIR [OPTIONS]"
exit
}

# Script for de-novo motif discovery using meme-chip
# It takes bed regions that are enriched for the ChIPed molecule.
# It produces enriched DNA binding motifs and run the most enriched motif on the input bed file
# author: Fabian Buske
# date: August 2013

# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME <DIR>/<TASK>/<SAMPLE>.summary.txt

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f | --bed )            shift; f=$1 ;; # bed file containing enriched regions (peaks)
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

for MODULE in $MODULE_MEMECHIP; do module load $MODULE; done  # save way to load modules that itself load other modules

export PATH=$PATH_MEMECHIP:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--bedtools    --\n "$(bedtools --version)
[ -z "$(which bedtools)" ] && echo "[ERROR] no bedtools detected" && exit 1
echo -e "--perl        --\n "$(perl -v | grep "This is perl" )
[ -z "$(which perl)" ] && echo "[ERROR] no perl detected" && exit 1
echo -e "--meme-chip   --\n "$(cat `which meme`.bin | strings | grep -A 2 "MEME - Motif discovery tool" | tail -n 1)
[ -z "$(which meme-chip)" ] && echo "[ERROR] meme-chip not detected" && exit 1

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f
n=${f##*/}

if [ -z "$FASTA" ] || [ ! -f $FASTA ]; then
    echo "[ERROR] no reference provided (FASTA)"
    exit 1
else
    echo "[NOTE] Reference: $FASTA"
fi

GENOME_CHROMSIZES=${FASTA%.*}.chrom.sizes
if [ ! -f $GENOME_CHROMSIZES ]; then
    echo "[ERROR] GENOME_CHROMSIZES not found. Excepted at $GENOME_CHROMSIZES"
    exit 1
else
    echo "[NOTE] Chromosome size: $GENOME_CHROMSIZES"

fi
echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a ${f}
	dmget -a $OUTDIR/*
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="get sequence data"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else

    if [ -n "$SLOPBEDADDPARAM" ]; then
        echo "[NOTE] extend bed regions: $EXTENDREGION"
    
        RUN_COMMAND="bedtools slop -i $f -g $GENOME_CHROMSIZES $SLOPBEDADDPARAM  > $OUTDIR/$n"
        echo $RUN_COMMAND && eval $RUN_COMMAND
        f=$OUTDIR/$n
    fi
    
    bedtools getfasta -name -fi $FASTA -bed $f -fo $OUTDIR/${n/$BED/.fasta}

    # mark checkpoint
    if [ -f $OUTDIR/${n/$BED/.fasta} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="create background model"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    # create background from bed file unless provided
    if [ -z $MEMEBACKGROUND ]; then
        fasta-get-markov -nostatus $FASTAGETMARKOVADDPARAM < $OUTDIR/${n/$BED/.fasta} > $OUTDIR/${n/$BED/.bg}
    fi
    # mark checkpoint
    if [ -f $OUTDIR/${n/$BED/.bg} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi
MEMEBACKGROUND=$OUTDIR/${n/$BED/.bg}

################################################################################
CHECKPOINT="meme-chip"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    RUN_COMMAND="meme-chip $MEMECHIPADDPARAM -oc $OUTDIR/${n/$BED/} -bfile $MEMEBACKGROUND -desc ${n/$BED/} -db $MEMECHIPDATABASES -meme-p $CPU_MEMECHIP $OUTDIR/${n/$BED/.fasta}"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    # mark checkpoint
    if [ -f $OUTDIR/${n/$BED/}/combined.meme ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="classify bound regions"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "Peak regions: `wc -l $f | awk '{print $1}'`" > $OUTDIR/${n/$BED/.summary.txt}
       
    RUN_COMMAND="fimo $FIMOADDPARAM --bgfile $MEMEBACKGROUND --oc $OUTDIR/${n/$BED/_fimo} $OUTDIR/${n/$BED/}/combined.meme $OUTDIR/${n/$BED/.fasta}"
    echo $RUN_COMMAND && eval $RUN_COMMAND

    sort -k4,4 -k1,1 -k2,2g $f > $OUTDIR/${n/$BED/_sorted.bed}
    
    if [[ "$(wc -l $OUTDIR/${n/$BED/_fimo}/fimo.txt)" -le 1 ]]; then
        echo "[NOTE] no motif occurences enriched using fimo with given cutoff"
    
    else
        for PATTERN in $(tail -n+2 $OUTDIR/${n/$BED/_fimo}/fimo.txt | awk '{print $1}' | sort -u); do
            echo "[NOTE] Motif: $PATTERN"
        
            grep -P "^${PATTERN}\t" $OUTDIR/${n/$BED/_fimo}/fimo.txt | cut -f2-4,6 | tail -n+2 | sort -k1,1 > $OUTDIR/${n/$BED/_fimo}/$PATTERN.txt
        
            join -1 1 -2 4 $OUTDIR/${n/$BED/_fimo}/$PATTERN.txt $OUTDIR/${n/$BED/_sorted.bed} | awk '{OFS="\t"; print $5,$6+$2,$6+$3,$1,$4,$9}' > $OUTDIR/${n/$BED/_motif}_${PATTERN}.direct.bed
            
            comm -13 <(awk '{print $1}' $OUTDIR/${n/$BED/_fimo}/$PATTERN.txt | sort -u ) <(awk '{print $4}' $f | sort -u ) > $OUTDIR/${n/$BED/_fimo}/${PATTERN}_tmp.txt
        
            join -1 4 -2 1 $OUTDIR/${n/$BED/_sorted.bed} $OUTDIR/${n/$BED/_fimo}/${PATTERN}_tmp.txt | awk '{OFS="\t"; print 2,$3,$4,$1,$5,$6}' > $OUTDIR/${n/$BED/_motif}_${PATTERN}.indirect.bed
            
            echo "Motif $PATTERN bound directly (strong site): $(cat $OUTDIR/${n/$BED/_motif}_${PATTERN}.direct.bed | awk '{print $4}' | sort -u | wc -l | awk '{print $1}')" >> $OUTDIR/${n/$BED/.summary.txt}
            echo "Motif $PATTERN bound indirectly (weak or no site): $(cat $OUTDIR/${n/$BED/_motif}_${PATTERN}.indirect.bed | awk '{print $4}' | sort -u | wc -l | awk '{print $1}')" >> $OUTDIR/${n/$BED/.summary.txt}
            
            echo "Most similar known motif: "$(cat $OUTDIR/${n/$BED/}/meme_tomtom_out/tomtom.txt | head -n 2 | tail -n 1 | cut -f 2) >> $OUTDIR/${n/$BED/.summary.txt}
            echo "Q-value: "$(cat $OUTDIR/${n/$BED/}/meme_tomtom_out/tomtom.txt | head -n 2 | tail -n 1 | cut -f 6) >> $OUTDIR/${n/$BED/.summary.txt}
            echo "Query consensus: "$(cat $OUTDIR/${n/$BED/}/meme_tomtom_out/tomtom.txt | head -n 2 | tail -n 1 | cut -f 8) >> $OUTDIR/${n/$BED/.summary.txt}
            echo "Target consensus: "$(cat $OUTDIR/${n/$BED/}/meme_tomtom_out/tomtom.txt | head -n 2 | tail -n 1 | cut -f 9) >> $OUTDIR/${n/$BED/.summary.txt}
        done
    fi
    
    # mark checkpoint
    if [ -f $OUTDIR/${n/$BED/.summary.txt} ];then echo -e "\n********* $CHECKPOINT   \n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
    
fi

################################################################################
CHECKPOINT="cleanup"    

[ -e $OUTDIR/${n/$BED/.fasta} ] && rm $OUTDIR/${n/$BED/.fasta}
[ -d $OUTDIR/${n/$BED/_fimo} ] && rm -r $OUTDIR/${n/$BED/_fimo}
[ -e $OUTDIR/${n/$BED/_sorted.bed} ] && rm $OUTDIR/${n/$BED/_sorted.bed}
[ -e $OUTDIR/${n/$BED/.bg} ] && rm $OUTDIR/${n/$BED/.bg} 

echo -e "\n********* $CHECKPOINT\n"
################################################################################
[ -e $OUTDIR/${n/$BED/.summary.txt}.dummy ] && rm $OUTDIR/${n/$BED/.summary.txt}.dummy
echo ">>>>> Motif discovery with memechip - FINISHED"
echo ">>>>> enddate "`date`

