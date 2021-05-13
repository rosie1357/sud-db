import pandas as pd

from ..utils.params import FIPS_NAME_MAP

def read_sas(*, dir, filename):

    return pd.read_sas(dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

def convert_fips(*, df, incol='submtg_state_cd'):

    return df[incol].map(lambda x: FIPS_NAME_MAP[x])

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

    def calc_pct(num, denom):
        """
        Helper function calc_pct to be applied row-wise to each set of numerator/denominators
        If suppress_from_numer == True, will return suppressed value if numer is suppressed
        Otherwise, returns num/denom * 100

        """
        
        if suppress_from_numer == True:
            if num == suppress_value:
                return suppress_value

        return 100 * (num / denom)

    if len(denominators) == 1 and len(numerators) > 1:
        denominators = denominators * len(numerators)

    assert len(denominators) == len(numerators), "ERROR: Length of numerators != length of denominators passed to create_pcts: FIX"

    for pair in zip(numerators, denominators):

        df[f"{pair[0]}{suffix}"] = df[list(pair)].apply(lambda x: calc_pct(*x), axis=1)

    return df