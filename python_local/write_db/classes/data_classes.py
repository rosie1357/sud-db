import pandas as pd

from ..tasks.national_values import get_national_values
from ..tasks.data_transform import read_sas, convert_fips, create_pcts
from ..tasks.small_cell_suppress import small_cell_suppress
from ..utils.text_funcs import pct_list, create_text_list

class BaseDataClass:
    """
    BaseDataClass to use as parent for TableDataClass to do the following:
         set base properties
         create total population counts df

    Must initialize with:
        year str: TAF year to write
        sas_dir Path: path to sas datasets
        totals_ds str: name of SAS dataset with totals


    """

    def __init__(self, year, sas_dir, totals_ds):

        self.year = year
        self.sas_dir  = sas_dir
        self.totals_ds = totals_ds
        
        self.totals_df = self.prep_totals(tot_cols = ['pop_tot','pop_sud_tot'])

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

        for key in details_dict:
            setattr(self, key, details_dict[key])

        # create lists of count cols, all table cols

        self.count_cols = self.numerators + self.denominators

        if self.excel_order == ['denominator','count','pct']:
            self.excel_cols = create_text_list(base_list = self.numerators, return_list_func=pct_list, init_list=self.denominators)

        # create base_df

        self.base_df = self.create_base_df()
        
    def __getattr__(self, attr):
        """
        Assign all attributes of BaseDataClass instance
        """
        return getattr(self.baseclass_inst, attr)


    def create_base_df(self):
        """
        Method create_base_df to do the following:
            1. Read in specific SAS ds
            2. Convert fips to name
            3. Join to totals
            4. Apply small cell suppression to all counts
            5. Get national sum of all counts
            6. Create percents, will be suppressed if numerator is already suppressed
        
        """

        df = read_sas(dir=self.sas_dir, filename=self.sas_ds)

        df['state'] = convert_fips(df = df)

        df = df.merge(self.totals_df.drop(columns=['submtg_state_cd']), left_on='state', right_on='state', how='outer')

        df = small_cell_suppress(df = df, suppress_cols = self.count_cols)

        df = pd.concat([df, get_national_values(df = df, calc_cols = self.count_cols, op='sum')])

        df = create_pcts(df = df, numerators = self.numerators, denominators = self.denominators)

        return df


    