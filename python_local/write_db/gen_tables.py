
from .utils.params import SASDIR, TOTALS_DS
from .classes.BaseDataClass import BaseDataClass
from .classes.TableClass import TableClass
from .classes.TableClassCountsOnly import TableClassCountsOnly
from .classes.TableClassDuals import TableClassDuals

def gen_tables(*, year, version, workbook, table_details):
    """
    Function gen_tables to generate excel tables
    params:
        year str: year to run
        version str: version of TAF
        workbook excel obj: template to write to
        table_details dict: dictionary with one table per key with details to write table

    """

    # loop over all tables in table_details to create regular TableClass (default) or child class if specified

    for table, kwargs in table_details.items():

        # identify class to use for given measure - TableClass is default

        use_class = kwargs.get('use_class', 'TableClass')

        # create table class, set initial attributes

        _tableclass = eval(use_class)(year, SASDIR(year), TOTALS_DS, workbook, **kwargs)

        _tableclass.set_initial_attribs()

        # prep to write to tables

        _tableclass.prep_for_tables()

        # write to excel

        _tableclass.write_excel_sheet()
        


