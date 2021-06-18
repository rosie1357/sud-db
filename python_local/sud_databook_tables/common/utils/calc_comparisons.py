import pandas as pd
import numpy as np

def calc_comparisons(*, data1, data2, join_on, how_join = 'outer', compare_cols = 'All', join_suffixes = ('_1','_2'), diff_types = 'both', fill_na = None, **kwargs):
    """
    Function calc_comparisons to read in two datasets with the same columns and calculate raw and/or pct differences for each pairs of columns,
        for data1 - data2.
        
    If input cols have non-numeric values, will return nan
   
    Will add _diff and/or _pctdiff columns to output df for each col to be compared

    Notes:
        - any div by 0 for percent differences will be set to NA
        - percent differences are NOT multiplied by 100 - that must be done with formatting
    
    params:
        data1 df: first datasets
        data2 df: second dataset (difference will be calulcated as data1 - data2)
        join_on str: name of col to join on (must be on both)
        how_join str: how to join, default is outer
        compare_cols str/list: columns to compare, default = All (all cols), otherwise will only compare passed list
        join_suffixes tuple: suffixes to add to joined data, default is _1, _2
        diff_types str: type of differences to create - default is both. 
            Other options are raw (only calculate raw differences) or pct (only calcualte pct differences).
            Will issue error if other value is given
        fill_na str/int/bool: if given, will fill any null comparison with value - default is None
        
    returns:
        pandas df, merged data1 and data2 with comparisons
    
    """
    
    joined = pd.merge(data1, data2, how = how_join, on = join_on, suffixes = join_suffixes)
    
    if compare_cols == 'All':
        compare_cols = [col for col in data1 if col != join_on]
        
    else:
        assert all((col in data1.columns) & (col in data2.columns) for col in compare_cols), f"Invalid list of cols ({compare_cols}) passed to {kwargs['function_name']}: FIX"

    assert diff_types.lower() in ['both','raw','pct'], f"Invalid value of diff_types ({diff_types}) passed to calc_comparisons. Must be both, raw or pct: FIX"
    
    for col in compare_cols:

        if diff_types != 'pct':
            joined[f"{col}_diff"] = pd.to_numeric(joined[f"{col}{join_suffixes[0]}"], errors='coerce') - pd.to_numeric(joined[f"{col}{join_suffixes[1]}"], errors='coerce')
            
            if fill_na:
                joined[f"{col}_diff"].fillna(fill_na, inplace=True)

        if diff_types != 'raw':
            joined[f"{col}_pctdiff"] = 100 * ((pd.to_numeric(joined[f"{col}{join_suffixes[0]}"], errors='coerce') - pd.to_numeric(joined[f"{col}{join_suffixes[1]}"], errors='coerce'))
                                               /pd.to_numeric(joined[f"{col}{join_suffixes[1]}"],errors='coerce')).replace(np.inf, 'NA')
            
            if fill_na:
                joined[f"{col}_pctdiff"].fillna(fill_na, inplace=True)
    
    return joined