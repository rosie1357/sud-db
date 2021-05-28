import pandas as pd

from .TableClass import TableClass
from ..tasks.data_transform import convert_fips, zero_fill_cond, create_stats
from ..tasks.national_values import get_national_values
from ..tasks.small_cell_suppress import small_cell_suppress
from ..utils.decorators import add_op_suffix


class TableClassDuals(TableClass):
    """
    TableClassDuals to inherit all attributes/methods from TableClass and overwrite main methods (table does not follow structure of any others)

    """

    def set_initial_attribs(self):

        """
        Method to set initial attributes using attribs assigned at init, overriding method from TableClass

        """

        self.excel_cols = self.big_denom + self.count_cols + [f"{denom}_stat" for  denom in self.denominators]

        self.group_cols = ['submtg_state_cd']

    @add_op_suffix
    def read_sas_duals(self, filename):
        """
        Method read_sas_duals to do the following (modified version of read_sas):
            - subset to subset_col and subset_value (duals only)
            - Get total and join back on to get total dual count (first col given in self.count_cols)
            - subset to numer population (SUD only) and rename count to name of second col given in self.count_cols

        """

        df = pd.read_sas(self.sas_dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')
        df = df.loc[eval(f"df.{self.subset_col} {self.subset_value}")]

        grouped = df.groupby(self.group_cols)
        df[self.count_cols[0]] = grouped['count'].transform(sum)

        return df.loc[eval(f"df.{self.numer_col} {self.numer_value}")].rename(columns = {'count' : self.count_cols[1]})

    def prep_for_tables(self):
        """
        Method prep_for_tables to override parent class method to run processing specific to duals table

        """

        self.prepped_df = self.create_prepped_df() 

        self.sheet_name = self.get_sheet_name()


    def create_prepped_df(self):
        """
        Method create_prepped_df to override method from TableClass to do unique prep on DS:

            - Read in specific SAS ds, make subsets to duals and create SUD numerator (using read_sas overriden for class)
            - Convert fips to name
            - Join to totals
            - Fill denominators and conditionally fill numerators with 0s (only fill numer with 0 if denom > 0)
            - Apply small cell suppression to all counts
            - Get national sum of all counts
            - Create percents, will be suppressed if numerator is already suppressed
            - Fill all nan values with period

        Returns:
            df to be assigned to table_df
        
        """

        df = self.read_sas_duals(self.sas_ds)

        df['state'] = convert_fips(df = df)

        df = df.merge(self.totals_df.drop(columns=['submtg_state_cd']), left_on='state', right_on='state', how='outer')

        df = zero_fill_cond(df = df, base_cols = [self.count_cols[0]], cond_cols = [self.count_cols[1]])

        df = small_cell_suppress(df = df, suppress_cols = self.count_cols).reset_index(drop=True)

        df = pd.concat([df, get_national_values(df = df, calc_cols = self.count_cols + self.big_denom, op='sum').reset_index(drop=True)], ignore_index=True)

        df = create_stats(df = df, numerators = [self.numerator] * len(self.denominators), denominators = self.denominators, 
                          prop_mult = self.prop_mult, stat_name_use=1)

        return df.fillna('.').reset_index(drop=True)