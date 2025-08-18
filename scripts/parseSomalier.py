#!/usr/bin/env python

import csv
import getopt
import json
import os
import sys

# read somalier output, keep samples with matches above 80 percent. Populate json.

def getarg(argument):
    json_file=""
    somalier=""
    optli,arg = getopt.getopt(argument[1:],"j:s:h",['json_file','somalier_file','help'])
    if len(optli) == 0 :
        usage()
        sys.exit("Error : No argument given")
    for option, value in optli:
        if option in ("-j","--json_file"):
            json_file=str(value)
        if option in ("-s","--somalier_file"):
            somalier_file=str(value)
        if option in ("-h","--help"):
            usage()
            sys.exit()
    if not json_file:
        sys.exit("Error - json_file parameter is required")
    elif json_file and not os.path.exists(json_file):
        sys.exit("Error - JSON index stats file not found:\n" + str(json_file))
    if not somalier_file:
        sys.exit("Error - somalier_file parameter is required")
    elif somalier_file and not os.path.exists(somalier_file):
        sys.exit("Error - Somalier relate pairs file not found:\n" + str(somalier_file))

    return json_file, somalier_file

def parse_somalier(somalier_file):
    data = []
    with open(somalier_file, 'r') as somalier_fh:
        reader = csv.reader(somalier_fh, delimiter="\t")
        next(reader)
        for row in reader:
            if float(row[2]) >= 0.8:
                data.append(row[0:14])

    genotype_matches = []
    for l in data:
        genotype_matches.append([l[0], l[1], l[2], l[13]])
        genotype_matches.append([l[1], l[0], l[2], l[13]])

    return genotype_matches

def update_json(json_file, genotype_matches):    
    """
    If genotype matches were found, update the report json.
    """
    with open(json_file, 'r') as json_fh:
        run_report_json = json.load(json_fh)
        for sample in run_report_json['samples']:
            matches = {}
            for l in genotype_matches:
                if sample == '_'.join(l[0].split("_")[1:]):
                    matches[l[1]] = {
                            "sample_name" : '_'.join(l[1].split('_')[1:-1]),
                            "biosample_id" : l[1].rsplit('_', 1)[-1],
                            "plate_barcode" : l[1].split("_")[0],
                            "percent_match" : float(l[2]) * 100,
                            "n_sites" : int(l[3])
                            }
            run_report_json['samples'][sample]["genotype_matches"] = matches if len(matches) > 0 else None

    with open(json_file, 'w') as out_json:
        json.dump(run_report_json, out_json, indent=4)

def main():
    json_file, somalier_file = getarg(sys.argv)
    
    genotype_matches = parse_somalier(somalier_file)

    if len(genotype_matches) > 0:
        update_json(json_file, genotype_matches)
        print(f"""Updated {json_file} with genotype matches from {somalier_file}""")
    
    else:
        print(f"""No samples in {somalier_file} matched, no updates to {json_file} required.""")

def usage():
    print("\n-------------------------------------------------------------------------------------")
    print("parseSomalier.py" )
    print("This program was written by Mareike Janiak")
    print("For more information, contact: mareike.janiak@computationalgenomics.ca")
    print("----------------------------------------------------------------------------------\n")
    print("USAGE : parseSomalier.py")
    print("    -j    JSON file to be updated")
    print("    -s    somalier pairs file to be parsed")
    print("    -h    this help\n")

if __name__ == '__main__':
    main()
