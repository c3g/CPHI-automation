#!/bin/bash
set -e -o pipefail

usage() {
    echo "script usage: ProjectTracking_RunProcessing.sh -h [-t trackingfolder]"
    echo "Usage:"
    echo " -h                       Display this help message."
    echo " -t <trackingfolder>      Project tracking folder that contains subfolder with pt and transfer jsons."
    exit 1
    }

while getopts 'ht:' OPTION; do
    case "$OPTION" in
    t)
      trackingfolder="$OPTARG"
      ;;
    h)
      usage
      ;;
    ?)
      usage
      ;;
    esac
done

export MUGQIC_INSTALL_HOME=/cvmfs/soft.mugqic/CentOS6
module use "$MUGQIC_INSTALL_HOME/modulefiles"

if [ -s "$input"  ]; then
    TRANSFER_PATH=$trackingfolder
else
    echo "Error incorrect number of command line arguments."
    echo "Usage: $(basename $0) -t <transfer_dir>"
    exit 1
fi
########################################################
# Set file paths
REPORT_PATH=/lb/project/mugqic/projects/mjaniak/PCGL/cphi_project_tracking/summary_reports

########################################################
## Look for transfer jsons and summarize
TIMESTAMP=$(date '+%Y-%m-%d')

module purge && module load mugqic/python/3.12.2
TOTAL_TRANSFERRED=$(~/CPHI-automation/scripts/transferReport.py -i ${TRANSFER_PATH} -o ${REPORT_PATH}/NRGI_CPHI_processed_${TIMESTAMP}) 
TOTAL_PROCESSED=$(tail -n +2 ${REPORT_PATH}/NRGI_CPHI_processed_${TIMESTAMP}.tsv | wc -l)

SUMMARY=$(tail -n 1 ${REPORT_PATH}/NRGI_CPHI_processed_${TIMESTAMP}_transfer_summary.tsv | tr -d '\r')

module unload mugqic/python/3.12.2

echo """Weekly update for project NRGI_CPHI.
As of ${TIMESTAMP} a total of ${TOTAL_PROCESSED} samples have been processed. Of those, a total of ${TOTAL_TRANSFERRED} have been transferred.

Number of samples transferred during most recent month (may be ongoing):
"${SUMMARY}"

A file detailing all samples processed so far and a summary by month are attached to this email.                                                        
                                                        
This is an automated email, please do not respond.""" | mailx -s "NRGI_CPHI weekly report ${TIMESTAMP}" -a ${REPORT_PATH}/NRGI_CPHI_processed_${TIMESTAMP}_transfer_summary.tsv -a ${REPORT_PATH}/NRGI_CPHI_processed_${TIMESTAMP}.tsv -r abacus.genome@mail.mcgill.ca "mareike.janiak@computationalgenomics.ca" "jose.galvezlopez@mcgill.ca" "antoine.paccard@mcgill.ca"

echo "notification sent"
