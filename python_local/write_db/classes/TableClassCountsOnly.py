
import pandas as pd

from .TableClass import TableClass
from ..tasks.data_transform import convert_fips
from ..tasks.national_values import get_national_values


class TableClassCountsOnly(TableClass):
    """
    TableClassCountsOnly to inherit all attributes/methods from TableClass and override main methods (minimal data prep needed for counts only)

    """

    def set_initial_attribs(self):

        """
        Method to set initial attributes using attribs assigned at init, overriding method from TableClass

        """

        self.excel_cols = self.count_cols

    def prep_for_tables(self):
        """
        Method prep_for_tables to override parent class method to run processing specific to counts table

        """

        self.prepped_df = self.create_prepped_df() 

        self.sheet_name = self.get_sheet_name()


    def create_prepped_df(self):
        """
        Method create_prepped_df to override method from TableClass to do minimal prep on input sas DS
        Does the following steps:

            - Read in specific SAS ds
            - Convert fips to name
            - Convert counts to set > 0 to 1, otherwise 0
            - Sum to get first total row

        Returns:
            df to be assigned to table_df
        
        """

        df = self.read_sas(self.sas_ds)

        df['state'] = convert_fips(df = df)

        df[self.count_cols] = df[self.count_cols].applymap(lambda x: 1 if x > 0 else 0)

        df = pd.concat([df, get_national_values(df = df, calc_cols = self.count_cols, op='sum', state_name='Total number of states').reset_index(drop=True)], ignore_index=True)

        return df.reset_index(drop=True)