#!/bin/bash -e

echo ">>>>> read mapping with bowtie 1"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> bowtie.sh $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f FASTQ -r REFERENCE -o OUTDIR [OPTIONS]"
exit
}

# Script to run bowtie v1 program.
# It takes comma-seprated list of files containing short sequence reads in fasta or fastq format and bowtie index files as input.
# It produces output files: read alignments in .bam format and other files.
# author: Fabian Buske
# date: June 2013

# QCVARIABLES,Resource temporarily unavailable

if [ ! $# -gt 3 ]; then usage ; fi

THREADS=1
MEMORY=2
FASTQNAME=
FORCESINGLE=0

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository                       
        -t | --threads )        shift; THREADS=$1 ;; # number of CPUs to use                                      
        -m | --memory )         shift; MEMORY=$1 ;; # memory used 
        -f | --fastq )          shift; f=$1 ;; # fastq file                                                       
        -r | --reference )      shift; FASTA=$1 ;; # reference genome                                             
        -o | --outdir )         shift; MYOUT=$1 ;; # output dir                                                     
        -i | --rgid )           shift; EXPID=$1 ;; # read group identifier RD ID                                  
        -l | --rglb )           shift; LIBRARY=$1 ;; # read group library RD LB                                   
        -p | --rgpl )           shift; PLATFORM=$1 ;; # read group platform RD PL                                 
        -s | --rgsi )           shift; SAMPLEID=$1 ;; # read group sample RG SM (pre)                             
        -u | --rgpu )           shift; UNIT=$1 ;; # read group platform unit RG PU
        --fastqName )           shift; FASTQNAME=$1 ;; #(name of fastq or fastq.gz)
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

JAVAPARAMS="-Xmx"$MEMORY"G -Djava.io.tmpdir="$TMP #-XX:ConcGCThreads=1 -XX:ParallelGCThreads=1 -XX:MaxDirectMemorySize=10G"
echo "JAVAPARAMS "$JAVAPARAMS

echo "********* programs"
for MODULE in $MODULE_BOWTIE; do module load $MODULE; done  # save way to load modules that itself load other modules
export PATH=$PATH_BOWTIE:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)
PATH_IGVTOOLS=$(dirname $(which igvtools.jar))
PATH_PICARD=$(dirname $(which MarkDuplicates.jar))
echo -e "--JAVA       --\n" $(java -version 2>&1)
[ -z "$(which java)" ] && echo "[ERROR] no java detected" && exit 1
echo -e "--bowtie     --\n "$(bowtie --version)
[ -z "$(which bowtie)" ] && echo "[ERROR] no bowtie detected" && exit 1
echo -e "--samtools   --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R          --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--igvtools   --\n "$(java -jar $JAVAPARAMS $PATH_IGVTOOLS/igvtools.jar version 2>&1)
[ ! -f $PATH_IGVTOOLS/igvtools.jar ] && echo "[ERROR] no igvtools detected" && exit 1
echo -e "--PICARD     --\n "$(java -jar $JAVAPARAMS $PATH_PICARD/MarkDuplicates.jar --version 2>&1)
[ ! -f $PATH_PICARD/MarkDuplicates.jar ] && echo "[ERROR] no picard detected" && exit 1
echo -e "--samstat    --\n "$(samstat -h | head -n 2 | tail -n1)
[ -z "$(which samstat)" ] && echo "[ERROR] no samstat detected" && exit 1
echo -e "--convert    --\n "$(convert -version | head -n 1)
[ -z "$(which convert)" ] && echo "[WARN] imagemagick convert not detected" 
echo -e "--wigToBigWig --\n "$(wigToBigWig 2>&1 | tee | head -n 1)
[ -z "$(which wigToBigWig)" ] && echo "[WARN] wigToBigWig not detected - no bigwigs will be generated"

# check library variables are set
if [[ -z "$EXPID" || -z "$LIBRARY" || -z "$PLATFORM" ]]; then
    echo "[ERROR] library info not set (EXPID, LIBRARY, and PLATFORM): free text needed"
    exit 1;
else
    echo "[NOTE] EXPID $EXPID; LIBRARY $LIBRARY; PLATFORM $PLATFORM"
fi

# get basename of f
n=${f##*/}


# delete old bam file                                                                                             
if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} ]; then rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}; fi
if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats ]; then rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats; fi
if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl ]; then rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl; fi

#is paired ?                                                                                                      
if [ -n "$READTWO" ] && [ -e ${f/$READONE/$READTWO} ] && [ "$FORCESINGLE" = 0 ]; then
    PAIRED="1"
else
    PAIRED="0"
fi

#is ziped ?                                                                                                       
ZCAT="zcat"
if [[ ${f##*.} != "gz" ]]; then ZCAT="cat"; fi

echo "********* generating the index files"
FASTASUFFIX=${FASTA##*.}
if [ ! -e ${FASTA/.${FASTASUFFIX}/}.1.ebwt ]; then echo ">>>>> make .ebwt"; bowtie-build $FASTA ${FASTA/.${FASTASUFFIX}/}; fi
if [ ! -e $FASTA.fai ]; then echo ">>>>> make .fai"; samtools faidx $FASTA; fi

if [ -n "$DMGET" ]; then
	echo "********* recall files from tape"
	dmget -a $(dirname $FASTA)/*
	dmls -l $FASTA*
	dmget -a ${f/$READONE/"*"}
	dmls -l ${f/$READONE/"*"}
fi

echo "********* bowtie"
if [ $PAIRED == "0" ]; then 
    READS="$f"
    let FASTQREADS=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
else 
    READS="-1 $f -2 ${f/$READONE/$READTWO}"
    READ1=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
    READ2=`$ZCAT ${f/$READONE/$READTWO} | wc -l | gawk '{print int($1/4)}' `
    let FASTQREADS=$READ1+$READ2
fi

#readgroup
FULLSAMPLEID=$SAMPLEID"${n/%$READONE.$FASTQ/}"
RG="--sam-RG \"ID:$EXPID\" --sam-RG \"SM:$FULLSAMPLEID\" --sam-RG \"LB:$LIBRARY\" --sam-RG \"PL:$PLATFORM\""

# check if fastq are compressed
$GZIP -t $f 2>/dev/null
if [[ $? -eq 0 ]] && [ $PAIRED == "0" ]; then
    # pipe gzipped fastqs into bowtie
    RUN_COMMAND="$GZIP -dc $f | bowtie $RG $BOWTIEADDPARAM --threads $THREADS --un $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} --max $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} --sam $BOWTIE_OPTIONS ${FASTA/.${FASTASUFFIX}/} - $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}"
else
    echo "[NOTE] unzip fastq files"
    $GZIP -cd $f > $f.unzipped
    $GZIP -cd ${f/$READONE/$READTWO} > ${f/$READONE/$READTWO}.unzipped
    RUN_COMMAND="bowtie $RG $BOWTIEADDPARAM --threads $THREADS --un $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} --max $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} --sam $BOWTIE_OPTIONS ${FASTA/.${FASTASUFFIX}/} -1 $f.unzipped -2 ${f/$READONE/$READTWO}.unzipped $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}"
fi
echo $RUN_COMMAND
eval $RUN_COMMAND

# create bam files for discarded reads and remove fastq files
if [ $PAIRED == "1" ]; then
    if [ -e $MYOUT/${n/%$READONE.$FASTQ/.${UNM}_1.fq} ]; then
    java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
        FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.${UNM}_1.fq} \
        FASTQ2=$MYOUT/${n/%$READONE.$FASTQ/.${UNM}_2.fq} \
        OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} \
        QUALITY_FORMAT=Standard \
        SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
        READ_GROUP_NAME=null \
        QUIET=TRUE \
        VERBOSITY=ERROR
    samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp}
    mv $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam}
    fi

    if [ -e $MYOUT/${n/%$READONE.$FASTQ/.${MUL}_1.fq} ]; then
    java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
        FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}_1.fq} \
        FASTQ2=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}_2.fq} \
        OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.${MUL}.bam} \
        QUALITY_FORMAT=Standard \
        SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
        READ_GROUP_NAME=null \
        QUIET=TRUE \
        VERBOSITY=ERROR

    samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp}
    mv $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam}
    fi
else
    if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} ]; then
    java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
        FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.fq} \
        OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} \
        QUALITY_FORMAT=Standard \
        SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
        READ_GROUP_NAME=null \
        QUIET=TRUE \
        VERBOSITY=ERROR
    samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp}
    mv $MYOUT/${n/%$READONE.$FASTQ/.$UNM.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$UNM.bam}
    fi

    if [ -e $MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} ]; then
    java $JAVAPARAMS -jar $PATH_PICARD/FastqToSam.jar \
        FASTQ=$MYOUT/${n/%$READONE.$FASTQ/.$MUL.fq} \
        OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} \
        QUALITY_FORMAT=Standard \
        SAMPLE_NAME=${n/%$READONE.$FASTQ/} \
        READ_GROUP_NAME=null \
        QUIET=TRUE \
        VERBOSITY=ERROR

    samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp}
    mv $MYOUT/${n/%$READONE.$FASTQ/.$MUL.tmp.bam} $MYOUT/${n/%$READONE.$FASTQ/.$MUL.bam} 
    fi
fi
# cleanup
rm -f $f.unzipped ${f/$READONE/$READTWO}.unzipped
rm -f $MYOUT/${n/%$READONE.$FASTQ/.$UNM*.fq}
rm -f $MYOUT/${n/%$READONE.$FASTQ/.$MUL*.fq}

# continue for normal bam file conversion                                                                         
echo "********* sorting and bam-conversion"
samtools view -Sbt $FASTA.fai $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam} > $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam}
rm -f $MYOUT/${n/%$READONE.$FASTQ/.$ALN.sam}

samtools sort $MYOUT/${n/%$READONE.$FASTQ/.$ALN.bam} $MYOUT/${n/%$READONE.$FASTQ/.ash}

if [ "$PAIRED" = "1" ]; then
    # fix mates
    samtools sort -n $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp
    samtools fixmate $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp.bam - | samtools sort - $MYOUT/${n/%$READONE.$FASTQ/.ash}
    rm $MYOUT/${n/%$READONE.$FASTQ/.ash}.bam.tmp.bam
fi

echo "********* mark duplicates"
if [ ! -e $MYOUT/metrices ]; then mkdir -p $MYOUT/metrices ; fi
THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files                                        
mkdir -p $THISTMP
java $JAVAPARAMS -jar $PATH_PICARD/MarkDuplicates.jar \
    INPUT=$MYOUT/${n/%$READONE.$FASTQ/.ash.bam} \
    OUTPUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} \
    METRICS_FILE=$MYOUT/metrices/${n/%$READONE.$FASTQ/.$ASD.bam}.dupl \
    AS=true \
    VALIDATION_STRINGENCY=LENIENT \
    TMP_DIR=$THISTMP
rm -rf $THISTMP
samtools index $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}


# statistics                                                                                                      
echo "********* statistics"
STATSOUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats
samtools flagstat $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} > $STATSOUT

if [ -n $SEQREG ]; then
    echo "#custom region" >> $STATSOUT
    echo $(samtools view -b $MYOUT/${n/%$READONE.$FASTQ/.ash.bam} $SEQREG | wc -l)" total reads in region " >> $STATSOUT
    echo $(samtools view -b -f 2 $MYOUT/${n/%$READONE.$FASTQ/.ash.bam} $SEQREG | wc -l)" properly paired reads in region " >> $STATSOUT
fi

echo "********* calculate inner distance"
THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
mkdir $THISTMP
java $JAVAPARAMS -jar $PATH_PICARD/CollectMultipleMetrics.jar \
    INPUT=$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} \
    REFERENCE_SEQUENCE=$FASTA \
    OUTPUT=$MYOUT/metrices/${n/%$READONE.$FASTQ/.$ASD.bam} \
    VALIDATION_STRINGENCY=LENIENT \
    PROGRAM=CollectAlignmentSummaryMetrics \
    PROGRAM=CollectInsertSizeMetrics \
    PROGRAM=QualityScoreDistribution \
    TMP_DIR=$THISTMP
  
# create pdfs
if [ -n "$(which convert)" ]; then 
    for im in $( ls $MYOUT/metrices/*.pdf ); do
        convert $im ${im/pdf/jpg}
    done
fi
rm -r $THISTMP

echo "********* verify"
BAMREADS=`head -n1 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}.stats | cut -d " " -f 1`
if [ "$BAMREADS" = "" ]; then let BAMREADS="0"; fi
if [ $BAMREADS -eq $FASTQREADS ]; then
    echo "-----------------> PASS check mapping: $BAMREADS == $FASTQREADS"
    rm $MYOUT/${n/%$READONE.$FASTQ/.ash.bam}
    rm $MYOUT/${n/%$READONE.$FASTQ/.$UNM}.bam
    rm $MYOUT/${n/%$READONE.$FASTQ/.$ALN}.bam
else
    echo -e "[ERROR] We are loosing reads from .fastq -> .bam in $f: \nFastq had $FASTQREADS Bam has $BAMREADS"
    exit 1
fi

#coverage for IGV
echo "********* coverage track"
java $JAVAPARAMS -jar $PATH_IGVTOOLS/igvtools.jar count $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} \
$MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam.cov.tdf} ${FASTA/.$FASTASUFFIX/}.genome

echo "********* samstat"
samstat $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam}

# generate bigwigs
if [ -n "$(which wigToBigWig)" ] && [ -n "$FRAGMENTLENGTH" ]; then 
    echo "********* bigwigs"
    NC=1000000
    N=$(samtools view -c -F 1028 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam})
    SCALEFACTOR=`echo "scale=3; $NC/$N" | bc `
  
    echo "[NOTE] library size (mapped reads): $N" 
    echo "[NOTE] scale factor: $SCALEFACTOR"
    echo "[NOTE] fragment length: $FRAGMENTLENGTH"

    if [ "$PAIRED" = "1" ] && [[ $FRAGMENTLENGTH -le 0 ]]; then
	echo "[NOTE] generate bigwig for properly paired reads on the same chromosomes"
	samtools sort -n $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} $MYOUT/${n/%$READONE.$FASTQ/.$ASD.tmp}
        samtools view -b -F 1028 -f 0x2 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.tmp.bam} | bamToBed -bedpe | awk '($1 == $4){OFS="\t"; print $1,$2,$6,$7,$8,$9}' | genomeCoverageBed -scale $SCALEFACTOR -g ${GENOME_CHROMSIZES} -i stdin -bg | wigToBigWig stdin  ${GENOME_CHROMSIZES} $MYOUT/${n/%$READONE.$FASTQ/.bw}
	rm $MYOUT/${n/%$READONE.$FASTQ/.$ASD.tmp.bam}
    else
        echo "[NOTE] generate (strand-specific) bigwigs considering single reads"
        samtools view -b -F 1028 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} | bamToBed | slopBed -s -r $FRAGMENTLENGTH -l 0 -i stdin -g ${GENOME_CHROMSIZES}  | genomeCoverageBed -scale $SCALEFACTOR -g ${GENOME_CHROMSIZES} -i stdin -bg | wigToBigWig stdin  ${GENOME_CHROMSIZES} $MYOUT/${n/%$READONE.$FASTQ/.bw}
        
        samtools view -b -F 1028 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} | bamToBed | slopBed -s -r $FRAGMENTLENGTH -l 0 -i stdin -g ${GENOME_CHROMSIZES}  | genomeCoverageBed -strand "+" -scale $SCALEFACTOR -g ${GENOME_CHROMSIZES} -i stdin -bg | wigToBigWig stdin  ${GENOME_CHROMSIZES} $MYOUT/${n/%$READONE.$FASTQ/.+.bw}
        
        samtools view -b -F 1028 $MYOUT/${n/%$READONE.$FASTQ/.$ASD.bam} | bamToBed | slopBed -s -r $FRAGMENTLENGTH -l 0 -i stdin -g ${GENOME_CHROMSIZES}  | genomeCoverageBed -strand "-" -scale $SCALEFACTOR -g ${GENOME_CHROMSIZES} -i stdin -bg | wigToBigWig stdin  ${GENOME_CHROMSIZES} $MYOUT/${n/%$READONE.$FASTQ/.-.bw}
    fi
fi

echo ">>>>> read mapping with bowtie 1 - FINISHED"
echo ">>>>> enddate "`date`
