import pandas as pd

from ..tasks.data_transform import convert_fips
from ..tasks.small_cell_suppress import small_cell_suppress


class BaseDataClass():
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

        self.year, self.sas_dir, self.totals_ds, self.workbook = year, sas_dir, totals_ds, workbook
        
        self.totals_df = self.prep_totals(tot_cols = ['pop_tot','pop_sud_tot'])
        
        # assign defaults that can be overwritten with table-specific params with creation of each TableClass

        self.scol = 2
        self.gen_wide = False
        self.main_copies = {}
        self.numer_copies = {}
        self.numer_col_any = []
        self.values_transpose = ['numer','denom']
        self.prop_mult = 100

    def read_sas(self, filename, copies={}):

        df = pd.read_sas(self.sas_dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

        for copy, orig in copies.items():
            df[copy] = df[orig]

        # if numer_col_any is set, must do the following for any cols in numer_col_any that are also in df cols:
        #   - subset to col == 1
        #   - rename count col to numer_col_any + _count
        # TODO: Make this dynamic, this hard coding was the simplest but not good way to do this!

        if hasattr(self, 'numer_col_any'):
            for col in list(set(df.columns) & set(self.numer_col_any)):
                df = df.loc[df[col]==1].rename(columns={'count' : f"{col}_count"})

        return df

    def prep_totals(self, tot_cols):
        """
        Method prep_totals to read in base file, apply small cell suppression, and create state totals for overall pop counts
        Rename totals to have _base suffix to avoid same named columns if joining to same ds
        """
        
        df = self.read_sas(self.totals_ds)[['submtg_state_cd'] + tot_cols]

        df['state'] = convert_fips(df=df)

        df = small_cell_suppress(df = df, suppress_cols = tot_cols)

        return df.rename(columns = {f"{col}" : f"{col}_base" for col in tot_cols})