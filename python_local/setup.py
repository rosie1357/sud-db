from setuptools import setup, find_packages

setup(
    name='sud_db_tables',
    version='0.1.0',
    description='Package to write SUD db tables',
    packages=find_packages(),
    author='Rosalie Malsberger', 
    author_email='rmalsberger@mathematica-mpr.com',
    license='Mathematica',
    entry_points={
        'console_scripts': [
            'write_db_tables  = src.cli:main',
        ],
    },
)