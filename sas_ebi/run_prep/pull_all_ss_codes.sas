/**********************************************************************************************/
/*Program: pull_all_ss_codes
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 06/2021
/*Purpose: Pull all SS proc codes and export to Excel
/***********************************************************************************************/

libname tmsi_lib SASIORST PRESERVE_COL_NAMES=YES PRESERVE_TAB_NAMES=YES
         dsn=RedShift  authdomain="AWS_TMSIS_QRY" ;

%let basedir=/sasdata/users/&sysuserid/tmsisshare/prod/Task_4_and_5_TAF_analyses/020_SUD_DB_2020;
%let year=2020;

%include "&basedir./Programs/99_sud_inner_macros.sas";

proc sql;
	%tmsis_connect;

	create table codes as select * from connection to tmsis_passthrough
	(select distinct submtg_state_cd, vld_val, vld_val_desc
	from cms_prod.vld_val_rfrnc 
	where vld_val_type='STATE' and de_name='PROCEDURE-CODE' );

	proc export data=codes dbms=xlsx outfile="&basedir./Excel/State_Specific_Proc_Codes_Raw_20210614.xlsx" replace;
	run;