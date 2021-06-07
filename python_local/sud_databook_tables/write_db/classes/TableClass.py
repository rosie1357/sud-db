import pandas as pd

from .BaseDataClass import BaseDataClass
from ..tasks.national_values import get_national_values
from ..tasks.data_transform import convert_fips, create_stats, zero_fill_cond
from ..tasks.small_cell_suppress import small_cell_suppress, suppress_match_numer
from ..tasks.write_excel import read_template_col, write_sheet
from common.utils.text_funcs import stat_list, create_text_list
from common.utils.df_funcs import list_dup_cols
from common.utils.params import STATE_LIST


class TableClass(BaseDataClass):
    """
    TableClass to inherit from instance of BaseDataClass to get base attributes and totals df

    Must initialize with:
        args to pass to BaseDataClass
        kwargs to use for TableClass to set all attributes (variable based on params passed in config)

    """
    
    def __init__(self, *args, **kwargs):
        """
        Initialize with BaseDataClass instance and pass args, create attributes from all passed kwargs

        """
        super().__init__(*args)

        for key, value in kwargs.items():
            setattr(self, key, value)

    def set_initial_attribs(self):
        """
        Method to set initial attributes using attribs assigned at init

        """

        if self.excel_order == ['big_denom','count','stat']:
            self.indiv_denoms = False

        elif self.excel_order == ['big_denom','denom','count','stat']:
            self.indiv_denoms = True

        # assign specific additional attributes if a separate numerator ds is specified:
        # join_cols to join main and numerator ds on
        # separate numerator and denominator copies 

        if hasattr(self, 'group_cols'):
            self.join_cols = ['submtg_state_cd'] + self.group_cols

        # create lists of count cols, all table cols
        # if group_order is given, must dynamically create list of numerators and denominators

        if hasattr(self, 'group_order'):
            self.numerators = [f"numer_{g}" for g in self.group_order]
            if self.indiv_denoms == True:
                self.denominators = [f"denom_{g}" for g in self.group_order]

        if self.indiv_denoms == False:
            self.denominators = self.big_denom
            self.count_cols = self.numerators + self.denominators
            self.excel_cols = create_text_list(base_list = self.numerators, 
                                               return_list_func=stat_list, init_list=self.denominators)

        elif self.indiv_denoms == True:
            self.count_cols = self.big_denom + self.numerators + self.denominators
            self.excel_cols = create_text_list(base_list = [list(pair) for pair in zip(self.denominators,self.numerators)], 
                                               return_list_func=stat_list, init_list=self.big_denom )

    def prep_for_tables(self):
        """
        Method prep_for_tables to call class methods to create initial and prepped dfs, and pull sheet name from Excel template, and
        assign to class attributes

        """

        self.init_df = self.create_init_df()
        self.prepped_df = self.create_prepped_df(df = self.init_df)

        self.sheet_name = self.get_sheet_name()

    def create_init_df(self):
        """
        Method create_init_df to do the following:
            - Read in specific SAS ds
                - If additional param sas_ds_numer (SAS dataset with only numerators) was passed, must read in and join to base, creating numerator flag
            - Convert fips to name
            - Join to totals
            
        Returns:
            df to be assigned to init_df
        
        """
        df = self.read_sas_data(filename = self.sas_ds, copies = self.main_copies)

        if hasattr(self, 'sas_ds_numer'):
            for sas_ds in self.sas_ds_numer:
                df = df.merge(self.read_sas_data(filename=sas_ds, copies=self.numer_copies),
                     left_on=self.join_cols, right_on=self.join_cols, how='outer')

            # drop any dup columns (non-needed columns that joined on with multiple ds merges) - these cause concat to error

            df.drop(columns = list_dup_cols(df), inplace=True)

        df['state'] = convert_fips(df = df)

        return df.merge(self.totals_df.drop(columns=['submtg_state_cd']), left_on='state', right_on='state', how='outer')


    def create_prepped_df(self, df):
        """
        Method create_prepped_df to do the following on input df to prep to write to tables:
            
            - Fill denominators and conditionally fill numerators with 0s (only fill numer with 0 if denom > 0)
            - Apply small cell suppression to all counts (numerators and denominators separately)
                - if have indiv_denoms, must then loop over each pair of num/denom and suppress num if denom is suppressed based on second lowest suppression
            - Get national sum of all counts
            - Create percents, will be suppressed if numerator is already suppressed
            - Fill all nan values with period

        params:
            df: df to prep

        Returns:
            df to be assigned to prepped_df
        
        """

        df = zero_fill_cond(df = df, base_cols = self.denominators, cond_cols = self.numerators)

        df = small_cell_suppress(df, self.numerators, self.denominators,
                                 suppress_second = self.suppress_second, match_numer = self.indiv_denoms).reset_index(drop=True)

        df = pd.concat([df, get_national_values(df = df, calc_cols = self.count_cols, op='sum').reset_index(drop=True)], ignore_index=True)

        df = create_stats(df = df, numerators = self.numerators, denominators = self.denominators, prop_mult = self.prop_mult)

        return df.fillna('.').reset_index(drop=True)


    def get_sheet_name(self):
        """
        Method to return specific sheet name matching sheet number
        params:
            self

        returns:
            text with sheet name

        raises error if:
            0 or >1 sheets match given sheet number

        """

        match = [name for name in self.workbook.sheetnames if name.startswith(self.sheet_num)]

        assert len(match)==1, f"ERROR: {len(match)} sheet names start with given sheet number ({self.sheet_num}), requires exactly 1 - FIX"

        return match[0]

    def write_excel_sheet(self):
        """
        Method write_excel_sheet to write self.prepped_df to excel sheet using state-order df extracted from sheet
        params:
            self

        returns:
            none
        """

        order_df = read_template_col(workbook = self.workbook, sheet_name = self.sheet_name, state_list = STATE_LIST, strip_chars=['*'])

        # join order_df to table df, assert all values of state in order_df

        to_table = self.prepped_df.merge(order_df, left_on='state', right_on='state', how='outer', indicator = '_merged')

        assert set(to_table['_merged']) == set(['both']), f"ERROR: All values of state not on both template and table_df for {self.sheet_num} - FIX"

        # write to sheet

        write_sheet(workbook = self.workbook, df = to_table, sheet_name = self.sheet_name, cols = self.excel_cols, scol=self.scol, row_col = 'rownum')
