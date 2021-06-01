def add_op_suffix(func):
    """
    Decorator add_op_suffix to decorate read_sas_data methods in table classes to add _op suffix to all input filenames if:
        - table_type is OUD AND
        - filename is not given in the list use_sud_ds (few filenames hard-coded to use only the SUD datasets for the OUD tables)

        If both of the above are not met, just use regular filename

    """

    def wrapper(*args, **kwargs):
        
        filename = kwargs.pop('filename')
        
        if (args[0].table_type == 'OUD') & (filename not in args[0].use_sud_ds):
            return func(*args, filename = f"{filename}_op", **kwargs)
        else:
            return func(*args, filename = filename, **kwargs)
    return wrapper