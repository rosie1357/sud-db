import pandas as pd

from .TableClass import TableClass
from common.utils.calc_comparisons import calc_comparisons
from common.utils.stats import two_proportions_confint

class TableClassG(TableClass):
    """
    TableClassG to inherit all attributes/methods from TableClass to use some basic methods.
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
        self.excel_cols = [f"{col}_{suffix}" for col in self.base_cols + self.comp_cols for suffix in ['py','cy']] + [f"{col}_diff" for col in self.comp_cols] + ['ci']

        # create prepped df to write to tables

        self.prep_for_tables()

    def get_stats(self):
        """
        Method get_stats to run tests on proportions to get confidence interval and pvalue and add cols to prepped_df

        """

        # get CI (returned as series of lists) and reformat to rounded tuples

        confint = self.prepped_df_pre[[self.excel_cols[2], self.excel_cols[0], self.excel_cols[3], self.excel_cols[1]]].apply(lambda x: two_proportions_confint(*x, default_exception='DS'), axis=1)

        self.prepped_df_pre['ci'] = confint.apply(lambda x: f'({"{:0.2f}".format(x[0]*100)}, {"{:0.2f}".format(x[1]*100)})' if type(x) == list else x)

        return self.prepped_df_pre

    def prep_for_tables(self):
        """
        Method prep_for_tables to create prepped df (comparisons and stat tests), pull sheet name from Excel template, and
        assign to class attributes

        """

        keep_cols = ['state'] + self.base_cols + self.comp_cols

        self.prepped_df_pre = calc_comparisons(data1 = self.prepped_df[keep_cols], data2 = self.prepped_df_p[keep_cols], 
                                               join_on = 'state', diff_types = 'raw', join_suffixes = ('_cy','_py'), fill_na='.')

        self.prepped_df = self.get_stats()

        self.sheet_name = self.get_sheet_name()