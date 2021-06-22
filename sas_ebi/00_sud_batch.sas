/**********************************************************************************************/
/*Program: 00_sud_batch
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Submit the programs for the SUD databook
/*Mod: 
/*Notes: 
/***********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

libname tmsi_lib SASIORST PRESERVE_COL_NAMES=YES PRESERVE_TAB_NAMES=YES
         dsn=RedShift  authdomain="AWS_TMSIS_QRY" ;

options linesize=220 center nosymbolgen mprint;

%let basedir=/sasdata/users/&sysuserid/tmsisshare/prod/Task_4_and_5_TAF_analyses/020_SUD_DB_2020;
%let year=2020;

** List of states to exclude;

%let states_exclude=%nrstr('99');

proc printto 
	log="&basedir./Log_Lst/sud_batch_&year._&sysdate..log"
	print="&basedir./Log_Lst/sud_batch_&year._&sysdate..lst"
	new;
run; 

%include "&basedir./Programs/01_sud_initial.sas";
%include "&basedir./Programs/02_sud_tool1.sas";
%include "&basedir./Programs/03_sud_dx_only.sas";
%include "&basedir./Programs/04_sud_nodx.sas";
%include "&basedir./Programs/05_sud_analytic_pop.sas";
%include "&basedir./Programs/06_sud_claims_pull.sas";
%include "&basedir./Programs/07_sud_claims_assign.sas";
%include "&basedir./Programs/08_sud_claims_count.sas";
%include "&basedir./Programs/09_sud_claims_progression.sas";
%include "&basedir./Programs/99_sud_inner_macros.sas";
%include "&basedir./Programs/99_sud_macro_lists.sas";

%let indata=&basedir./Indata;

libname sasout "&basedir./Output";
%let qcout=&basedir./Output/QC;
libname qcout "&qcout.";
%let indata=&basedir./Indata;

options nomlogic nomprint minoperator errorabend;

** Determine if year is a leap year - if so, set ndays=366, otherwise set ndays=365;

%global leap;
%global totdays;
%leapyear;

%put leap for &year. = &leap. with &totdays. days;

%let tool1_excel = %str(50139 SUD Code set_2020 Revision_Reformatted.xlsx);
%let db_excel = %str(T-MSIS data book code lists_2019.xlsx);

** Run the tool 1 macro to read from tool 1 excel with codes and create text files with text to create tables;

%create_tool1_lookups(excel=&tool1_excel.);

** Run the macro to create the text files which have the text to create lookup tables of
   procedure, revenue, TOB and POS codes;

%redshift_insert_sud_codes(excel=&db_excel.);
%redshift_insert_mapping(excel=&db_excel.);


proc sql;
	%tmsis_connect;

	title1 'SUD 0: INITIAL PREP MACRO';

	%SUD_INITIAL;

	title1 'SUD 1: TOOL 1 SUD IDENT (METHOD 1)';

	%SUD_TOOL1;

	title1 'SUD 2: DIAGNOSIS CODE ONLY SUD IDENT (METHOD 2)';

	%SUD_DX_ONLY;

	title1 'SUD 3: NO DIAGNOSIS CODE SUD IDENT (METHOD 3)';

	%SUD_NODX;

	title1 'SUD 4: CREATE ANALYTIC POP JOINING ALL THREE METHODS';

	%SUD_ANALYTIC_POP;

	title1 'SUD 5: PULL ALL SUD CLAIMS FOR ANALYTIC POP';

	%SUD_CLAIMS_PULL; 

	title1 'SUD 6: ASSIGN SUD CLAIMS TO SETTING/SERVICE TYPE';

	%SUD_CLAIMS_ASSIGN;

	title1 'SUD 7: COUNT SUD SERVICES (CLAIMS OR DAYS)';

	%SUD_CLAIMS_COUNT;

	title1 'SUD 8: SUD CLAIMS PROGRESSION FROM INPATIENT/RESIDENTIAL';

	%SUD_CLAIMS_PROGRESSION; 

quit;


proc printto;
run;
