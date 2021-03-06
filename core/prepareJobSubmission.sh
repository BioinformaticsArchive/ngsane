#!/bin/bash -e

#
# General template for submitting a job 
#


#INPUTS
while [ "$1" != "" ]; do
    case $1 in
    -q | --queue )          shift; QUEUE=$1 ;;     # nodetype for qsub
	-k | --toolkit )        shift; CONFIG=$1 ;;    # location of the NGSANE repository
	-i | --input )          shift; ORIGIN=$1 ;;    # subfile in $SOURCE
	-e | --fileending )     shift; ENDING=$1 ;;    # select source files of a specific ending
	-t | --task )           shift; TASK=$1 ;;      # what to do
	-n | --nodes )          shift; NODES=$1;;
	-c | --cpu    )         shift; CPU=$1 ;;       # CPU used
	-m | --memory )         shift; MEMORY=$1;;     # min Memory required
	-w | --walltime )       shift; WALLTIME=$1;;
	-p | --command )        shift; COMMAND=$1;;
	--postcommand )         shift; POSTCOMMAND=$1;;
	--postname )			shift; POSTNAME=$1;;
	--postnodes )           shift; POSTNODES=$1;;
	--postcpu )             shift; POSTCPU=$1 ;;   # CPU used for postcommand
	--postmemory )          shift; POSTMEMORY=$1;; # Memory used for postcommand
	--postwalltime )        shift; POSTWALLTIME=$1;;
	-r | --reverse )        REV="1";;              # input is fastq
	-d | --nodir )          NODIR="nodir";;
	-a | --armed )          ARMED="armed";;
    -W | --wait )           shift; JOBIDS=$1 ;;    # jobids to wait for
    --commontask )          shift; COMMONTASK=$1;; # name of a task common to multiple libraries
	--keep )                KEEP="keep";;
	--new )                 KEEP="new";;
	--recover )             RECOVER="recover";;
	--debug )               DEBUG="debug";;
	--direct )              DIRECT="direct";;
	--first )               FIRST="first";;
	--postonly )            POSTONLY="postonly" ;;
	--dryrun )              DRYRUN="TRUE" ;;
	--givenDirs )			shift; GIVENDIRS=$1 ;;			# given directories instead of Dir from config
	-h | --help )           usage ;;
	* )                     echo "prepareJobSubmission.sh: don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

echo -e "\e[96m[Task]\e[0m $TASK $NODIR"
if [ -n "$GIVENDIRS" ]; then declare -a DIR; DIR=( $GIVENDIRS ); fi
if [ ! -d $QOUT/$TASK ]; then mkdir -p $QOUT/$TASK; fi
if [ -z "$POSTNAME" ]; then POSTNAME="postcommand"; fi

if [ -n "$COMMONTASK" ]; then 
    mkdir -p $OUT/common/$TASK
    COMMAND="$COMMAND -o $OUT/common/$TASK"
fi
        
## Select files in dir to run 
if [[ ! -e $QOUT/$TASK/runnow.tmp || "$KEEP" || "$DEBUG" ]]; then
    echo -e "[NOTE] setup enviroment"
    if [ -e $QOUT/$TASK/runnow.tmp ]; then rm $QOUT/$TASK/runnow.tmp; fi
        
    for dir in ${DIR[@]}; do
    
        # separate folder from sample pattern
        DIRNAME=${dir%%/*}
        SAMPLEPATTERN=${dir/$DIRNAME/}
    
        # ensure dirs are there
        if [ -z "$NODIR" ]; then
            if [ ! -d $OUT/$DIRNAME/$TASK ]; then 
                mkdir -p $OUT/$DIRNAME/$TASK; 
                echo "DIR created $OUT/$DIRNAME/$TASK"
            fi
        fi
        
        # add tasks to runnow.tmp
        # search for real files and dummy files, in case both exist only keep real one
        if [ -n "$REV" ]; then
            for f in $( ls $SOURCE/$DIRNAME/$ORIGIN/$SAMPLEPATTERN*$ENDING* | grep -P ".$ENDING(.dummy)?\$" | sed 's/.dummy//' | sort -u ); do
                n=${f##*/}
                name=${n/$ENDING/}
                LOGFILE=$QOUT/$TASK/$DIRNAME'_'$name'.out'
                if [ "$KEEP" = "new" ] && [ -f $LOGFILE ]; then
                    # check if file has been processed previousely
                	COMMANDARR=(${COMMAND// / })
                	DUMMY="echo "$(grep -P "^# *RESULTFILENAME" ${COMMANDARR[0]} | cut -d " " -f 3- | sed "s/<SAMPLE>/$name/" | sed "s/<DIR>/$DIRNAME/" | sed "s/<TASK>/$TASK/")
                    D=$(eval $DUMMY)
                	if [ -n "$D" ] && [ -f $D ] && [[ $(grep -P "^>{5} .* FINISHED" $LOGFILE | wc -l ) -gt 0 ]] ; then 
                	   echo -e "\e[34m[SKIP]\e[0m $n (already processed: $DIRNAME/${D##*/})"  
                	   continue
                    fi
                fi 
                echo -e "\e[32m[TODO]\e[0m $DIRNAME/$n"
                echo $f >> $QOUT/$TASK/runnow.tmp
            done
        
        else
            for f in $( ls $SOURCE/$ORIGIN/$DIRNAME/$SAMPLEPATTERN*$ENDING* | grep -P ".$ENDING(.dummy)?\$" | sed 's/.dummy//' | sort -u ); do
                n=${f##*/}
                name=${n/$ENDING/}
                LOGFILE=$QOUT/$TASK/$DIRNAME'_'$name'.out'
                if [ "$KEEP" = "new" ] && [ -f $LOGFILE ]; then
                    # check if file has been processed previousely
                	COMMANDARR=(${COMMAND// / })
                	DUMMY="echo "$(grep -P "^# *RESULTFILENAME" ${COMMANDARR[0]} | cut -d " " -f 3- | sed "s/<SAMPLE>/$name/" | sed "s/<DIR>/$DIRNAME/" | sed "s/<TASK>/$TASK/")
                    D=$(eval $DUMMY)
                	if [ -n "$D" ] && [ -f $D ] && [[ $(grep -P "^>{5} .* FINISHED" $LOGFILE | wc -l ) -gt 0 ]]; then
                	   echo -e "\e[34m[SKIP]\e[0m $n (already processed - $DIRNAME/${D##*/})"  
                	   continue
                    fi
                fi 
                echo -e "\e[32m[TODO]\e[0m $DIRNAME/$n"
                echo $f >> $QOUT/$TASK/runnow.tmp
            done
        fi
        
    done
else
    echo -e "[NOTE] previous environment setup detected"
fi
if [ -n "$KEEP" ]; then 
    if [ "$KEEP" = "new" ]; then
        echo -e "[NOTE] Data setup finished. Please, start trigger in \e[4marmed\e[24m or \e[4mdirect\e[24m mode."
    else
        echo -e "[NOTE] Data setup finished. Please, inspect/modify runnow.tmp in the qout/$TASK/runnow.tmp folder and then start \e[4marmed\e[24m or \e[4mdirect\e[24m mode."
    fi
    exit ; 
else
    echo -e "[NOTE] proceeding with job scheduling..."
fi

# record task in log file
JOBLOG=$QOUT/$TASK/job.$(date "+%Y%m%d").log
cat $CONFIG ${NGSANE_BASE}/conf/header.sh ${NGSANE_BASE}/conf/header.d/* > $JOBLOG


MYJOBIDS="" # collect job IDs for postcommand
FILES=""
JOBNUMBER=0
for i in $(cat $QOUT/$TASK/runnow.tmp); do

	let JOBNUMBER=JOBNUMBER+1

    n=$(basename $i) 
    # ending : fastq/xx or xx/bwa
    dir=$(dirname $i | gawk '{n=split($1,arr,"/"); print arr[n]}')
    if [ -n "$REV" ]; then dir=$(dirname $i | gawk '{n=split($1,arr,"/"); print arr[n-1]}'); fi
    name=${n/$ENDING/}
               
    COMMAND2=${COMMAND//<FILE>/$i} # insert files for which parallele jobs are submitted
    COMMAND2=${COMMAND2//<DIR>/$dir} # insert output dir
    COMMAND2=${COMMAND2//<NAME>/$name} # insert ??

    if [ -n "$COMMONTASK" ]; then 
        LOGFILE=$QOUT/$TASK/$dir"_"$COMMONTASK".log"    
    else
        LOGFILE=$QOUT/$TASK/$dir"_"$name".out"
    fi

    FILES=$FILES" $i"

    # only postcommand 
    if [[ -n "$POSTONLY" || -z "$COMMAND" ]]; then MYJOBIDS=$JOBIDS; continue; fi

	# create dummy files for the pipe
	COMMANDARR=(${COMMAND// / })
	DUMMY="echo "$(grep -P "^# *RESULTFILENAME" ${COMMANDARR[0]} | cut -d " " -f 3- | sed "s/<SAMPLE>/$name/" | sed "s/<DIR>/$dir/" | sed "s/<TASK>/$TASK/")
	D=$(eval $DUMMY)
	if [ -n "$D" ]; then
		echo "[NOTE] make $D.dummy"
		[ ! -e $(dirname $D) ] && mkdir -p $(dirname $D)
		touch $D.dummy
	fi

    echo -e "\e[33m[ JOB]\e[0m  $COMMAND2"

    if [ -n "$DEBUG" ]; then eval $COMMAND2; fi

    if [[ -n "$ARMED" || -n "$DIRECT" ]]; then

        if [ -n "$RECOVER" ] && [ -f $LOGFILE ] ; then
            # add log-file for recovery
            COMMAND2="$COMMAND2 --recover-from $LOGFILE"
            
            if [[ $(grep -P "^>{5} .* FINISHED" $LOGFILE | wc -l ) -gt 0 ]] ; then
                echo -e "\e[92m[NOTE]\e[0m Previous $TASK run finished without error - nothing to be done"
                rm $D.dummy
                continue
            else
                echo "[NOTE] #########################################################################" >> $LOGFILE
                echo "[NOTE] Recover from logfile: $LOGFILE" >> $LOGFILE
                # mask old errors
                sed -i "s/^\[ERROR\] /[NOTE][PREVIOUS][ERROR] /g" $LOGFILE
                echo "[NOTE] Previous errors masked" >> $LOGFILE
            fi
            
        else
            # remove old submission output logs
            if [ -e $QOUT/$TASK/$dir'_'$name.out ]; then rm $QOUT/$TASK/$dir'_'$name.out; fi
        fi
    
        echo "[NOTE] Jobfile: "$JOBLOG >> $LOGFILE
        # add citations
		TASKCITE=${TASK/*-/}
        TASKNAME=$(grep -P "^TASK_[A-Z0-9]+=[\"']?$TASKCITE[\"']? *$" $JOBLOG | cut -d "=" -f 1 | cut -d ":" -f 2)
		CITED_PROGRAMS=$(grep -P "^${TASKNAME/TASK/MODULE}=" $JOBLOG | sed -e "s|^${TASKNAME/TASK/MODULE}||" | sed -e 's/["=${}]//g' | sed -e 's/NG_/NG_CITE_/g')
        for M in NG_CITE_NGSANE $CITED_PROGRAMS; do

            CITE=$(grep -P "^$M=" $JOBLOG) || CITE=""
            if [ -n "$CITE" ]; then
                echo -e "[CITE] ${CITE/$M=/}" >> $LOGFILE
            fi 
        done

		#eval job directly but write to logfile
	    if [ -n "$DIRECT" ]; then echo "[NOTE] write $LOGFILE"; eval $COMMAND2 >> $LOGFILE 2>&1; continue; fi

        if [ -n "$JOBIDS" ]; then
            echo "check joids"
            if [[ $(echo $JOBIDS | sed 's/:*$//g'| awk -F':' '{print NF}') == 1 ]]; then
                # everyone waits for the same job if only one id was given
                JOBID=$(echo $JOBIDS | cut -d ":" -f 1)        
            else
                # otherwise wait for job in corresponding slot
                JOBID=$(echo $JOBIDS | cut -d ":" -f $JOBNUMBER)
            fi
			
			echo -e "[NOTE] wait for $JOBID out of $JOBIDS"
            RECIPT=$($BINQSUB -a "$QSUBEXTRA" -W "$JOBID" -k $CONFIG -m $MEMORY -n $NODES -c $CPU -w $WALLTIME \
        	   -j $TASK'_'$dir'_'$name$COMMONTASK -o $LOGFILE --command "$COMMAND2")
        else 
            RECIPT=$($BINQSUB -a "$QSUBEXTRA" -k $CONFIG -m $MEMORY -n $NODES -c $CPU -w $WALLTIME \
        	   -j $TASK'_'$dir'_'$name$COMMONTASK -o $LOGFILE --command "$COMMAND2")
        fi    	

        echo -e "Jobnumber $RECIPT"
        MYJOBIDS=$MYJOBIDS$RECIPT":"
    
        # if only the first task should be submitted as test
        if [[ -n "$FIRST" || -n "$COMMONTASK" ]] ; then exit; fi
    
    fi
done


if [ -n "$POSTCOMMAND" ]; then
   # process for postcommand
	dir=$(echo ${DIR[@]} | sort -u |sed 's/ /_/g')
	#DIR=$(echo ${DIR[@]} | tr " " "\n" | sort -u | tr "\n" "_" | sed 's/_$//' )
    #DIR=$(echo -e ${DIR// /\\n} | sort -u -r | gawk 'BEGIN{x=""};{x=x"_"$0}END{print x}' | sed 's/__//' | sed 's/^_//' | sed 's/_$//' )
    FILES=$(echo -e $FILES | sed 's/ /,/g')
    POSTCOMMAND2=${POSTCOMMAND//<FILE>/$FILES}
    POSTCOMMAND2=${POSTCOMMAND2//<DIR>/$dir}
	POSTLOGFILE=$QOUT/$TASK/$POSTNAME.out

    echo "[NOTE] "$POSTCOMMAND2

	# create dummy files for the pipe
	COMMANDARR=(${POSTCOMMAND// / })
	if [ -n "$(grep RESULTFILENAME ${COMMANDARR[0]})" ]; then
		DUMMY="echo "$(grep -P "^# *RESULTFILENAME" ${COMMANDARR[0]} | cut -d " " -f 3- | sed "s/<DIR>/$dir/g" | sed "s/<TASK>/$TASK/g" | sed "s/<ADDDUMMY>/$ADDDUMMY/g")
		D=$(eval $DUMMY)
		echo "[NOTE] make $D.dummy"
		[ ! -e $(dirname $D) ] && mkdir -p $(dirname $D)
		touch $D.dummy
	fi

    if [[ -n "$DEBUG" || -n "$FIRST" ]]; then eval $POSTCOMMAND2; exit; fi
    if [[ -n "$ARMED" ||  -n "$POSTONLY" || "$DIRECT" ]]; then

    # remove old submission output logs

    if [ -n "$RECOVER" ] && [ -e $POSTLOGFILE ] ; then
         # add log-file for recovery
         POSTCOMMAND2="$POSTCOMMAND2 --recover-from $POSTLOGFILE"
         
         if [[ $(grep -P "^>{5} .* FINISHED" $POSTLOGFILE | wc -l ) -gt 0 ]] ; then
             echo -e "\e[92m[NOTE]\e[0m Previous $TASK run finished without error - nothing to be done"
             MYJOBIDS=""
			 rm $QOUT/$TASK/runnow.tmp && exit;
         else
             echo "[NOTE] #########################################################################" >> $POSTLOGFILE
             echo "[NOTE] Recover from logfile: $POSTLOGFILE" >> $POSTLOGFILE
             # mask old errors
             sed -i "s/^\[ERROR\] /[NOTE][PREVIOUS][ERROR] /g" $POSTLOGFILE
             echo "[NOTE] Previous errors masked" >> $POSTLOGFILE
         fi
	else
		 if [ -e $POSTLOGFILE ]; then rm $POSTLOGFILE; fi
	fi

    # record task in log file
#    cat $CONFIG ${NGSANE_BASE}/conf/header.sh > $QOUT/$TASK/job.$(date "+%Y%m%d").log
#	echo "[NOTE] Jobfile: "$JOBLOG >> $POSTLOGFILE

    echo "[NOTE] Jobfile: "$JOBLOG >> $POSTLOGFILE
    # add citations
	TASKCITE=${TASK/*-/}
    TASKNAME=$(grep -P "^TASK_[A-Z0-9]+=[\"']?$TASKCITE[\"']? *$" $JOBLOG | cut -d "=" -f 1 | cut -d ":" -f 2)
	CITED_PROGRAMS=$(grep -P "^${TASKNAME/TASK/MODULE}=" $JOBLOG | sed -e "s|^${TASKNAME/TASK/MODULE}||" | sed -e 's/["=${}]//g' | sed -e 's/NG_/NG_CITE_/g')
    for M in NG_CITE_NGSANE $CITED_PROGRAMS; do
    	CITE=$(grep -P "^$M=" $JOBLOG) || CITE=""
      	if [ -n "$CITE" ]; then
    	    echo -e "[CITE] ${CITE/$M=/}" >> $POSTLOGFILE
        fi 
    done

	#eval job directly but write to logfile
	if [ -n "$DIRECT" ]; then eval $POSTCOMMAND2 > $POSTLOGFILE 2>&1 ; exit; fi

    # unless specified otherwise use HPC parameter from main job 
    if [ -z "$POSTNODES" ];    then POSTNODES=$NODES; fi
    if [ -z "$POSTCPU" ];      then POSTCPU=$CPU; fi
    if [ -z "$POSTMEMORY" ];   then POSTMEMORY=$MEMORY; fi
    if [ -z "$POSTWALLTIME" ]; then POSTWALLTIME=$WALLTIME; fi


    if [ -n "$MYJOBIDS" ]; then
		echo -e "[NOTE] wait for $MYJOBIDS"
        RECIPT=$($BINQSUB -a "$QSUBEXTRA" -W "$MYJOBIDS" -k $CONFIG -m $POSTMEMORY -n $POSTNODES -c $POSTCPU -w $POSTWALLTIME \
    	   -j $TASK'_'postcommand -o $POSTLOGFILE --command "$POSTCOMMAND2")
    else 
        RECIPT=$($BINQSUB -a "$QSUBEXTRA" -k $CONFIG -m $POSTMEMORY -n $POSTNODES -c $POSTCPU -w $POSTWALLTIME \
    	   -j $TASK'_'postcommand -o $POSTLOGFILE --command "$POSTCOMMAND2")
    fi    	

    echo -e "Jobnumber $RECIPT"

    fi
fi

# remove job list of this rounds files
if [ ! -n "$KEEP" ] && [ -e $QOUT/$TASK/runnow.tmp ]; then  rm $QOUT/$TASK/runnow.tmp ; fi
