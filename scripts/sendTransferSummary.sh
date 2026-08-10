#!/bin/bash

# DOVEE -- FINISHED ANALYSIS MONITOR AND NOTIFIER
# check for Dovee log file that is newer than timestamp. If found, send notification.
########################################################

if [ "$#" != 1  ]
then
    echo "Error incorrect number of command line arguments."
    echo "Usage: $(basename $0) <transfer_dir>"
    exit
fi
########################################################
# Set file paths
TRANSFER_PATH=$(realpath ${1}) # where to look for transfer json files
REPORT_PATH=/lb/project/mugqic/projects/mjaniak/PCGL/cphi_project_tracking/summary_reports

########################################################
## Look for transfer jsons and summarize
TIMESTAMP=$(date '+%Y-%m-%d')

module purge && module load mugqic/python/3.12.2
TOTAL=$(~/CPHI-automation/scripts/transferReport.py -i ${TRANSFER_PATH} -o ${REPORT_PATH}/CPHI_NRGI_transferred_${TIMESTAMP}) 

SUMMARY=$(tail -n 1 ${REPORT_PATH}/CPHI_NRGI_transferred_${TIMESTAMP}_summary.tsv | tr -d '\r')

module unload mugqic/python/3.12.2

echo """Weekly update for project CPHI_NRGI.
As of ${TIMESTAMP} a total of ${TOTAL} samples have been transferred. 

Number of samples transferred during most recent month (may be ongoing):
"${SUMMARY}"

A file detailing all samples transferred so far and a summary by month are attached to this email.                                                        
                                                        
This is an automated email, please do not respond.""" | mailx -s "CPHI_NRGI weekly report ${TIMESTAMP}" -a ${REPORT_PATH}/CPHI_NRGI_transferred_${TIMESTAMP}_summary.tsv -a ${REPORT_PATH}/CPHI_NRGI_transferred_${TIMESTAMP}.tsv -r abacus.genome@mail.mcgill.ca "mareike.janiak@computationalgenomics.ca" "jose.galvezlopez@mcgill.ca" "antoine.paccard@mcgill.ca"

echo "notification sent"
