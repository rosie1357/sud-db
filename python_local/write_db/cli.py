"""
cli script to run write_db_tables from command line 
"""

import os
import argparse
import logging
import openpyxl as xl
from pathlib import Path

from .utils.params import LOGDIR, LOGNAME

def main(args=None):
    
    # add cli args and extract

    parser = argparse.ArgumentParser()

    parser.add_argument('--year', required=True)
    parser.add_argument('--version', required=True)

    # extract arguments from parser

    args = parser.parse_args()
    YEAR, VERSION = args.year,  args.version

    # read in measures config file to get dictionary with all needed lists

    MEASURES = read_config(config_dir = get_current_path(sub_dirs = 'write_db/utils'))

    # set up log
    
    log = generate_logger(logdir = LOGDIR, logname = LOGNAME, 
                          init_message = f"Creation of SUD DB tables")

    