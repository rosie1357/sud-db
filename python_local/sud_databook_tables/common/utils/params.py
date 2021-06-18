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

STATE_LIST = [str(state) for state in states.STATES_AND_TERRITORIES] + ['District of Columbia','United States','Total number of states']

# mappings of name/abbrev to FIPS

FIPS_NAME_MAP = states.mapping('fips','name')

# base restricted and regular paths

DIR_RESTRICTED = lambda year: Path(fr"N:\Project\51131_MACBIS\Restricted\MA1\T3_Analytics\01_MandatedReports\01_SUDDatabook\{int(year)-2018:02}_{year}")
DIR_MAIN = lambda year: Path(str(DIR_RESTRICTED(year)).replace('\\Restricted',''))

# subdirs

SPECDIR = lambda year: DIR_MAIN(year) / Path(r'Specs and table shells\Table shells')

SASDIR = lambda year: DIR_RESTRICTED(year) / 'ebi_output'

OUTDIR = lambda year: DIR_MAIN(year) / 'Output'

LOGDIR = lambda year: DIR_RESTRICTED(year) / Path(r'python_local\logs')

# file names

SHELL = 'SUD DB Tables.xlsx'
SHELL_OUD = 'SUD DB Tables_OUD.xlsx'
SHELL_PYEAR = 'SUD DB Tables - Prior Year Comparisons.xlsx'

OUTFILE = lambda year: f"SUD DB Tables ({year}) - {DATE_NOW}.xlsx"
OUTFILE_OUD = lambda year: f"SUD DB Tables (OUD) ({year}) - {DATE_NOW}.xlsx"
OUTFILE_PYEAR = lambda year: f"SUD DB Tables ({year}) - Prior Year Comparisons - {DATE_NOW}.xlsx"

TOTALS_DS = 'state_sud_methods'