
import numpy as np
from scipy import stats

def two_proportions_test(success_a, size_a, success_b, size_b):
    """
    Code taken from http://ethen8181.github.io/machine-learning/ab_tests/frequentist_ab_test.html#Comparing-Two-Proportions

    A/B test for two proportions;
    given a success a trial size of group A and B compute
    its zscore and pvalue
    
    Parameters
    ----------
    success_a, success_b : int
        Number of successes in each group
        
    size_a, size_b : int
        Size, or number of observations in each group
    
    Returns
    -------

    pvalue : float
        p-value for the two proportion z-test
    """
    prop_a = success_a / size_a
    prop_b = success_b / size_b
    prop_pooled = (success_a + success_b) / (size_a + size_b)
    var = prop_pooled * (1 - prop_pooled) * (1 / size_a + 1 / size_b)
    zscore = np.abs(prop_b - prop_a) / np.sqrt(var)
    one_side = 1 - stats.norm(loc = 0, scale = 1).cdf(zscore)
    pvalue = one_side * 2
    return pvalue


def two_proportions_confint(success_a, size_a, success_b, size_b, significance = 0.05, default_exception = 'NA'):
    """
    Code taken from http://ethen8181.github.io/machine-learning/ab_tests/frequentist_ab_test.html#Comparing-Two-Proportions
    
    A/B test for two proportions;
    given a success a trial size of group A and B compute
    its confidence interval;
    resulting confidence interval matches R's prop.test function

    Parameters
    ----------
    success_a, success_b : int
        Number of successes in each group

    size_a, size_b : int
        Size, or number of observations in each group

    significance : float, default 0.05
        Often denoted as alpha. Governs the chance of a false positive.
        A significance level of 0.05 means that there is a 5% chance of
        a false positive. In other words, our confidence level is
        1 - 0.05 = 0.95

    default_exception str : default value to return if any input values are invalid and stat cannot be calculated
        (eg if value is string), default is NA

    Returns
    -------

    confint : list
        Confidence interval of the two proportion test
    """

    try:

        prop_a = success_a / size_a
        prop_b = success_b / size_b
        var = prop_a * (1 - prop_a) / size_a + prop_b * (1 - prop_b) / size_b
        se = np.sqrt(var)

        # z critical value
        confidence = 1 - significance
        z = stats.norm(loc = 0, scale = 1).ppf(confidence + significance / 2)

        # standard formula for the confidence interval
        # point-estimtate +- z * standard-error
        prop_diff = prop_b - prop_a
        confint = prop_diff + np.array([-1, 1]) * z * se
        
        return list(confint)

    except:
        return default_exception


def p_adjust_bh(p):
    
    # taken from https://stackoverflow.com/questions/7450957/how-to-implement-rs-p-adjust-in-python/33532498#33532498
    
    """Benjamini-Hochberg p-value correction for multiple hypothesis testing."""
    
    p = np.asfarray(p)
    by_descend = p.argsort()[::-1]
    by_orig = by_descend.argsort()
    steps = float(len(p)) / np.arange(len(p), 0, -1)
    q = np.minimum(1, np.minimum.accumulate(steps * p[by_descend]))
    return q[by_orig]