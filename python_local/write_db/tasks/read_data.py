"""
read data funcs
"""

import pandas as pd

def read_sas(*, dir, filename, renames={}, copies={}):

    df = pd.read_sas(dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1').rename(columns = renames)

    for copy, orig in copies.items():
        df[copy] = df[orig]

    return df