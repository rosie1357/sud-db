
from .utils.params import SASDIR, TOTALS_DS
from .classes.BaseDataClass import BaseDataClass
from .classes.TableClass import TableClass
from .classes.TableClassWideTransform import TableClassWideTransform
from .classes.TableClassCountsOnly import TableClassCountsOnly
from .classes.TableClassDuals import TableClassDuals

def gen_tables(*, year, version, workbook, table_details, config_sheet_num='sheet_num_sud', table_type='SUD'):
    """
    Function gen_tables to generate excel tables
    params:
        year str: year to run
        version str: version of TAF
        workbook excel obj: template to write to
        table_details dict: dictionary with one table per key with details to write table
        table_type str: table to write, default is SUD. For OUD set to OUD
        config_sheet_num str: name of sheet num param in config  to pull for given table, default is sheet_num_sud
            for OUD tables = sheet_num_op

    """

    # loop over all tables in table_details to create regular TableClass (default) or child class if specified
    # only run for OUD tables if sheet_num_op in kwargs

    for table, kwargs in table_details.items():

        sheet_num = kwargs.get(config_sheet_num, None)

        # only write table if sheet num given in config (do not write every sheet for OUD)

        if sheet_num:

            # identify class to use for given measure - TableClass is default

            use_class = kwargs.get('use_class', 'TableClass')

            # create table class, set initial attributes, add sheet_num to pass with kwargs to set class attributes

            _tableclass = eval(use_class)(year, SASDIR(year), TOTALS_DS, table_type, workbook, **dict(kwargs, sheet_num=sheet_num))

            _tableclass.set_initial_attribs()

            # prep to write to tables

            _tableclass.prep_for_tables()

            # write to excel

            _tableclass.write_excel_sheet()
        


