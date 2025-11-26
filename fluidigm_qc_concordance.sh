#!/bin/bash

usage() {
    echo "Script to analyze and parse fluidigm SNP arrays for sex concordance and genotype checks."
    echo "script usage: fluidigm_qc_concordance.sh -h [-i input_file] [-w working_dir]"
    echo "Usage:"
    echo " -h                   Display this help message."
    echo " -i <input_file>      Input fluidigm file. A csv file created by the Fluidigm SNP Array caller."
    echo " -w <working_dir>     Path to where outputs and reports will be generated."

    exit 1
    }

while getopts 'hi::w:' OPTION; do
    case "$OPTION" in
        i)
            FLUIDIGM_CSV=$(realpath "$OPTARG")
            ;;
        w)
            RUN_DIR=$(realpath "$OPTARG")
            ;;
        h)
            usage
            ;;
        ?)
            usage
            ;;
    esac
done

if [ -z "$FLUIDIGM_CSV" ] || [ -z "$RUN_DIR" ]; then
    echo -e "ERROR: Missing mandatory arguments -i and/or -w.\n"
    usage
fi

############################################################################################
# workflow for getting somalier comparisons and fluidigm sex calls + creating json to send back to freezeman
module purge && module load mugqic/python/3.12.2 mugqic/R_Bioconductor/4.3.2_3.18 mugqic/pandoc/2.16.2 mugqic/bcftools/1.19 mugqic/htslib/1.19.1 mugqic_dev/somalier/0.2.13 && \

export SCRIPT_HOME=$(dirname $(realpath $0))
PLATE_BARCODE=$(head -n1 ${FLUIDIGM_CSV} | awk -F',' '{print $3}')
REPORTS_OUT=${RUN_DIR}/reports
OUTPUT_DIR=${RUN_DIR}/output
VCF_DIR=${OUTPUT_DIR}/fluidigm_vcf

echo -e "Parsing output of fluidigm plate ${PLATE_BARCODE}."
echo -e "Outputs and reports will be found here: ${RUN_DIR}\n\n"

# 1. json file is created with entry per sample, includes sample name & position
python $SCRIPT_HOME/scripts/createReportJSON.py \
    -f ${FLUIDIGM_CSV} \
    -o ${REPORTS_OUT} && \
echo -e "created inital JSON\n\n\n" && \

# 2. copy header vcf
cp $SCRIPT_HOME/resources/fluidigm_vcf_header.vcf ${VCF_DIR}/fluidigm.${PLATE_BARCODE}.vcf && \

# 3. run Rscript with fluidigm csv as input (appends to header vcf, turns csv into vcf while fixing strand and making bases consistent with GRCh38)
Rscript $SCRIPT_HOME/scripts/fluidigm2vcf.R \
    -i ${FLUIDIGM_CSV} \
    -o ${VCF_DIR} && \
echo -e "created VCF\n\n\n" && \

# 4. vcf is sorted and indexed (bcftools)
bcftools sort \
    -Oz ${VCF_DIR}/fluidigm.${PLATE_BARCODE}.vcf \
    -o ${VCF_DIR}/fluidigm.${PLATE_BARCODE}.sort.vcf.gz && \
tabix -p vcf ${VCF_DIR}/fluidigm.${PLATE_BARCODE}.sort.vcf.gz && \
echo -e "indexed VCF\n\n\n" && \

# 5. somalier extract (add prefix to sample name, like barcode/run_name? Would ensure unique names)
somalier extract \
    -d ${OUTPUT_DIR}/somalier/fluidigm_extracted/${PLATE_BARCODE} \
    --sample-prefix=${PLATE_BARCODE}_ \
    --sites $SCRIPT_HOME/resources/fluidigm_array_sites.vcf.gz \
    -f $MUGQIC_INSTALL_HOME/genomes/species/Homo_sapiens.GRCh38/genome/Homo_sapiens.GRCh38.fa \
    ${VCF_DIR}/fluidigm.${PLATE_BARCODE}.sort.vcf.gz && \

# 6. somalier relate (all samples in "database"), output should be named with run_name or barcode name?
somalier relate \
    -o ${OUTPUT_DIR}/somalier/relate/${PLATE_BARCODE} \
    ${OUTPUT_DIR}/somalier/fluidigm_extracted/*/*.somalier && \
echo -e "ran somalier\n\n\n" && \

# 7. Parse somalier output to identify matches, populate json with matches 
python ${SCRIPT_HOME}/scripts/parseSomalier.py \
    -j ${REPORTS_OUT}/report.fluidigm.${PLATE_BARCODE}.json \
    -s ${OUTPUT_DIR}/somalier/relate/${PLATE_BARCODE}.pairs.tsv && \

# 8. create report listing qc results, inconclusive sex calls and matches
Rscript $SCRIPT_HOME/scripts/fluidigmReport.R \
    -f $(realpath ${FLUIDIGM_CSV}) \
    -s ${OUTPUT_DIR}/somalier/relate/${PLATE_BARCODE}.pairs.tsv \
    -j ${REPORTS_OUT}/report.fluidigm.${PLATE_BARCODE}.json \
    -o ${REPORTS_OUT} && \
echo -e "\n\nparsed somalier, updated json, and created report" && \

# 9. Email with report is sent to lab/others. json is ingested into freezeman.
module purge && module load mugqic/python/3.10.2 && \
python ${SCRIPT_HOME}/scripts/freezeman_ingest.py --url https://biobank.genome.mcgill.ca/api/ --user techdevadmin --password $(cat ~/assets/.techdevadmin) --cert ~/monitor/assets/fullbundle.pem ${REPORTS_OUT}/report.fluidigm.${PLATE_BARCODE}.json && \

echo "A new fluidigm genotyping run was detected: $PLATE_BARCODE.

The results have been ingested into Freezeman and a summary report has been prepared.

Please review the attached report to see any potential issues with the samples in the run.

This is an automated notification, please do not reply." | mailx -s "Report for fluidigm $PLATE_BARCODE" -a $REPORTS_OUT/fluidigm_qc.${PLATE_BARCODE}.html -r abacus.genome@mail.mcgill.ca "mareike.janiak@computationalgenomics.ca" "ariane.boisclair@mcgill.ca" "lena.lichunfong@mcgill.ca" "jose.galvezlopez@mcgill.ca" && \
echo "Email sent"
