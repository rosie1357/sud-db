
from common.utils.params import SASDIR, TOTALS_DS
from .classes.BaseDataClass import BaseDataClass
from .classes.TableClass import TableClass
from .classes.TableClassWideTransform import TableClassWideTransform
from .classes.TableClassCountsOnly import TableClassCountsOnly
from .classes.TableClassDuals import TableClassDuals

def gen_tables(*, year, workbook, table_details, config_sheet_num, table_type):
    """
    Function gen_tables to generate excel tables
    params:
        year str: year to run
        workbook excel obj: template to write to
        table_details dict: dictionary with one table per key with details to write table
        table_type str: table to write (SUD or OUD)
        config_sheet_num str: name of sheet num param in config to pull for given table (sheet_num_sud or sheet_num_op)

    """

    # loop over all tables in table_details to create regular TableClass (default) or child class if specified
    # only run if specific config_sheet_num given in kwargs (not all tables run for OUD, and some few tables specified separately for SUD/OUD)

    for table, kwargs in table_details.items():

        sheet_num = kwargs.get(config_sheet_num, None)

        # only write table if sheet num for table type given in config

        if sheet_num:

            # identify class to use for given measure - TableClass is default

            use_class = kwargs.get('use_class', 'TableClass')

            # extract optional list of DS names to hard-code use of SUD counts (i.e. for OUD tables, will not append _op suffix to get full population counts)
            # must extract here to pass as arg to create BaseDataClass

            use_sud_ds = kwargs.pop('use_sud_ds', [])

            # create table class, set initial attributes, add sheet_num to pass with kwargs to set class attributes

            _tableclass = eval(use_class)(year, SASDIR(year), TOTALS_DS, table_type, workbook, use_sud_ds, **dict(kwargs, sheet_num=sheet_num))

            _tableclass.set_initial_attribs()

            # prep to write to tables

            _tableclass.prep_for_tables()

            # write to excel

            _tableclass.write_excel_sheet()
        


