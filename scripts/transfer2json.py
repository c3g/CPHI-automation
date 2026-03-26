#!/usr/bin/env python3

import argparse
import glob
import json
import os
import logging

logging.basicConfig(format='%(levelname)s: %(asctime)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# what is the purpose of this?
PREFIX_OFFSETS = {
        "/lb/robot/research/freezeman-processing/novaseqx/2": 0
        }

def main():
    """ Main """
    parser = argparse.ArgumentParser(prog='transfer2json.py', description="Creates json file for project tracking database for a given transfer of data.")
    parser.add_argument('-i', '--input', required=True, help="Batch file from Globus.")
    parser.add_argument('-s', '--source', required=True, help="Source cluster of the transfer.")
    parser.add_argument('-d', '--destination', required=True, help="Cluster of destination for the transfer.")
    parser.add_argument('-o', '--output', required=False, help="Output json filename (Default: <input_filename>.json).")
    parser.add_argument('--start', required=False, help="Start time of operation (format: YYYY-MM-DDTHH.MM.SS).")
    parser.add_argument('--stop', required=False, help="End time of operation (format: YYYY-MM-DDTHH.MM.SS).")
    parser.add_argument('--operation_cmd_line', required=True, help="Command used for transfer.")
    parser.add_argument('--delivery', required=False, help="Delivery json file.")
    args = parser.parse_args()

    if not args.output:
        base_name, _ = os.path.splitext(args.input)
        output = os.path.basename(base_name) + ".json"
    else:
        output = args.output

    if args.delivery:
        jsonify_delivery_transfer(
                batch_file = args.input,
                source = args.source,
                destination = args.destination.lower(),
                delivery_json = args.delivery,
                output = output,
                operation_cmd_line = args.operation_cmd_line,
                start = args.start,
                stop = args.stop                                                                                                          
                )
    else:
        jsonify_run_processing_transfer(
                batch_file = args.input,
                source = args.source,
                destination = args.destination.lower(),
                output = output,
                operation_cmd_line = args.operation_cmd_line,
                start = args.start,
                stop = args.stop
                )

def jsonify_delivery_transfer(batch_file, source, destination, delivery_json, output, operation_cmd_line, start=None, stop=None):
    """Writing transfer json based on json delivery file"""
    with open(deliver_json, 'r') as json_file:
        delivery_json = json.load(json_file)
    delivery_file_by_location = {}
    delivery_file_by_name = {}

    def _append_unique_readset(mapping, key, readset_name):
        if key not in mapping:
            mapping[key] = [readset_name]
        elif readset_name not in mapping[key]:
            mapping[key].append(readset_name)

    for specimen in delivery_json['specimen']:
        for sample in specimen['sample']:
            for readset in sample['readset']:
                readset_name = readset['name']
                for file in readset['file']:
                    file_name = file.get('name')
                    file_location = file.get('location')

                    if file_name:
                        _append_unique_readset(delivery_file_by_name, file_name, readset_name)
                    if file_location:
                        normalized_location = os.path.normpath(file_location)
                        _append_unique_readset(delivery_file_by_location, normalized_location, readset_name)

    start = start.replace('.', ':').replace('T', ' ') if start else None
    stop = stop.replace('.', ':').replace('T', ' ') if stop else None
    json_output = {
            "operation_platform": source,
            "operation_cmd_line": operation_cmd_line,
            "job_start": start,
            "job_stop": stop,
            "readset": []
            }
    with open(batch_file, 'r') as file:
        for line in file:
            fields = line.split()
            if len(fields) < 2:
                continue

            src_path = os.path.normpath(fields[0])
            src_location_uri = f"{source}://{fields[0]}"
            dest_location_uri = f"{destination}://{fields[1].strip()}"
            current_file = os.path.basename(fields[0])

            readset_names = delivery_file_by_location.get(src_path, [])

            # Backward compatibility: fallback to filename only when unambiguous
            if not readset_names:
                name_matches = delivery_file_by_name.get(current_file, [])
                if len(name_matches) == 1:
                    readset_names = name_matches
                elif len(name_matches) > 1:
                    logger.warning(
                            "Ambiguous delivery filename '%s' (multiple readsets) without location match for '%s'; skipping.",
                            current_file,
                            src_path
                            )
                    continue

            for readset_name in readset_names:
                _append_file(json_output, readset_name, src_location_uri, dest_location_uri)

    with open(output, 'w', encoding='utf-8') as file:
        json.dump(json_output, file, ensure_ascii=False, indent=4)

   
def _matched_prefix(line: str):
    """Return the matched prefix or None if not matched."""
    for pfx in PREFIX_OFFSETS.keys():
        if line.startswith(pfx):
            return pfx
    return None

def _append_file(json_output, readset_name, src_location_uri, dest_location_uri):
    """Append a file entry to an existing readset or create a new one."""
    for readset in json_output["readset"]:
        if readset["readset_name"] == readset_name:
            readset["file"].append(
                    {
                        "src_location_uri": src_location_uri,
                        "dest_location_uri": dest_location_uri
                    }
                )
            return
        #Not found: create new
    json_output["readset"].append(
            {
                "readset_name": readset_name,
                "file": [
                    {
                        "src_location_uri": src_location_uri,
                        "dest_location_uri": dest_location_uri
                    }
                ]
            }
        )

def jsonify_run_processing_transfer(batch_file, source, destination, output, operation_cmd_line, start=None, stop=None):
    """Writing transfer json based on batch file with path-index offsets per prefix."""
    start = start.replace('.', ':').replace('T', ' ') if start else None
    stop = stop.replace('.', ':').replace('T', ' ') if stop else None

    json_output = {
            "operation_platform": source,
            "operation_cmd_line": operation_cmd_line,
            "job_start": start,
            "job_stop": stop,
            "readset": []
            }

    with open(batch_file, 'r') as file:
        for raw_line in file:
            line = raw_line.strip()
            pfx = _matched_prefix(line)
            if not pfx:
                continue

            fields = line.split()
            if len(fields) < 2:
                continue # malformed line

            src_path = fields[0]
            dest_path = fields[1]

            path_l = src_path.split('/')
            path_d = dest_path.split('/')
            offset = PREFIX_OFFSETS[pfx]

            # Build URIs once
            src_location_uri = f"abacus://{src_path}"
            dest_location_uri = f"{destination}://{dest_path.strip()}"

            if ".cram.crai" in src_path:
                try:
                    readset_name = f"{path_l[12].replace('.sorted.cram.crai', '')}"
                except IndexError:
                    continue

                _append_file(json_output, readset_name, src_location_uri, dest_location_uri)

            elif ".cram" in src_path:
                try:
                    readset_name = f"{path_l[12].replace('.sorted.cram', '')}"
                except IndexError:
                    continue

                _append_file(json_output, readset_name, src_location_uri, dest_location_uri)

            elif ".tar.gz" in src_path:
                try:
                    print(path_d)
                    readset_name = f"{path_d[2].replace('.dragen_outputs.tar.gz', '')}"
                    print(readset_name)
                except IndexError:
                    continue

                _append_file(json_output, readset_name, src_location_uri, dest_location_uri)

    with open(output, 'w', encoding='utf-8') as file:
        json.dump(json_output, file, ensure_ascii=False, indent=4)

if __name__ == '__main__':
    main()
