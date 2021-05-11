import pandas as pd

from utils.params import FIPS_NAME_MAP

def read_sas(self, filename):

    return pd.read_sas(self.sas_dir / f"{filename}.sas7bdat", encoding = 'ISO-8859-1')

def convert_fips(self, df, incol='submtg_state_cd'):

    return df[incol].map(lambda x: FIPS_NAME_MAP[x])