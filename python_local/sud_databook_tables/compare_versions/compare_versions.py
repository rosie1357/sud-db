from pathlib import Path
import pandas as pd

from common.utils.params import STATE_LIST, DIR_MAIN, OUTDIR, LOGDIR, DATE_NOW
from common.utils.general_funcs import generate_logger

YEAR = 2019

log = generate_logger(logdir=LOGDIR(YEAR), logname = f"compare_db_versions_{DATE_NOW}.log")

DIR_OLD = DIR_MAIN(YEAR) / 'Output'
DIR_NEW = OUTDIR(YEAR)

workbook_old = pd.ExcelFile(DIR_OLD / 'SUD DB Tables (2019) - 2020-09-23.xlsx')
workbook_new = pd.ExcelFile(DIR_NEW / 'SUD DB Tables (2019) - 2021-06-03.xlsx')

sheets_df = pd.DataFrame(workbook_old.sheet_names, columns=['sheetname'])


def prep_values(x):
    
    if str(x).strip() == 'DS':
        return 'DS'
    
    elif type(x) == float:
        return round(x,2)
    
    else:
        return x
        

def read_sheet(excel_obj, sheetname):
    
    
    df = pd.io.excel.ExcelFile.parse(excel_obj, sheetname, na_values=['.', '. '])
    
    df.iloc[:,0] = df.iloc[:,0].apply(lambda x: str(x).replace('*',''))
    
    df.set_index(df.iloc[:,0], inplace=True)
    df.drop(columns=[df.columns[0]], inplace=True)
    df.columns = [f"col_{i}" for i in range(1,len(df.columns)+1)]
    df.dropna(axis=1, how='all', inplace=True)
    
    # replace trailing space from DS cells (added in base version), round numerics to 4 decimal places for comparisons
    
    df = df.applymap(prep_values)
    
    return df[df.index.isin([value for value in df.index if value in STATE_LIST])]
    

def comp_tables(sheetname, base_excel_obj, comp_excel_obj):

    log.info(f"\n{sheetname}")
    
    base_df = read_sheet(base_excel_obj, sheetname)
    comp_df = read_sheet(comp_excel_obj, sheetname)
    
    diff_df = base_df.compare(comp_df)
    
    if diff_df.shape[0]==0:
        log.info('--All equal!\n')
        
    else:
        log.info('--NOT all equal!!! Differences below:\n')
        log.info(diff_df)
    
def main():
            
    sheets_df['match'] = sheets_df['sheetname'].apply(comp_tables, base_excel_obj = workbook_old, comp_excel_obj = workbook_new)

if __name__ == '__main__':
    main()
