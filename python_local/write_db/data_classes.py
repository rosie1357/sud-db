
import pandas as pd
from utils.params import FIPS_NAME_MAP
from tasks.national_values import get_national_values

class BaseDataClass:
    """
    BaseDataClass to use as parent for TableDataClass to do the following:
         set base properties
         set common methods
         create total population counts df


    """

    def __init__(self, year, sas_dir, base_filename):

        self.year = year
        self.sas_dir  = sas_dir
        self.base_filename = base_filename
        
        self.totals_df = self.prep_totals(tot_cols = ['pop_tot','pop_sud_tot'])

    
    def read_sas(self, filename):

        return pd.read_sas(self.sas_dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

    def convert_fips(self, df, incol='submtg_state_cd'):

        return df[incol].map(lambda x: FIPS_NAME_MAP[x])

    def prep_totals(self, tot_cols):
        """
        Method prep_totals to read in and create state and US totals for overall pop counts

        """
        
        df = self.read_sas(self.base_filename)

        df['state'] = self.convert_fips(df=df)

        nat = get_national_values(df = df, calc_cols = tot_cols)

        return pd.concat([df[['state'] + tot_cols], nat]).reset_index(drop=True)
        
        
class TableClass(BaseDataClass):
    
    def __init__(self, baseclass_inst, table_name):
        self.baseclass_inst = baseclass_inst
        self.table_name = table_name
        
    def __getattr__(self, attr):
        return getattr(self.baseclass_inst, attr)
    