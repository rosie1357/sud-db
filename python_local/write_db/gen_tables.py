
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

    # create instance of BaseDataClass to use to initialize all TableClass instances

    _baseclass = BaseDataClass(year = year, sas_dir = SASDIR(year), workbook = workbook, totals_ds = TOTALS_DS)

    # loop over all tables in table_details to create TableClass 

    for table, details_dict in table_details.items():

        _tableclass = TableClass(baseclass_inst = _baseclass, details_dict = details_dict)

        _tableclass.write_excel_sheet()
        


