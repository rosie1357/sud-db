"""
general functions
"""

import logging
import yaml
import pandas as pd
import os
from pathlib import Path

def read_config(*, config_dir, config_name='config.yaml'):
    """
    Function read_config to read yaml config file and return file after conversion to python object
    
    params:
        config_dir Path: directory with config file
        config_name str: optional name of config file (default is config.yml)
    
    returns:
        dict: dictionary of input yaml config file
    """

    with open(config_dir / config_name) as f:
        config = yaml.safe_load(f)
    return config

def get_current_path(sub_dirs = ''):
    """
    Function get_current_path to return the current path from which the function is called (as a Path object),
    with optional sub directories if requested

    params:
        sub_dirs str: string of optional subdirectories to be appended to path, separated by forward slash if >1
            example: 'src/utils'

    returns:
        Path object

    """

    return Path(os.getcwd()) / sub_dirs

def func_name(func=None):
    """
    Function func_name to decorate functions to return internal name while in function    
    
    """
    def wrapper(*args, **kwargs):
        try:
            function_name = func.__func__.__qualname__
        except:
            function_name = func.__qualname__
        return func(*args, **kwargs, function_name=function_name)
    return wrapper


def print_to_log(*, message, records, print_index=False):
    """
    Function print_to_log to print message and input df to log
    
    params:
        message str: message to print
        records df: df to print after message (will print all input records/columns)  
        print_index boolean: boolean to write index when printing df - default is False (does not print index)
    
    returns:
        none
    
    """
    
    logging.info(f"\n{message}:\n")
    logging.info(f"{records.to_string(index=print_index)}") 
    
    
def crosstab(*, df, groupcols):
    """
        Function crosstab to create df with counts of records by groupcols cols
        
        params:
            df: input df
            groupcols list: list of cols to group by
            
        returns:
            df with one rec per every combo of groupcols values with row count    
    
    """
    
    cf = df.copy()
    
    cf['count'] = 1
    
    counts = pd.DataFrame(cf.groupby(groupcols)['count'].count())
    counts.reset_index(inplace=True)
    
    return counts

def generate_logger(*, logdir, logname, packages_suppress = ['boto3','botocore','numexpr'], suppress_addtl = [], init_message = None):
    """
    Function generate_logger to generate log file for given directory and log name. Sets level to INFO
    
    params:
        logdir Path: directory for log file
        logname str: name of log file
        packages_suppress list: default list of packages to set logging level to critical to prevent notes to log
        suppress_addtl list: additional packages to suppress, default is none
        init_message str: optional initial message to write to log, default is none
        
    returns:
        logger

    """
    
    logging.basicConfig(filename=logdir / logname, filemode='w', level=logging.INFO, format='%(message)s')
    
    # for given packages to suppress, set levels to critical
    
    for package in packages_suppress + suppress_addtl:
        logging.getLogger(package).setLevel(logging.CRITICAL)
        
    if init_message is not None:
        logging.info(init_message)
    
    return logging