/**********************************************************************************************/
/*Program: 04_sud_nodx
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in the claims pulled in %SUD_INITIAL and identify benes with SUD conditions
/*         based on procedure, rev and POS codes (no diagnosis codes)
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/


%macro SUD_NODX;

	** To be identified with SUD without diagnosis code, must have 1 inpatient or 2+ outpatient/residential
       claims (on different service dates) that have SUD-specific procedure/rev/service place codes.

	** First, take the IP and OT (POS=21/51 only) files where records with only lab/transportation have
       been dropped, and join to the lookup tables of SUD-specific procedure and rev codes;

	%sud_inp_nodx(IP, nproc=6);
	%sud_inp_nodx(OT, nproc=1);

	** Take the above two tables and get a table of distinct benes with any claim marked as INP_SUD, and
	   with any claim marked as INP_OUD;

	execute (
		create temp table inp_bene_nodx as
		select submtg_state_cd,
		       msis_ident_num,
			   max(INP_SUD) as INP_SUD,
			   max(INP_OUD) as INP_OUD

		from (select distinct submtg_state_cd,
		                      msis_ident_num,
							  INP_SUD,
							  INP_OUD
			  from IP_inp_sud_nodx
			  where INP_SUD=1 

			  union all

			  select distinct submtg_state_cd,
		                      msis_ident_num,
							  INP_SUD,
							  INP_OUD
			  from OT_inp_sud_nodx
			  where INP_SUD=1 ) 

		group by submtg_state_cd,
		         msis_ident_num

	) by tmsis_passthrough;

	** Next must take outpatient/residential claims and join to the same lists (also including POS code),
	   then roll up to get one date per claim so can count whether two SUD claims on different service dates.
	   Also count the number of OUD services on different service dates.;

	%sud_outp_nodx(LT, 
                   tbl=HL2,
                   dates=srvc_endg_dt);

	%sud_outp_nodx(OT, 
                   tbl=HL_labt2, 
                   dates=srvc_endg_dt srvc_bgnng_dt srvc_endg_dt_line);


	** Take the LT and OT tables of SUD claims and get a table of distinct bene/dates with any claim marked as OUTP_SUD;

	execute (
		create temp table outp_sud_nodx as
		select submtg_state_cd,
		       msis_ident_num,
			   srvc_dt,
			   sum(OUTP_OUD) as OUTP_OUD

		from (select submtg_state_cd,
		             msis_ident_num,
					 srvc_dt,
					 max(OUTP_OUD) as OUTP_OUD
			  from LT_outp_sud_nodx2
			  group by submtg_state_cd,
			           msis_ident_num,
					   srvc_dt

			  union all

			  select submtg_state_cd,
		             msis_ident_num,
					 srvc_dt,
					 max(OUTP_OUD) as OUTP_OUD
			  from OT_outp_sud_nodx2
              group by submtg_state_cd,
			           msis_ident_num,
                       srvc_dt) 

		group by submtg_state_cd,
		         msis_ident_num,
				 srvc_dt

	) by tmsis_passthrough;

	** Join the inpatient bene-level table with the outpatient bene/date-level table (after aggregating to bene-level)
	   to identify all benes with SUD identified through either inpatient or outpatient, AND all benes identified as OUD
	   with at least one inpatient and at least two outpatient dates;

	execute (
		create temp table BENE_SUD_NODX as
		select coalesce(a.submtg_state_cd,b.submtg_state_cd) as submtg_state_cd,
		       coalesce(a.msis_ident_num,b.msis_ident_num) as msis_ident_num,
			   a.INP_SUD,
			   a.INP_OUD,
			   b.NDATES_OUTP_SUD,
			   b.NDATES_OUTP_OUD,
			   case when NDATES_OUTP_SUD>1 
			        then 1 else 0
					end as OUTP_SUD2,
			   case when NDATES_OUTP_OUD>1 
			        then 1 else 0
					end as OUTP_OUD2,

			   case when INP_SUD=1 or OUTP_SUD2=1
			        then 1 else 0
					end as POP_SUD_NODX,

			   case when INP_OUD=1 or OUTP_OUD2=1
			        then 1 else 0
					end as OUD_NODX

		from inp_bene_nodx a
		     full join
			 (select submtg_state_cd, 
                     msis_ident_num, 
                     count(*) as NDATES_OUTP_SUD,
					 sum(OUTP_OUD) as NDATES_OUTP_OUD
              from outp_sud_nodx 
              group by submtg_state_cd, 
                       msis_ident_num) b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

	) by tmsis_passthrough;

%mend SUD_NODX;
