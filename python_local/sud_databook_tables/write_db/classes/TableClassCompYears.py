import pandas as pd

from .TableClass import TableClass
from common.utils.calc_comparisons import calc_comparisons

class TableClassCompYears(TableClass):
    """
    TableClassCompYears to inherit all attributes/methods from TableClass to use some basic methods. 
    Must be initialized with current and prior year prepped dfs to write specific numbers for both years and comparisons to given G table

    """
    
    def __init__(self, prepped_df, prepped_df_p, workbook, sheet_num, write_cols):
        """
        Initialize with params:
            prepped_df df: current year prepped df
            prepped_df_p df: prior year prepped df
            workbook excel obj: template to write to
            sheet_num str: sheet number from G tables to write to
            write_cols list: list of cols to write both years to table, assumes first col will NOT have diff calculated

        """

        self.prepped_df = prepped_df
        self.prepped_df_p = prepped_df_p
        self.workbook = workbook
        self.sheet_num = sheet_num
        self.base_cols, self.comp_cols = [write_cols.pop(0)], write_cols
        
        # assign scol, excel_cols to specify cols to write to sheet

        self.scol = 2
        self.excel_cols = [f"{col}_{suffix}" for col in self.base_cols + self.comp_cols for suffix in ['py','cy']] + [f"{col}_diff" for col in self.comp_cols]


    def prep_for_tables(self):
        """
        Method prep_for_tables to create prepped df (comparisons dfs), pull sheet name from Excel template, and
        assign to class attributes

        """

        keep_cols = ['state'] + self.base_cols + self.comp_cols

        self.prepped_df = calc_comparisons(data1 = self.prepped_df[keep_cols], data2 = self.prepped_df_p[keep_cols], 
                                           join_on = 'state', diff_types = 'raw', join_suffixes = ('_cy','_py'), fill_na='.')

        self.sheet_name = self.get_sheet_name()