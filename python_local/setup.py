from setuptools import setup, find_packages

setup(
    name='sud_databook_tables',
    version='0.1.0',
    description='Package to create SUD databook tables',
    packages=find_packages("sud_databook_tables"), 
    package_dir={"": "sud_databook_tables"},
    author='Rosalie Malsberger', 
    author_email='rmalsberger@mathematica-mpr.com',
    license='Mathematica',
    entry_points={
        'console_scripts': [
            'write_db_tables  = write_db.cli:main',
            'compare_versions = compare_versions.compare_versions:main'
        ],
    },
)