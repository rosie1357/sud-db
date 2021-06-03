
import pandas as pd

def get_national_values(*, df, calc_cols, op='sum', state_name = 'United States'):
    """
    Function get_national_values to calculate either sum or average across all rows (states)
    params:
        df df: input df (assumes one row per state)
        calc_cols list: list of cols to calculate
        op str: operational to perform, default is 'sum'
        state_name str: name to give to record in assigning value of col state, default = 'United States'

    Allows for non-numeric values - will coerce to numeric

    returns:
        df with aggregate values with one column per input calc_cols
    """


    return df[calc_cols].apply(pd.to_numeric, errors='coerce').agg([op]).assign(state = state_name)