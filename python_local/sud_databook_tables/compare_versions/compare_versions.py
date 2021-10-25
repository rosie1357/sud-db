"""
Stand-alone script to compare old (SAS DDE) and new (python) versions of tables
"""

from pathlib import Path
import pandas as pd
import argparse
from datetime import date

from common.utils.params import STATE_LIST, DIR_MAIN, OUTDIR, LOGDIR, DATE_NOW
from common.utils.general_funcs import generate_logger, print_to_log

# assign old and new table paths

DIR_OLD = lambda year: DIR_MAIN(year) / 'Output'
DIR_NEW = lambda year: DIR_MAIN(year) / 'Output'

TABLE_OLD = 'SUD DB Tables (2020) - 2021-07-02.xlsx'
TABLE_NEW = 'SUD DB Tables (2020) - 2021-07-30.xlsx'

# function to return name of Excel file given excel wb object

get_file_name = lambda workbook: Path(workbook.__dict__['io']).name

def prep_values(x):
    """
    Function prep_values to read in specific variable and prep for comparisons:
        - replace trailing space from DS cells (added in base version)
        - round numerics to 2 decimal places for comparisons

    params:
        x str/num: specific cell value

    returns:
        x str/num: prepped value

    """
    
    if str(x).strip() == 'DS':
        return 'DS'
    
    elif type(x) == float:
        return round(x,2)
    
    else:
        return x

def read_sheet(excel_obj, sheetname):
    """
    Function read_sheet to read in specific excel sheet and prep for comparisons
    params:
        excel_obj excel obj: excel object to read
        sheetname str: name of sheet to read

    returns:
        df: df with prepped sheet

    """

    # read in sheet, replace periods with nan, set first column (state names) as index with asterisks removed
    
    df = pd.io.excel.ExcelFile.parse(excel_obj, sheetname, na_values=['.', '. '], verbose=True)
    
    df.iloc[:,0] = df.iloc[:,0].apply(lambda x: str(x).replace('*',''))
    
    df.set_index(df.iloc[:,0], inplace=True)
    df.index.rename(sheetname, inplace=True)
    df.drop(columns=[df.columns[0]], inplace=True)

    # rename columns with generic col_# name, drop any completely null cols

    df.columns = [f"col_{i}" for i in range(1,len(df.columns)+1)]
    df.dropna(axis=1, how='all', inplace=True)
    
    # prep values for comparisons:
    # - replace trailing space from DS cells (added in base version)
    # - round numerics to 2 decimal places for comparisons
    
    df = df.applymap(prep_values)

    # return df with overall/state rows only
    
    return df[df.index.isin([value for value in df.index if value in STATE_LIST])]
    

def comp_tables(sheetname, log, base_excel_obj, comp_excel_obj):
    """
    Function comp_tables to read in specific sheet on two Excel file to run pd.compare and print results to log
    params:
        sheetname str: sheet name to read
        log logger obj: log to write results to
        base_excel_obj excel obj: base excel object to read sheet from
        comp_excel_obj excel obj: comparison excel object to read sheet from

    returns:
        none (prints to log)

    """

    log.info(f"\n{sheetname}")
    
    base_df = read_sheet(base_excel_obj, sheetname)
    comp_df = read_sheet(comp_excel_obj, sheetname)
    
    diff_df = base_df.compare(comp_df)
    
    if diff_df.shape[0]==0:
        log.info('--All equal!\n')
        
    else:
        log.info('--NOT all equal!')
        print_to_log(log = log, message = 'Differences', records = diff_df, print_index=True)
    
def main(args=None):

    # add cli args and extract

    parser = argparse.ArgumentParser()

    parser.add_argument('--year', required=True)

    # extract arguments from parser
    
    args = parser.parse_args()

    year = args.year

    # generate log

    log = generate_logger(logdir=LOGDIR(year), logname = f"compare_db_versions_{DATE_NOW}.log")

    # define old and new workbooks

    workbook_old = pd.ExcelFile(DIR_OLD(year) / TABLE_OLD)
    workbook_new = pd.ExcelFile(DIR_NEW(year) / TABLE_NEW)

    # generate series with sheet names 

    sheets_df = pd.Series(workbook_old.sheet_names)

    # run comp_tables on each sheet

    log.info(f"Comparison of tables: {get_file_name(workbook_old)} vs {get_file_name(workbook_new)}")
            
    sheets_df.apply(comp_tables, log=log, base_excel_obj = workbook_old, comp_excel_obj = workbook_new)