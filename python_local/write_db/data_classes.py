
import pandas as pd
from tasks.national_values import get_national_values
from tasks.data_transform import read_sas, convert_fips
from tasks.small_cell_suppress import small_cell_suppress

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
        
        df = read_sas(self.totals_ds)

        df['state'] = convert_fips(df=df)

        df = small_cell_suppress(df = df, suppress_col = tot_cols)

        return df.rename(columns = {f"{col}" : f"{col}_base" for col in tot_cols})
        
        
class TableClass(BaseDataClass):
    """
    TableClass to inherit from instance of BaseDataClass to get base attributes and totals df

    Must initialize with:
        baseclass_inst BaseDataClass: instance of BaseDataClass
        table_name str: name of table to write
        sas_ds str: name of SAS ds with counts for table

    """
    
    
    def __init__(self, baseclass_inst, table_name, sas_ds):
        self.baseclass_inst = baseclass_inst
        self.table_name = table_name
        self.sas_ds = sas_ds
        
        # create base_df

        self.base_df = self.create_base_df()
        
    def __getattr__(self, attr):
        return getattr(self.baseclass_inst, attr)


    def create_base_df(self):
        """
        Method create_base_df to read in specific SAS ds, convert fips, and join to totals
        
        """

        df = read_sas(self.sas_ds)
        df['state'] = convert_fips(df = self.base_df)

        df.merge(self.totals_df, left_on='state', right_on='state', how='outer')


    