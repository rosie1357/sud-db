"""
cli script to run write_db_tables from command line 
"""

import os
import argparse
import openpyxl as xl
from pathlib import Path

from common.utils.params import SPECDIR, SHELL, SHELL_OUD, OUTDIR, OUTFILE, OUTFILE_OUD
from common.utils.general_funcs import variable_matcher, variable_constructor, read_config, get_current_path
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

    CONFIG = read_config(config_dir = get_current_path(sub_dirs = 'sud_databook_tables/write_db/config'), variable_match = {'matcher' : variable_matcher, 'constructor' : variable_constructor})

    table_details = CONFIG['TABLE_MAPPINGS']

    # open shells (regular and OP/OUD)

    workbook = xl.load_workbook(SPECDIR(YEAR) / SHELL)
    workbook_oud = xl.load_workbook(SPECDIR(YEAR) / SHELL_OUD)

    # call gen_tables to do all processing for both sets of tables (regular and OP/OUD)

    gen_tables(year = YEAR, version = VERSION, workbook = workbook, table_details = table_details, config_sheet_num='sheet_num_sud', table_type='SUD')
    gen_tables(year = YEAR, version = VERSION, workbook = workbook_oud, table_details = table_details, config_sheet_num='sheet_num_op', table_type='OUD')

    # save tables

    workbook.save(OUTDIR(YEAR) / OUTFILE(YEAR))
    workbook_oud.save(OUTDIR(YEAR) / OUTFILE_OUD(YEAR))