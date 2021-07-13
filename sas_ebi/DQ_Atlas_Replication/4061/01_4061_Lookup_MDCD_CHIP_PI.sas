/*********************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                   */
/* This code cannot be copied, distributed or used                   */
/* without the express written permission of                         */
/* Mathematica Policy Research, Inc.                                 */
/*********************************************************************/
*====================================================================*         
*                PROJECT 50139 MACBIS - TASK4                        *                 
*====================================================================*;
* PROGRAM NAME: 01_Read MDCD_CHIP_PI.sas                                                           
* PROGRAMMER  : Preeti Gill                                                
* DESCRIPTION : Read Medicaid CHIP PI data for given year
* MODIFICATION: 
*====================================================================*;          
*====================================================================*;          
* 2. Import PI data.                                                 *;
*====================================================================*;    
%let lookup = &progpath./4061_Medicaid_Enrollment;

proc sql;
   %tmsis_connect;

   %droptable(PIdata_&year.);
	execute(
	   create table if not exists &dbname..&prefix.PIdata_&year. as
	   select  state_cd
			   ,rptg_prd_strt_dt
			   ,enrlmt_mdcd_tot_cnt 
			   ,enrlmt_chip_tot_cnt
			   ,final_report

	   from pimcee.performance_indicator

	  where final_report='Y' 
	        and year(rptg_prd_strt_dt) =&year.

	) by tmsis_passthrough;

	create table PI_&year. as select * from connection to tmsis_passthrough
		(select * from &dbname..&prefix.PIdata_&year. 
                  order by state_cd,rptg_prd_strt_dt);
   %tmsis_disconnect;
quit;
%states_expected(lookup_dsn = PI_&year., state_name = state_cd, abbr = yes);

data PI_&year.;
merge PI_&year.;

format rptg_dt yymmn6.;
*rptg_dt=datepart(RPTG_PRD_STRT_DT);
rptg_dt=RPTG_PRD_STRT_DT;
ENRLMT_TOT_CNT=sum(of ENRLMT_MDCD_TOT_CNT ENRLMT_CHIP_TOT_CNT);

/*For CA and AZ, if total count is not equal to MDCD count then flag*/
if ENRLMT_TOT_CNT^=ENRLMT_MDCD_TOT_CNT then flag=1;
else flag=0;
run;

proc sort data = PI_&year.;
by submtg_state_Cd rptg_dt;
run;



/**MDCD Enrollment**/
proc transpose data=PI_&year 
               out=PI_mdcd_&year.(drop=_NAME_ _LABEL_) prefix=mdcd_;
   by submtg_state_Cd;
   id rptg_dt;
   var ENRLMT_MDCD_TOT_CNT;
run;


**-- Create insert statements;
%aremac_insert(dsname = pi_mdcd_&year., lookup_path = &lookup.)

**--Add to AREMAC workbench;
%macro add_lookup(dsname);
	proc sql;
		%tmsis_connect;

		%droptable(&dsname.)
		%include "&lookup./&dsname..txt";

		select * from connection to tmsis_passthrough
		(select * from &dbperm..&prefix.&dsname.);
	%tmsis_disconnect;
	quit;
%mend add_lookup;
%add_lookup(pi_mdcd_&year.);
