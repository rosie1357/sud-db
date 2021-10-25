# ** SUD Databook Code **

There are two parts to this repo: the SAS EBI code to run all the programs to pull from TAF and produce all the output for the databook, and the local python code to create the formal Excel tables.

## 1. SAS EBI code

.. will add

## 2. Local python code 

The code to run locally in python to create the formal tables for the databook is located in the python_local subfolder [here](./python_local). The tables are populated by reading in the datasets created on EBI, rearranging them and creating stats (e.g. %s, rates), and then writing by cell to the empty table templates. This section details (A) how to run the code and (B) how the code is structured/what to update before running.

### A. How to run

This project uses pipenv to manage package depencies, and to add the main  **sud_databook_tables** as a package to then easily call the individual modules using entry points.

To create the virtual environment using the [Pipfile](./python_local/Pipfile), navigate to this folder in Git bash or terminal of your choice, and submit the following:

```bash
pipenv update
```

To enter the virtual env so that all commands given at the terminal are run in the virtual env, submit the following command:

```bash
pipenv shell
```

Note that each of the modules are added as entry points in [setup.py](./python_local/setup.py) so they can be run in the virtual env with command shortcuts. The main module to create the tables is [write_db_tables](./python_local/sud_databook_tables/write_db). (NB. There are two additional modules defined but this README won't cover those as they were just run ad-hoc.)

To run the main module, you can use the entry point defined in [setup.py](./python_local/setup.py) that is set to run the `main()` function within the module's [cli.py](./python_local/sud_databook_tables/write_db/cli.py) script. This call takes one required `(--year)` and one optional `(--pyr_comp)` parameter.

`--year` must be set to the year of the databook you are running.
`--pyr_comp` is a boolean that indicates whether comparisons to the prior year's databook should be run. The default is True.

Submit the following commands:

```bash
pipenv update
pipenv shell
write_db_tables --year 2020
```

Note that the pipenv commands are only required if you need to update and then enter the virtual env shell.

### B. Code structure/What to update

As noted above, the module to create tables is called via the `main()` function within the module's [cli.py](./python_local/sud_databook_tables/write_db/cli.py) script.

Note there is one main set of tables (the SUD tables), and a companion set of tables (the OUD tables) that are always created. The OUD tables contain some of the main tables subset to a specific population of those identified as having OUD. The G tables contain comparisons to the prior year and are only created if `--pyr_comp` was set to True.

- The first thing it does is read in the [config.yaml](./python_local/sud_databook_tables/write_db/config/config.yaml) file to get the needed information on how to run each table. This is the most important file in the module! This file is structured with two outer dictionaries:
    1. **TABLE_MAPPINGS** is the dictionary for the main set of tables. There is one key per table (sheet). Within each key is all the information needed to run that table, including e.g. which sheet it maps to (`sheet_num_sud`), which SAS variables to read in as numerators (`numerators`), etc.
    2. **G_TABLE_MAPPINGS** is the dictionary to populate the supplemental G tables, which create comparisons to the prior year. There is one key per main table. Within each key are key-value pairs where the key is the G table to be populated with that main table's information, and the value is a list of columns from that main table to pull in.

- The next thing it does is open the table shells (see below for instructions on how to update paths to those if needed). It then calls the main function [gen_tables](./python_local/sud_databook_tables/write_db/gen_tables.py) to do all processing and write to each sheet.

- The final step is saving the populated templates with the year and date information in the file names.
