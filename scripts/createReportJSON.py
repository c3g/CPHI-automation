#!/usr/bin/env python

import csv
import json
import getopt
import re
import sys
import os

# read fluidigm csv and create json with run barcode, samples, positions, and fields for predicted sex, and somalier matches

def getarg(argument):
    fluidigm_file=""
    json_file=""
    optli,arg = getopt.getopt(argument[1:],"f:o:h",['fluidigm_file','output_dir','help'])
    if len(optli) == 0 :
        usage()
        sys.exit("Error : No argument given")
    for option, value in optli:
        if option in ("-f","--fluidigm_file"):
            fluidigm_file=str(value)
        if option in ("-o","--output_dir"):
            output_dir=str(value)
        if option in ("-h","--help"):
            usage()
            sys.exit()
    if not output_dir:
        sys.exit("Error - output_dir parameter is required")
    if not fluidigm_file:
        sys.exit("Error - fluidigm_file parameter is required")
    elif fluidigm_file and not os.path.exists(fluidigm_file):
        sys.exit("Error - Fluidigm SNP array file not found:\n" + str(fluidigm_file))

    return fluidigm_file, output_dir

def parse_fluidigm(fluidigm_file):
    """
    Parse fluidigm output to get run barcode and samples in run.
    """
    data = []
    
    with open(fluidigm_file, 'r') as csv_file:
        reader = csv.reader(csv_file)
        for row in reader:
            data.append(row)

    barcode = data[0][2]
    sample_data = data[16:]

    return barcode, sample_data

def create_json(sample_data, barcode, json_file):
    """
    Create report hash and write to json.
    """
    report_hash = {
            "barcode" : barcode,
            "instrument": "fluidigm",
            "samples" : dict(
                [
                    (
                        row[4],
                        {
                            "sample_name" : '_'.join(row[4].split('_')[:-1]),
                            "biosample_id" : row[4].rsplit('_', 1)[-1],
                            "sample_position" : re.sub("S", "", row[0].split("-")[0]),
                            "passed" : None,
                            "fluidigm_predicted_sex" : None,
                            "genotype_matches" : None
                        }
                    ) for row in [sample_data if row[5] != "NTC"]
                ]
                )
            }

    with open(json_file, 'w') as out_json:
        json.dump(report_hash, out_json, indent=4)

def main():
    fluidigm_file, output_dir = getarg(sys.argv)
    
    barcode, sample_data = parse_fluidigm(fluidigm_file)
    
    json_file = os.path.join(output_dir, f"report.fluidigm.{barcode}.json")

    create_json(sample_data, barcode, json_file)

    print(f"""Created report json {json_file} for run {barcode} from file {fluidigm_file}.""")

def usage():
    print("\n-------------------------------------------------------------------------------------")
    print("createReportJSON.py" )
    print("This program was written by Mareike Janiak")
    print("For more information, contact: mareike.janiak@computationalgenomics.ca")
    print("----------------------------------------------------------------------------------\n")
    print("USAGE : createReportJSON.py")
    print("    -f    fluidigm file to be parsed")
    print("    -o    dir where report json will be written")
    print("    -h    this help\n")

if __name__ == '__main__':
    main()
