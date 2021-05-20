
from .utils.params import SASDIR, TOTALS_DS
from .classes.data_classes import BaseDataClass, TableClass


def gen_tables(*, year, version, workbook, table_details):
    """
    Function gen_tables to generate excel tables
    params:
        year str: year to run
        version str: version of TAF
        workbook excel obj: template to write to
        table_details dict: dictionary with one table per key with details to write table

    """

    # loop over all tables in table_details to create TableClass - initialize with args to pass to BaseDataClass and kwargs to pass to TableClass

    for table, kwargs in table_details.items():

        _tableclass = TableClass(year, SASDIR(year), TOTALS_DS, workbook, **kwargs)

        _tableclass.write_excel_sheet()
        


