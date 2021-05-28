def add_op_suffix(func):
    """
    Decorator add_op_suffix to decorate read_sas_data methods in table classes to add _op suffix to all input filenames if table is OUD,
    otherwise just use given filename

    """

    def wrapper(*args, **kwargs):
        
        filename = kwargs.pop('filename')
        
        if args[0].table_type == 'OUD':
            return func(*args, filename = f"{filename}_op", **kwargs)
        else:
            return func(*args, filename = filename, **kwargs)
    return wrapper