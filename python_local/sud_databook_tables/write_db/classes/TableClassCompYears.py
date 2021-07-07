import pandas as pd

from .TableClass import TableClass
from common.utils.calc_comparisons import calc_comparisons

class TableClassCompYears(TableClass):
    """
    TableClassCompYears to inherit all attributes/methods from TableClass to use some basic methods.
    Must be initialized with current and prior year prepped dfs to write either all numerators or all stats and comparisons to comparison sheet

    """
    
    def __init__(self, _tableclass, prepped_df_p, workbook):
        """
        Initialize with params:
            _tableclass instance of TableClass: current year TableClass instance
            prepped_df_p df: prior year prepped df
            workbook excel obj: template to write to

        """

        self._tableclass = _tableclass
        self.prepped_df_p = prepped_df_p
        self.workbook = workbook
        self.sheet_name = _tableclass.sheet_num
        
        # assign scol, specific cols to create comparisons for

        self.scol = 2

        if self._tableclass.comparison_value in ['pct','avg']:

            stat_cols = [col for col in self._tableclass.excel_cols if col.endswith('stat')]

        elif self._tableclass.comparison_value == 'numerators':

            stat_cols = self._tableclass.numerators

        # assign cols to write to excel (write pctdiff for denom for all tables, for pct write raw diff for all comp cols otherwise write pctdiff)

        if self._tableclass.comparison_value == 'pct':
            diff_type = 'diff'
        else:
            diff_type = 'pctdiff'

        self.excel_cols = [f"{col}_{suffix}" for col in self._tableclass.big_denom for suffix in ['py','cy', 'pctdiff']] + \
             [f"{col}_{suffix}" for col in stat_cols for suffix in ['py','cy', diff_type]]

        # create comp_cols (denom + stat_cols)

        self.comp_cols = self._tableclass.big_denom + stat_cols

        # create prepped df to write to tables

        self.prep_for_tables()


    def prep_for_tables(self):
        """
        Method prep_for_tables to create prepped df (comparisons dfs)

        """

        keep_cols = ['state'] + self.comp_cols

        self.prepped_df = calc_comparisons(data1 = self._tableclass.prepped_df[keep_cols], data2 = self.prepped_df_p[keep_cols], 
                                           join_on = 'state', diff_types = 'both', join_suffixes = ('_cy','_py'), fill_na='.')