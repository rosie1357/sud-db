"""
df funcs
"""

import pandas as pd

from collections import Counter

def list_dup_cols(df):
    """
    Function list_dup_cols to read in df and return list of duplicate columns (if exist)

    params:
        df: pandas df

    returns:
        list: list of duplicate col names, empty list if no dups

    """

    return [key for key, value in Counter(df.columns).items() if value > 1]
