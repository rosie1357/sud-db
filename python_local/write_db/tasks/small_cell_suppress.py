

def small_cell_suppress(*, df, suppress_col, addtl_cols=None, suppress_value='DS', min_max=(0,11)):
    """
    Function small_cell_suppress to set all values of given col within given range to given suppressed value.
    If addtl_cols are given, on same row will also set to same suppressed value

    params:
        df df: pandas df
        suppress_col [str, int, float]: name of col to evaluate value and suppress
        addtl_cols list: optional list of additional cols to suppress
        suppress_value [str, int, float] value to use if suppressing, default = 'DS'
        min_max tuple: tuple with range of min/max values to identify for suppression, will identify EXCLUSIVE of range, default = (0,11)

    returns:
        df with suppression applied

    """

    df[suppress_col] = df[suppress_col].apply(lambda x: suppress_value if (x > min_max[0]) &(x < min_max[1]) else x)

    if addtl_cols:
        df.loc[df[suppress_col] == suppress_value, addtl_cols] = suppress_value

    return df