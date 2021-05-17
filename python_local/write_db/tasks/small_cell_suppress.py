def small_cell_suppress(*, df, suppress_cols, suppress_value='DS', min_max=(0,11)):
    """
    Function small_cell_suppress to set all values of given columns within given range to given suppressed value.

    params:
        df df: pandas df
        suppress_cols list: list of col(s) to evaluate value and suppress
        suppress_value [str, int, float] value to use if suppressing, default = 'DS'
        min_max tuple: tuple with range of min/max values to identify for suppression, will identify EXCLUSIVE of range, default = (0,11)

    returns:
        df with suppression applied

    """

    df[suppress_cols] = df[suppress_cols].applymap(lambda x: suppress_value if (x > min_max[0]) & (x < min_max[1]) else x)

    return df