import pandas as pd

from ..tasks.data_transform import convert_fips
from ..tasks.small_cell_suppress import small_cell_suppress
from common.utils.decorators import add_op_suffix
from common.utils.params import FIPS_NAME_MAP


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
        use_sud_ds list: list of any SAS datasets read in for given table that should use SUD only (do not append _op suffix)
        dq_state_excl list: list of states to exclude for DQ reasons


    """
    
    def __init__(self, year, sas_dir, totals_ds, table_type, workbook, use_sud_ds, dq_states_excl):

        self.year = year 
        self.sas_dir = sas_dir
        self.totals_ds = totals_ds 
        self.table_type = table_type 
        self.workbook = workbook
        self.use_sud_ds = use_sud_ds
        self.dq_states_excl = dq_states_excl
        
        # assign defaults that can be overwritten with table-specific params with creation of each TableClass

        self.scol = 2
        self.main_copies = {}
        self.numer_copies = {}
        self.numer_col_any = []
        self.values_transpose = ['numer','denom']
        self.prop_mult = 100
        self.suppress_second = False
        self.comparison_value = 'pct'

        # read in totals df to use in all with each creation of TableClass

        self.totals_df = self.prep_totals(tot_cols = ['pop_tot','pop_sud_tot'])

    @add_op_suffix
    def read_sas_data(self, filename=None, **kwargs):

        df = pd.read_sas(self.sas_dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

        # drop any states identified as DQ exclude

        df = df.loc[~df['submtg_state_cd'].isin(self.dq_states_excl)]

        if 'copies' in kwargs.keys():

            for copy, orig in kwargs['copies'].items():
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
        
        df = self.read_sas_data(filename=self.totals_ds)[['submtg_state_cd'] + tot_cols]

        df['state'] = convert_fips(df=df)

        df = small_cell_suppress(df, tot_cols)

        return df.rename(columns = {f"{col}" : f"{col}_base" for col in tot_cols})

    def fill_dq_unusable(self, df):
        """
        Method fill_dq_unusable to take input df, add rows for DQ unusable states if they do not exist, and fill with DQ
        
        """

        # identify any states marked as DQ and create dummy df with one rec per state - merge on so the state recs are there if they were not before

        dq_state_names_excl = [FIPS_NAME_MAP.get(state) for state in self.dq_states_excl]

        df = df.merge(pd.DataFrame(data = dq_state_names_excl, columns = ['state']), left_on='state', right_on='state', how='outer')

        df.loc[df['state'].isin(dq_state_names_excl)] = df.loc[df['state'].isin(dq_state_names_excl)].fillna('DQ')

        return df



