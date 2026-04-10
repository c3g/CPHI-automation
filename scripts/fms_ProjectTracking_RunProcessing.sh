#!/bin/bash
set -e -o pipefail

usage() {
    echo "script usage: ProjectTracking_RunProcessing.sh -h [-r runfolder] [-l lane] [-s sample] [-x xsample]"
    echo "Usage:"
    echo " -h                               Display this help message."
    echo " -r <runfolder>                   RunFolder found in abacus under /lb/robot/research/freezeman-processing/<sequencer>/<year>/<runfolder>."
    echo " -d <destination>                 Destination of the transfer (sd4h)."
    echo " -l <lane>                        Lane(s) to be ingested (default: all)."
    echo " -s <sample>                      Sample Name(s) (as they appear in the json file from Freezeman) (default: all)."
    echo " -x <xsample>                     Sample Name(s) to be EXCLUDED (as they appear in the json file from Freezeman) (default: none)."
    exit 1                      
    }

while getopts 'hr:d::l::s::x:' OPTION; do
    case "$OPTION" in
      r)
        runfolder="$OPTARG"
        ;;
      d)
        destination="$OPTARG"
        ;;
      n)
        nucleic_acid_type="$OPTARG"
        ;;
      l)
        lane+=("$OPTARG")
        ;;
      s)
        sample+=("$OPTARG")
        ;;
      x)
        xsample+=("$OPTARG")
        ;;
      h)
        usage
        ;;
      ?)
        usage
        ;;
    esac
done

run_processing2json_args=""
transfer_args=""
if declare -p lane >&/dev/null; then
    run_processing2json_args="${run_processing2json_args} -l ${lane[*]}"
fi
if declare -p sample >&/dev/null; then
    run_processing2json_args="${run_processing2json_args} -s ${sample[*]}"
fi
if declare -p xsample >&/dev/null; then
    run_processing2json_args="${run_processing2json_args} -x ${xsample[*]}"
    transfer_args="-x ${xsample[*]}"
fi

export MUGQIC_INSTALL_HOME=/cvmfs/soft.mugqic/CentOS6
export MUGQIC_INSTALL_HOME_DEV=/lb/project/mugqic/analyste_dev
module use "$MUGQIC_INSTALL_HOME/modulefiles" "$MUGQIC_INSTALL_HOME_DEV/modulefiles"

##################################################
# Initialization
#module purge
# module load mugqic/python/3.12.2

#source ~/project_tracking_cli/venv/bin/activate

path=/lb/project/mugqic/projects/mjaniak/PCGL/cphi_project_tracking #TMP

cd $path

## Prepare run list
folder_prefix=/lb/robot/research/freezeman-processing
input=$(find "$folder_prefix"/*/*/ -maxdepth 1 -type d -name "$runfolder")
echo "-> Processing $runfolder..."

TIMESTAMP=$(date +%FT%H.%M.%S)

if [ -s "$input"  ]; then
    run_processing_json=$path/pt_jsons/$runfolder.json
    # Json creation from run validation file
    ~/CPHI-automation/scripts/fms_run_processing2json.py $run_processing2json_args --input $input --output $run_processing_json

    chmod 664 "$run_processing_json"

    # TBD for CPHI - do we need this?
    # Sample check before ingestion: make sure sample name is correct aka an existing one is not renamed
    # ~/moh_automation/pt_check_sample.sh -i $run_processing_json
    ret="$(pt-cli ingest run_processing --input-json $run_processing_json 2>&1 || true)"
    echo -e "$ret" | tee "${run_processing_json/.json/_${TIMESTAMP}_run_processing_ingestion.log}"
    if ! [[ $ret == *"has to be unique"*  ]] && [[ $ret == *"BadRequestError"*  ]]; then
        exit 1
    fi
else
    echo "--> ERROR: Missing folder $folder_prefix/*/*/$runfolder"
    exit 1
fi

# transfer cram, crais, and dragen tars to CPHI collection on SD4H
echo "Transfer started towards $destination. See log file ${run_processing_json/.json/_${destination}_${TIMESTAMP}_transfer.log}"
~/CPHI-automation/scripts/fms_transfer_RunProcessing.sh -r "$run_processing_json" -d "$destination" "$transfer_args" > "${run_processing_json/.json/_${destination}_${TIMESTAMP}_transfer.log}"
