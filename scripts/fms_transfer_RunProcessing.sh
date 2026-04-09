#!/usr/bin/env bash

THIS_SCRIPT=$(basename "$0")

usage() {
    echo "script usage: $THIS_SCRIPT -h [-r run_processing_json] [-d destination] [-x xsample]"
    echo "Usage:"
    echo " -h                           Display this help message."
    echo " -r <run_processing_json>     Run Processing json."
    echo " -d <destination>             Destination for the transfer."
    echo " -x <xsample>                 Sample Name(s) to be EXCLUDED (as they appear in the json file from Freezeman) (default: none)."
    exit 1
    }

while getopts 'hr:d::x:' OPTION; do
    case "$OPTION" in
        r)
            run_processing_json="$OPTARG"
            ;;
        d)
            destination="$OPTARG"
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

# mandatory arguments
if [ ! "$run_processing_json"  ] || [ ! "$destination"  ]; then
    echo -e "ERROR: Missing mandatory argument -r and/or -d.\n"
    usage
fi

if ! [[ $destination =~ sd4h ]]; then
    echo -e "ERROR: Invalid destination: '$destination'. It has to be sd4h.\n"
    usage
fi

GLOBUS_EP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/globus_collections.json"

destination_lowercase="${destination,,}"

DEST_EP=$(jq -r --arg dest "$destination_lowercase" '.globus_endpoints[$dest].uuid' "$GLOBUS_EP")
DEST_LOC=$(jq -r '.project_name' "$run_processing_json")

# Abacus Endpoint
ABA_EP='01389a74-7832-499b-8226-c6ff10d69731'
SRC_BASE_PATH="/lb/robot/research/freezeman-processing"

runfolder=$(jq -r '.run_name' "$run_processing_json")
run_id=$(jq -r '.run_ext_id' "$run_processing_json")

TRANSFER_DIR='/lb/project/mugqic/projects/mjaniak/PCGL/cphi_project_tracking/transfer_cphi'
TRANSFER_JSON_DIR='/lb/project/mugqic/projects/mjaniak/PCGL/cphi_project_tracking/transfer_jsons'
TIMESTAMP=$(date +%FT%H.%M.%S)
LOGFILE="${runfolder}_${TIMESTAMP}_${destination}_transfer.log"
LISTFILE="${runfolder}_${TIMESTAMP}_${destination}_transfer.list"
timestamp_start=$(date "+%Y-%m-%dT%H.%M.%S")

touch "$TRANSFER_DIR/$LOGFILE"
touch "$TRANSFER_DIR/$LISTFILE"
echo "Log file of transfer from Abacus to $destination" > "$TRANSFER_DIR/$LOGFILE"

jq -r '
    .specimen[]?.sample[]? | 
    .sample_name as $sample_name | 
    .readset[]? | 
    .readset_lane as $readset_lane | 
    .file[]? |
    select(.location_uri != null) | 
    "\($sample_name) \($readset_lane) \(.location_uri | sub("^abacus://"; ""))"
' "$run_processing_json" | while read -r sample_name readset_lane file; do
    if [[ "$xsample" == *"$sample_name"* ]]; then
        echo "Skipping ${sample_name}..."
    else
        file_basename=$(basename "$file")
        if [[ $file == *.dragen_outputs.tar.gz && "$file" != *"${run_id}_L00${readset_lane}.dragen_outputs.tar.gz" ]]; then
            file_basename=$(basename "$file" .dragen_outputs.tar.gz)
            new_filename=${file_basename}_${run_id}_L00${readset_lane}.dragen_outputs.tar.gz
            echo "$file $DEST_LOC/$sample_name/$new_filename" >> "$TRANSFER_DIR/$LISTFILE"
            echo "$file,$sample_name/$new_filename" >> "$TRANSFER_DIR/$LOGFILE"
        else
            echo "$file $DEST_LOC/$sample_name/$file_basename" >> "$TRANSFER_DIR/$LISTFILE"
            echo "$file,$sample_name/$file_basename" >> "$TRANSFER_DIR/$LOGFILE"
        fi
    fi
done

module load mugqic/globus-cli/3.24.0
# Generate and store a UUID for the submission-id
sub_id="$(globus task generate-submission-id)"

# Start the batch transfer
task_id="$(globus transfer --sync-level mtime --jmespath 'task_id' --format=UNIX --submission-id "$sub_id" --label "$runfolder" --batch "$TRANSFER_DIR/$LISTFILE" $ABA_EP $DEST_EP)"

echo -e "Waiting on 'globus transfer' task '$task_id'.\nTo monitor the transfer see: https://app.globus.org/activity/$task_id/overview"
globus task wait "$task_id" --polling-interval 60 -H

if [ $? -eq 0  ]; then
    TRANSFER_JSON="$TRANSFER_JSON_DIR/${LISTFILE/.list/.json}"
    module unload mugqic/globus-cli/3.24.0
    timestamp_end=$(date "+%Y-%m-%dT%H.%M.%S")
    ~/CPHI-automation/scripts/transfer2json.py --input $TRANSFER_DIR/$LISTFILE --source "abacus" --destination $destination --output $TRANSFER_JSON --operation_cmd_line "globus transfer --sync-level mtime --jmespath 'task_id' --format=UNIX --submission-id ${sub_id} --label $runfolder --batch $TRANSFER_DIR/$LISTFILE $ABA_EP $DEST_EP" --start $timestamp_start --stop $timestamp_end
    echo "Ingesting transfer $TRANSFER_JSON..."
    pt-cli ingest transfer --input-json $TRANSFER_JSON
else
    echo "$task_id failed!"
fi
