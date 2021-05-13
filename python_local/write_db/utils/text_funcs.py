
from functools import reduce

def pct_list(x):
    return [x, f"{x}_pct"]

def create_text_list(*, base_list, return_list_func, init_list=[]):
    """
    Function create_text_list to return a list of text strings combined after manipulation on each input list text element
    params:
        base_list list: list of initial text strings to apply specific function to to expand each element of list
        return_list_func: function to be applied to each input string element which will return a list based on that element
            e.g. if return_list_func is a function that returns the element and the element + _pct, the new list will contain the passed element 
                 plus the element + _pct, with each pair next to each other: if base_list = ['a','b'] then return will be ['a','a_pct','b','b_pct']
        init_list list: list to initialize with, default is empty

    returns:
        list of text elements with function applied
        
    """

    return reduce(lambda lst, x: lst + return_list_func(x), base_list, init_list)