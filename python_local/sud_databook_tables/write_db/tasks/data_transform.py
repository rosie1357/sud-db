import pandas as pd
import numpy as np

from common.utils.params import FIPS_NAME_MAP

def convert_fips(*, df, incol='submtg_state_cd'):

    return df[incol].map(lambda x: FIPS_NAME_MAP[x])
    
def calc_prop(num, denom, suppress_from_numer, suppress_value, prop_mult):
    """
    Helper function calc_prop to be applied row-wise to each set of numerator/denominators
    If suppress_from_numer == True, will return suppressed value if numer is suppressed
    Otherwise, returns num/denom * prop_mult

    """
    
    if suppress_from_numer == True:
        if num == suppress_value:
            return suppress_value

        elif denom == suppress_value:
            return np.nan

    try:
        return prop_mult * (num / denom)

    except ZeroDivisionError:
        return np.nan

def create_stats(*, df, numerators, denominators, prop_mult, suffix='_stat', suppress_from_numer=True, suppress_value='DS', stat_name_use=0):
    """
    Function create_stats to create stats (num/denom multiplied by given value) based on passed numerator/denominator params
    params:
        df df: df with num/denom cols
        numerators list: list of numerators (will make one percent for each numerator)
        denominators list: list of denominators, can be passed one of two ways:
            - if 1 denom and >1 numerators passed, the 1 denom will be used to create all stats
            - if # denoms = # of numerators, create stats based on position with each denom / each num in same position
            - note if # denom > 1 but NOT equal to # of numerators, will force error
        prop_mult int: int to multiple num/denom by, e.g. if give 100 will create pct
        suffix str: suffix to add to numerator name to make stat, default = _stat
        suppress_from_numer bool: boolean to indicate whether calculated stat should be set suppressed value if numer is suppressed already, default = True
        suppress_value str: value indicating suppression, default = 'DS'
        stat_name_use int: based on numerator/denominator pairs, indicates which to use to name the created stat (with specified suffix)
            if 0, will use numerator (default)
            if 1, will use denominator

    returns:
        df with stats added

    """

    if len(denominators) == 1 and len(numerators) > 1:
        denominators = denominators * len(numerators)

    assert len(denominators) == len(numerators), "ERROR: Length of numerators != length of denominators passed to create_stats: FIX"

    for pair in zip(numerators, denominators):

        df[f"{pair[stat_name_use]}{suffix}"] = df[list(pair)].apply(lambda x: calc_prop(*x, suppress_from_numer, suppress_value, prop_mult), axis=1)

    return df

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



