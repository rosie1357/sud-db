/************************************************************************************
* © 2020 Mathematica Inc. 
* The Covid Analytics Code using TAF was developed by Mathematica Inc. as part 
* of the MACBIS Business Analytics and Data Quality Development project funded by 
* the U.S. Department of Health and Human Services – Centers for Medicare and 
* Medicaid Services (CMS) through Contract No. HHSM-500-2014-00034I/HHSM-500-T0005 
*************************************************************************************/
/*************************************************************************/
/*** organization : Mathematica Policy Research
/*** project      : 50139 MACBIS, Task 4 and 5
/*** program      : RUN_02_COVID_DQ.sas
/*** author       : Preeti Gill
/*** purpose      : Automate running select issue briefs for monthly outputs
/*************************************************************************/

options noerrorabend;

%let year = 2020;

**Set scratch buckets;
%let dqatlas = macbis_tafdq_perm.dq2019_0503_;
%let dbname  = mprscratch;
%let dbperm  = mprscratch;
%let prefix  = suddb&year.;

**Set path parameters;

%let basepath  = /sasdata/users/gyg9/tmsisshare/prod/Task_4_and_5_TAF_analyses/020_SUD_DB_2020/DQ_Measures;


** Assign a the rest of DQ specific paths and libname;
%let logpath   = &basepath./Log_Lst;
%let datapath  = &basepath./Output;

%let progpath  = &basepath./Programs;

** Add the global files;
%include "&progpath./99_global_include.sas";

libname out "&datapath.";

** List of all issue briefs and years to run ;
%let briefs  = 4061 5111 5131;

**List all of the claim type codes to use;
%let clm_type_keep_ib = %str('1','A','3','C','U','W');

**Output state files;
%macro output(briefnum);

proc sql;
%tmsis_connect;
create table out.DQ&briefnum. as
select * from connection to tmsis_passthrough
(
select * 
from 
&dbperm..&prefix.&briefnum._fnl
);

%tmsis_disconnect;
quit;
%mend;



** Call and insert state lookup;
%state_dummy_table;



*====================================================================*;
* Run IB Process;
*====================================================================*;
%macro run_autib;

	proc printto log="&logpath./SUD_DQ_Measures_&year._&sysdate..log"
                 print="&logpath./SUD_DQ_Measures_&year._&sysdate..lst" new;
	run;

	ods html close;
	ods _all_ close;
	ods html body="&logpath./SUD_DQ_Measures_&year._&sysdate..html" style=HTMLBlue;

	** Drop all temp tables (if exist);

/*	%drop_all(schemaname=&dbname., prefix_drop=&prefix.);*/
/**/
/*	*Create views in AREMAC;*/
/**/
/*	%create_views;*/
/**/
/*	** Run all the issue briefs;*/
/*	%IB_timestamp_log(4061);*/
/*	%include "&progpath./4061_Medicaid_Enrollment/00_4061_Driver.sas";*/
/*	%output(4061);*/

	%IB_timestamp_log(5111);
	%include "&progpath./5111_Claims_Volume/00_5111_Driver.sas";
	%output(5111);

/*	%IB_timestamp_log(5131);*/
/*	%include "&progpath./5131_Missing_and_Invalid_Dx/00_5131_Driver.sas";*/
/*	%output(5131);*/
/**/
/*	%IB_timestamp_log(Complete);*/
/*	*/
	ods html close;

	proc printto;
	run;
	
%mend;
%run_autib;


proc export data =out.DQ4061 outfile="&basepath./SUD_DQMeasures_&sysdate..xlsx" dbms = xlsx replace;
sheet = "4061";
run;

proc export data =out.DQ4061 outfile="&basepath./SUD_DQMeasures_&sysdate..xlsx" dbms = xlsx replace;
sheet = "5111";
run;

proc export data =out.DQ5131 outfile="&basepath./SUD_DQMeasures_&sysdate..xlsx" dbms = xlsx replace;
sheet = "5131";
run;
