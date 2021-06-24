
from common.utils.params import SASDIR, TOTALS_DS, DQ_STATES, DQ_STATES_PYEAR
from .classes.BaseDataClass import BaseDataClass
from .classes.TableClass import TableClass
from .classes.TableClassWideTransform import TableClassWideTransform
from .classes.TableClassCountsOnly import TableClassCountsOnly
from .classes.TableClassDuals import TableClassDuals
from .classes.TableClassG import TableClassG
from .classes.TableClassCompYears import TableClassCompYears

def gen_tables(*, year, workbook, table_details, config_sheet_num, table_type, pyr_comp, g_table_details={}, workbook_pyear=None):
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
        workbook_pyear excel obj: excel obj to write comparison tables to if pyrcomp, default is None


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

            _tableclass = eval(use_class)(year, SASDIR(year), TOTALS_DS, table_type, workbook, use_sud_ds, DQ_STATES, **dict(kwargs, sheet_num=sheet_num))

            _tableclass.set_initial_attribs()

            # prep to write to tables

            _tableclass.prep_for_tables()

            # write to excel

            _tableclass.write_excel_sheet()

            # if pyr_comp == True (prior year stand-alone tables and comparison G tables are requested), create prior year TableClass with prepped df,
            # then write two sets of comparisons:
            #   1. Comparisons specified in main config for stand-alone tables (if exists)
            #   2. Loop over any G sheets specified for given table in g_table_details (if there are any - most sheets do not contribute to any G tables)

            if pyr_comp == True:

                pyear = int(year)-1

                _tableclass_p = eval(use_class)(pyear, SASDIR(pyear), TOTALS_DS, table_type, workbook, use_sud_ds, DQ_STATES_PYEAR, **dict(kwargs, sheet_num=sheet_num))

                _tableclass_p.set_initial_attribs()

                _tableclass_p.prep_for_tables()

                # write comparison sheet if _tableclass attrib for comparison_value is not None (i.e. no corresponding comparison sheet for sheet)

                if _tableclass.comparison_value != 'None':

                    _tableclassCompYears = TableClassCompYears(_tableclass, _tableclass_p.prepped_df, workbook_pyear)

                    _tableclassCompYears.write_excel_sheet()

                # write all G sheets for given G details key if exists

                if _tableclass.sheet_num in g_table_details.keys():

                    for g_sheet_num, comp_cols in g_table_details[_tableclass.sheet_num].items():

                        _tableclassG = TableClassG(_tableclass.prepped_df, _tableclass_p.prepped_df, workbook, g_sheet_num, comp_cols)

                        _tableclassG.write_excel_sheet()


