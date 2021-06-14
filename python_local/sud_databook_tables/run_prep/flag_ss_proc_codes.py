"""
Read in SS procedure codes downloaded from Redshift, remove national codes, and output excel with all codes not in national list with any word matching SUD list
"""

import pandas as pd
import argparse
from pathlib import Path

from common.utils.params import DATE_NOW, DIR_MAIN

SS_DIR = lambda year: DIR_MAIN(year) / Path(r'Output\State-specific procedure codes')
NAT_DIR = lambda natyear: Path(fr"N:\Project\51131_MACBIS\MA1\T2_DQ_Atlas\Automation\DQ lookup tables\_Lookups\v4_0\PROC_NAT\{natyear}")

SS_FILE = "State_Specific_Proc_Codes_Raw_20210614.xlsx"
NAT_FILE = lambda natyear: f"values_prcdr_cd_{natyear}.txt"

OUT_FILE = f"State_Specific_Proc_Codes_SUD_Words {DATE_NOW}.xlsx"

SUD_WORDS = ['substance','opioid','tobacco','alcohol','drug','naloxone','methadone','naltrexone','vivitrol','suboxone','buprenorphine', 
           'disulphiram','detox','chemical','cannabis','abuse','cocaine','stimulant','hallucinogen','nicotine','inhalant','psychoactive',
           'smoking','opium','heroin','narcotic','cigarette','ethanol','caffeine']

def is_sa(row):
    
    if any(word in str(row).lower() for word in SUD_WORDS):
        return True
    else:
        return False

def extract(row):
    
    if row.startswith("('"):
        return row.replace("('","").replace("'),","").replace("');","")
        
    else:
        return None

def main(args=None):

    # add cli args and extract

    parser = argparse.ArgumentParser()

    parser.add_argument('--year', required=True)
    year = parser.parse_args().year

    # assume always pull national codes from given year - 1

    natyear = int(year)-1 

    # read in SS codes

    ss_codes = pd.read_excel(SS_DIR(year) / SS_FILE)

    ss_codes['submtg_state_cd'] = ss_codes['submtg_state_cd'].apply(lambda x: str(x).zfill(2))

    # read in nat codes
        
    nat_codes = pd.read_csv(NAT_DIR(natyear) / NAT_FILE(natyear), header=None, delimiter = "\t")

    nat_codes['code'] = nat_codes[0].apply(extract)
    nat_codes.dropna(subset=['code'], inplace=True)
    nat_codes.drop(columns=[0], inplace=True)

    # join the two, identify codes that are NOT in the national list

    joined = pd.merge(ss_codes, nat_codes, left_on='vld_val', right_on='code', how='left', indicator=True)

    # create indicator for matching any of the SA words
        
    joined['sud_word'] = joined['vld_val_desc'].apply(is_sa)

    out = joined[(joined['sud_word']) & (joined['_merge']=='left_only')]

    out[['submtg_state_cd','vld_val','vld_val_desc']].to_excel(SS_DIR(year) / OUT_FILE, index=False)