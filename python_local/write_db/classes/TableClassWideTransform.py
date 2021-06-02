import pandas as pd

from .TableClass import TableClass
from ..tasks.data_transform import convert_fips, zero_fill_cond, create_stats
from ..tasks.national_values import get_national_values
from ..tasks.small_cell_suppress import small_cell_suppress
from ..utils.text_funcs import list_mapper, underscore_join

class TableClassWideTransform(TableClass):
    """
    TableClassWideTransform to inherit all attributes/methods from TableClass and overwrite main methods to  transpose input data from long to wide

    """

    def set_initial_attribs(self):

        """
        Method to set initial attributes using attribs assigned at init, adding to parent class method to add attribs to do wide transform

        """
        super().set_initial_attribs()

        # set state and big denom as index cols to pass to wide_transform

        self.index_cols = ['state'] + self.big_denom

        if hasattr(self, 'sas_ds_numer'):
            self.main_copies = {k : v for k,v in self.__dict__.items() if k  == 'denom'}
            self.numer_copies = {k : v for k,v in self.__dict__.items() if k  == 'numer'}

        else:
            self.main_copies = {k : v for k,v in self.__dict__.items() if k in ['numer','denom']}

            # if not using individual denoms, remove denom from dict/list

            if self.indiv_denoms == False:
                self.main_copies.pop('denom', None)
                self.values_transpose.remove('denom')
    
    def prep_for_tables(self):
        """
        Method prep_for_tables to override parent class method to add transform from long to wide between init and prep dfs

        """

        self.init_df_long = self.create_init_df()
        self.init_df = self.wide_transform(df = self.init_df_long)
        self.prepped_df = self.create_prepped_df(df = self.init_df) 

        self.sheet_name = self.get_sheet_name()

    def wide_transform(self, df):
        """
        Function wide_transform to take input df from wide to long
        params:
            df: df to transform from long to wide

        returns:
            df: dataframe transposed long to wide

        """

        # if have individual denoms, get totals across index_cols and group_cols - assume must sum and join back on

        if self.indiv_denoms == True:

            grouped = df.groupby(self.index_cols + self.group_cols)
            df['denom'] = grouped['denom'].transform(sum)

        # if numer_col is given, must create base df with deduplicated recs and separate num df with num counts only, and join together before transposing

        if 'numer_col' in self.__dict__.keys():

            join_cols = self.index_cols + self.group_cols

            base_df = df[join_cols + [col for col in self.values_transpose if col != 'numer']].drop_duplicates()
            num_df = df.loc[eval(f"df.{self.numer_col} {self.numer_value}")]

            df = base_df.merge(num_df[self.index_cols + self.group_cols + ['numer']], left_on=join_cols, right_on=join_cols, how='left').fillna(0)

            #wide = df.loc[eval(f"df.{self.numer_col} {self.numer_value}")].pivot_table(index=self.index_cols, columns=self.group_cols, values=self.values_transpose)

        wide = df.pivot_table(index=self.index_cols, columns=self.group_cols, values=self.values_transpose)

        # rename columns based on concatenation with underscore separator of current indices (tuples, which contain params passed above for "columns" and "values")

        wide.columns = list_mapper(underscore_join, wide.columns)
        
        return wide.reset_index()