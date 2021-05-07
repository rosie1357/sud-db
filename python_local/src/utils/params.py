"""
params
"""

from pathlib import Path
from datetime import datetime
import time
from us import states

# date/folder/file name constants

TIME_NOW = time.strftime("%Y%m%d-%H%M%S")
DATE_NOW = datetime.today().strftime('%Y-%m-%d')
DATE_NOW_FMT = datetime.today().strftime("%B %d, %Y")

STATE_LIST = [str(state) for state in states.STATES_AND_TERRITORIES] + ['District of Columbia'] + 'United States'

# mappings of name/abbrev to FIPS

FIPS_NAME_MAP = states.mapping('fips','name')
FIPS_NAME_MAP['00'] = 'United States'

# base restricted and regular paths

DIR_RESTRICTED = lambda year: Path(fr"N:\Project\51131_MACBIS\Restricted\MA1\T3_Analytics\01_MandatedReports\01_SUDDatabook\{year-2018:02}_{year}")
DIR_MAIN = lambda year: Path(str(DIR_RESTRICTED(year)).replace('\\Restricted',''))

SASDIR = DIR_RESTRICTED / 'ebi_output'

OUTDIR = lambda year: DIR_RESTRICTED(year) / Path(r'python_local\final_tables')

OUTDIR = lambda year: DIR_RESTRICTED(year) / Path(r'python_local\logs')