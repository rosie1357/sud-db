import pandas as pd

from ..tasks.national_values import get_national_values
from ..tasks.data_transform import read_sas, convert_fips, create_pcts, wide_transform, zero_fill_cond
from ..tasks.small_cell_suppress import small_cell_suppress
from ..tasks.write_excel import read_template_col, write_sheet
from ..utils.text_funcs import pct_list, create_text_list
from ..utils.params import STATE_LIST

class BaseDataClass:
    """
    BaseDataClass to use as parent for TableDataClass to do the following:
         set base properties - defaults that can be overwritten with table-specific params from config
         create total population counts df

    Must initialize with:
        year str: TAF year to write
        sas_dir Path: path to sas datasets
        totals_ds str: name of SAS dataset with totals
        workbook excel obj: template to write to


    """

    def __init__(self, year, sas_dir, totals_ds, workbook):

        self.year = year
        self.sas_dir  = sas_dir
        self.totals_ds = totals_ds
        self.workbook = workbook
        
        self.totals_df = self.prep_totals(tot_cols = ['pop_tot','pop_sud_tot'])
        
        # assign defaults that can be overwritten with table-specific params with creation of each TableClass

        self.scol = 2
        self.gen_wide = False

    def prep_totals(self, tot_cols):
        """
        Method prep_totals to read in base file, apply small cell suppression, and create state totals for overall pop counts
        Rename totals to have _base suffix to avoid same named columns if joining to same ds
        """
        
        df = read_sas(dir=self.sas_dir, filename=self.totals_ds)[['submtg_state_cd'] + tot_cols]

        df['state'] = convert_fips(df=df)

        df = small_cell_suppress(df = df, suppress_cols = tot_cols)

        return df.rename(columns = {f"{col}" : f"{col}_base" for col in tot_cols})
        
        
class TableClass(BaseDataClass):
    """
    TableClass to inherit from instance of BaseDataClass to get base attributes and totals df

    Must initialize with:
        baseclass_inst BaseDataClass: instance of BaseDataClass
        details_dict dict: dict with all details to make table (read in from config file)

    """
    
    def __init__(self, baseclass_inst, details_dict):
        """
        Initialize with BaseDataClass instance, create attributes from passed details_dict key/value pairs

        """
        self.baseclass_inst = baseclass_inst
        self.details_dict = details_dict

        for key in details_dict:
            setattr(self, key, details_dict[key])

        # create lists of count cols, all table cols

        # if group_order is given, must dynamically create list of numerators and denominators
        # numerator is assumed to be sum_col (will be summed) in wide_transform

        if hasattr(self, 'group_order'):
            self.numerators = [f"{self.sum_col}_{g}" for g in self.group_order]

            if not hasattr(self, 'denominators'):
                self.denominators = [f"denom_{g}" for g in self.group_order]

        if self.excel_order == ['big_denom','count','pct']:
            self.count_cols = self.numerators + self.denominators
            self.excel_cols = create_text_list(base_list = self.numerators, 
                                               return_list_func=pct_list, init_list=self.denominators)

        elif self.excel_order == ['big_denom','denom','count','pct']:
            self.count_cols = self.big_denom + self.numerators + self.denominators
            self.excel_cols = create_text_list(base_list = [list(pair) for pair in zip(self.denominators,self.numerators)], 
                                               return_list_func=pct_list, init_list=self.big_denom )

        # create dataframe to write to tables

        self.table_df = self.create_table_df()

        # identify specific sheet name from list of workbook sheets

        self.sheet_name = self.get_sheet_name()
        
    def __getattr__(self, attr):
        """
        Assign all attributes of BaseDataClass instance
        """
        return getattr(self.baseclass_inst, attr)


    def create_table_df(self):
        """
        Method create_table_df to do the following:
            - Read in specific SAS ds
            - Convert fips to name
            - Join to totals
            - Fill denominators and conditionally fill numerators with 0s (only fill numer with 0 if denom > 0)
            - Apply small cell suppression to all counts
            - Get national sum of all counts
            - Create percents, will be suppressed if numerator is already suppressed
            - Fill all nan values with period
        
        """

        df = read_sas(dir=self.sas_dir, filename=self.sas_ds)

        df['state'] = convert_fips(df = df)

        if self.gen_wide == True:
            
            # call wide_transform to read in long table, sum totals, and transform to get to wide format (one row per state)

            df = wide_transform(df, 'state', **self.details_dict)

        df = df.merge(self.totals_df.drop(columns=['submtg_state_cd']), left_on='state', right_on='state', how='outer')

        df = zero_fill_cond(df = df, base_cols = self.denominators, cond_cols = self.numerators)

        df = small_cell_suppress(df = df, suppress_cols = self.count_cols)

        df = pd.concat([df, get_national_values(df = df, calc_cols = self.count_cols, op='sum')])

        df = create_pcts(df = df, numerators = self.numerators, denominators = self.denominators)

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
        Method write_excel_sheet to write table df to excel sheet using state-order df extracted from sheet
        params:
            self

        returns:
            none
        """

        order_df = read_template_col(workbook = self.workbook, sheet_name = self.sheet_name, state_list = STATE_LIST, strip_chars=['*'])

        # join order_df to table df, assert all values of state in order_df

        to_table = self.table_df.merge(order_df, left_on='state', right_on='state', how='outer', indicator = '_merged')

        assert set(to_table['_merged']) == set(['both']), f"ERROR: All values of state not on both template and table_df for {self.table_num} - FIX"

        # write to sheet

        write_sheet(workbook = self.workbook, df = to_table, sheet_name = self.sheet_name, cols = self.excel_cols, scol=self.scol, row_col = 'rownum')
        




    