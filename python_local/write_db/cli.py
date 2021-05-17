"""
cli script to run write_db_tables from command line 
"""

import os
import argparse
import logging
import openpyxl as xl
from pathlib import Path

from .utils.params import LOGDIR, LOGNAME, SPECDIR, SHELL, OUTDIR, OUTFILE
from .utils.general_funcs import read_config, get_current_path, generate_logger
from .gen_tables import gen_tables

def main(args=None):
    
    # add cli args and extract

    parser = argparse.ArgumentParser()

    parser.add_argument('--year', required=True)
    parser.add_argument('--version', required=True)

    # extract arguments from parser

    args = parser.parse_args()
    YEAR, VERSION = args.year,  args.version

    # read in measures config file to get dictionary with details to run each table

    CONFIG = read_config(config_dir = get_current_path(sub_dirs = 'write_db/utils'))
    table_details = CONFIG['TABLE_MAPPINGS']

    # set up log
    
    log = generate_logger(logdir = LOGDIR(YEAR), logname = LOGNAME(YEAR), 
                          init_message = f"Creation of SUD DB tables")

    # open shell

    workbook = xl.load_workbook(SPECDIR(YEAR) / SHELL)

    # call gen_tables to do all processing

    gen_tables(year = YEAR, version = VERSION, workbook = workbook, table_details = table_details)

    # save table

    workbook.save(OUTDIR(YEAR) / OUTFILE(YEAR))



    