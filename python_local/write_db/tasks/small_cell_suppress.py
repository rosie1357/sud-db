import pandas as pd

def suppress_second_lowest(row, suppress_value):
    """
    Function suppress_second_lowest to do the following:
        - Identify if there is exactly ONE value within the row suppressed
        - If yes, also suppress the SECOND lowest that is > 0. If there are ties for second lowest, just suppress the first

    params:
        row series: applied row-wise to input df with only specific cols to suppress passed
        suppress value str/int: value to identify suppressed value and suppress second lowest if needed

    returns:
        input row (series) with second lowest suppressed if appropriate

    """
    
    # count the number of values in the series with the suppress value (default to 0)
    
    cnt_suppress = dict(row.value_counts()).get(suppress_value, 0)

    # if exactly one suppressed, create a boolean mask to identify numeric values > 0,
    # then identify the lowest value index with the min value in the series and also suppress
    
    if cnt_suppress == 1:
        
        mask = row.apply(lambda x: pd.to_numeric(x, errors='coerce')>0)
        
        row.loc[pd.to_numeric(row[mask]).idxmin()] = suppress_value
    
    return row


def small_cell_suppress(*, df, suppress_cols, suppress_value='DS', min_max=(0,11), suppress_second = False):
    """
    Function small_cell_suppress to set all values of given columns within given range to given suppressed value.

    params:
        df df: pandas df
        suppress_cols list: list of col(s) to evaluate value and suppress
        suppress_value [str, int, float] value to use if suppressing, default = 'DS'
        min_max tuple: tuple with range of min/max values to identify for suppression, will identify EXCLUSIVE of range, default = (0,11)
        suppress_second bool: boolean to indicate must suppress SECOND lowest value if only one value within row suppressed, default = False (do not suppress second lowest)

    returns:
        df with suppression applied

    """

    df[suppress_cols] = df[suppress_cols].applymap(lambda x: suppress_value if (x > min_max[0]) & (x < min_max[1]) else x)

    if suppress_second:
        df[suppress_cols] = df[suppress_cols].apply(suppress_second_lowest, suppress_value=suppress_value, axis=1)

    return df