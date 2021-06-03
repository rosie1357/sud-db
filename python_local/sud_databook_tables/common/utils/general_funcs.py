"""
general functions
"""

import logging
import yaml
import pandas as pd
import os
import re
from pathlib import Path

from common.utils.params import TOTALS_DS

# define variable_matcher to be passed to yaml.add_implicit_resolver to match pattern of ${} in yaml load to
# identify variables to resolve

variable_matcher = re.compile(r'\$\{(\w+)\}')

def variable_constructor(loader, node):
    """
    Function variable_constructor to be passed to yaml.add_constructor to extract variable names from passed
    yaml params and return variable value

    """
    
    value = node.value
    match = variable_matcher.match(value)

    return eval(match.groups()[0])
    

def read_config(*, config_dir, config_name='config.yaml', **kwargs):
    """
    Function read_config to read yaml config file and return file after conversion to python object
    
    params:
        config_dir Path: directory with config file
        config_name str: optional name of config file (default is config.yml)
        kwargs dict: optional dictionary to pass constructors to add to yaml if needed,
            must be passed in form of constructor name as key, then values of matcher and constructor equal to match and construct functions
            example: 
                variable_match = {'matcher' : variable_matcher, 'constructor' : variable_constructor}
                where variable_matcher is regex compiler to match expression, variable_constructor is function to return evaluated matched group 0
    
    returns:
        dict: dictionary of input yaml config file
    """
    
    # if matcher and constructor dict passed in kwargs, add to yaml reader
    
    for construct_name, values in kwargs.items():
    
        yaml.add_implicit_resolver(construct_name, values['matcher'], None, yaml.SafeLoader)
        yaml.add_constructor(construct_name, values['constructor'], yaml.SafeLoader)

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