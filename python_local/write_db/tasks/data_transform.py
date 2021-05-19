import pandas as pd
import numpy as np

from ..utils.params import FIPS_NAME_MAP
from ..utils.text_funcs import list_mapper, underscore_join

def read_sas(*, dir, filename):

    return pd.read_sas(dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

def convert_fips(*, df, incol='submtg_state_cd'):

    return df[incol].map(lambda x: FIPS_NAME_MAP[x])
    

def calc_pct(num, denom, suppress_from_numer, suppress_value):
    """
    Helper function calc_pct to be applied row-wise to each set of numerator/denominators
    If suppress_from_numer == True, will return suppressed value if numer is suppressed
    Otherwise, returns num/denom * 100

    """
    
    if suppress_from_numer == True:
        if num == suppress_value:
            return suppress_value

    try:
        return 100 * (num / denom)

    except ZeroDivisionError:
        return np.nan

def create_pcts(*, df, numerators, denominators, suffix='_pct', suppress_from_numer=True, suppress_value='DS'):
    """
    Function create_pcts to create percents based on passed numerator/denominator params
    params:
        df df: df with num/denom cols
        numerators list: list of numerators (will make one percent for each numerator)
        denominators list: list of denominators, can be passed one of two ways:
            - if 1 denom and >1 numerators passed, the 1 denom will be used to create all percents
            - if # denoms = # of numerators, create percents based on position with each denom / each num in same position
            - note if # denom > 1 but NOT equal to # of numerators, will force error
        suffix str: suffix to add to numerator name to make pct, default = _pct
        suppress_from_numer bool: boolean to indicate whether calculated pct should be set suppressed value if numer is suppressed already, default = True
        suppress_value str: value indicating suppression, default = 'DS'

    returns:
        df with percents added

    """

    if len(denominators) == 1 and len(numerators) > 1:
        denominators = denominators * len(numerators)

    assert len(denominators) == len(numerators), "ERROR: Length of numerators != length of denominators passed to create_pcts: FIX"

    for pair in zip(numerators, denominators):

        df[f"{pair[0]}{suffix}"] = df[list(pair)].apply(lambda x: calc_pct(*x, suppress_from_numer, suppress_value), axis=1)

    return df

def wide_transform(df, index_col, **kwargs):
    """
    Function wide_transform to take input df from wide to long
    params:
        df df: input df
        kwargs dict: additional params to dictate transformations

    returns:
        df: dataframe transposed long to wide


    """
    
    # get totals across index_col if group_col is passed in kwargs (assumes sum_col, numer_col, numer_value also assigned)

    if 'group_col' in kwargs.keys():

        grouped = df.groupby([index_col, kwargs['group_col']])

        df['denom'] = grouped[kwargs['sum_col']].transform(sum)

        wide = df.loc[eval(f"df.{kwargs['numer_col']} {kwargs['numer_value']}")].pivot_table(index=[index_col], columns=[kwargs['group_col']], values=[kwargs['sum_col'],'denom'])

        # rename columns based on concatenation of current indices (tuples, which contain params passed above for "columns" and "values")

        wide.columns = list_mapper(underscore_join, wide.columns)
        
        return wide

def zero_fill_cond(*, df, base_cols, cond_cols):
    """
    Function zero_fill_cond to operate on pairs of columns (e.g. denominators and numerators)
    to fill the base_col with 0 if nan, and only conditionally fill cond_col if base_col meets specified condition
    params:
        df: input df
        base_cols list: list of base_cols
        cond_cols list: list of cond_cols

    requires:
        # base_cols = # of cond_cols, will apply pairwise to each base and cond col


    """

    if len(base_cols) == 1 and len(cond_cols) > 1:
        base_cols = base_cols * len(cond_cols)

    assert len(base_cols) == len(cond_cols), "ERROR: Length of base_cols != length of cond_cols passed to zero_fill_cond: FIX"

    for pair in zip(base_cols, cond_cols):

        base, cond = list(pair)[0], list(pair)[1]

        df[base] = df[base].fillna(0)

        df.loc[df[base] > 1, cond] = df[cond].fillna(0)

    return df



