
from common.utils.params import SASDIR, TOTALS_DS
from .classes.BaseDataClass import BaseDataClass
from .classes.TableClass import TableClass
from .classes.TableClassWideTransform import TableClassWideTransform
from .classes.TableClassCountsOnly import TableClassCountsOnly
from .classes.TableClassDuals import TableClassDuals
from .classes.TableClassCompYears import TableClassCompYears

def gen_tables(*, year, workbook, table_details, config_sheet_num, table_type, pyr_comp, g_table_details = {}):
    """
    Function gen_tables to generate excel tables
    params:
        year str: year to run
        workbook excel obj: template to write to
        table_details dict: dictionary with one table per key with details to write table
        table_type str: table to write (SUD or OUD)
        config_sheet_num str: name of sheet num param in config to pull for given table (sheet_num_sud or sheet_num_op)
        pyr_comp bool: boolean to specify read in prior year SAS datasets and create G tables (will only ever be run for SUD tables, if requested)
        g_table_details dict: dictionary of G table mappings with one input SUD sheet per key with details to write each corresponding G table, default is empty dict

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

            # if pyr_comp == True (prior year comparison G tables are requested), check if sheet_num_sud attribute for _tableclass is one of the keys
            # in g_table_details (i.e. stats from SUD table number are used for any G tables) - if so, create prior year _tableclass

            if (pyr_comp == True) & (_tableclass.sheet_num in g_table_details.keys()):

                pyear = int(year)-1

                _tableclass_p = eval(use_class)(pyear, SASDIR(pyear), TOTALS_DS, table_type, workbook, use_sud_ds, **dict(kwargs, sheet_num=sheet_num))

                _tableclass_p.set_initial_attribs()

                _tableclass_p.prep_for_tables()

                # write all G sheets for given G details key

                for g_sheet_num, comp_cols in g_table_details[_tableclass.sheet_num].items():

                    _tableclassComp = TableClassCompYears(_tableclass.prepped_df, _tableclass_p.prepped_df, workbook, g_sheet_num, comp_cols)

                    _tableclassComp.prep_for_tables()

                    _tableclassComp.write_excel_sheet()


