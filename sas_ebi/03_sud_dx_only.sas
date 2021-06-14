/**********************************************************************************************/
/*Program: 03_sud_dx_only
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in the claims pulled in %SUD_INITIAL and identify benes with SUD conditions
/*         based on diagnosis codes only
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/


%macro SUD_DX_ONLY;

	** Assign benes to conditions based on ONE inpatient claim (IP or OT) or TWO outpatient/residential claims (LT or OT).
	   First stack the IP and OT (POS=21 or 51 only) and take the MAX across all condition indicators.
	   Subset to SUD_DGNS=1;

	execute (
		create temp table inp_claims as
		(select submtg_state_cd, 
		       msis_ident_num
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,&ind._SUD_DSRDR_DGNS
				%end;
		from IPHL_labt2
        where SUD_DGNS=1 )

		union all

		(select submtg_state_cd, 
		       msis_ident_num
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,&ind._SUD_DSRDR_DGNS
				%end;
		from OTHL_labt2
        where srvc_plc_cd in ('21','51') and SUD_DGNS=1 )

	) by tmsis_passthrough;

	** Take MAX to get to bene level;

	execute (
		create temp table inp_bene as
		select submtg_state_cd,
		       msis_ident_num
				%do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,max(&ind._SUD_DSRDR_DGNS) as &ind._SUD_DSRDR_DGNS1
				 %end;

		from inp_claims
		group by submtg_state_cd,
		         msis_ident_num

	) by tmsis_passthrough;

	** Now must identify conditions based on TWO claims on different service dates from
	   outpatient or residential - note must first create service date (using same rule as in
	   tool 1), then count unique service dates for each condition.
	   For OT we will need to subset to POS != 21, 51;

	%rollup_dgns_only(LT, 
                      tbl=HL2,
                      dates=srvc_endg_dt);

	%rollup_dgns_only(OT, 
                      tbl=HL_labt2, 
                      dates=srvc_endg_dt srvc_bgnng_dt srvc_endg_dt_line);

	** Union the above LT and OT claim-level files;

	execute (
		create temp table outp_claims as
		(select submtg_state_cd, 
		       msis_ident_num,
			   srvc_dt
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,&ind._SUD_DSRDR_DGNS
				%end;
		from LT_rollup_dgns )

		union all

		(select submtg_state_cd, 
		       msis_ident_num,
			   srvc_dt
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,&ind._SUD_DSRDR_DGNS
				%end;
		from OT_rollup_dgns )

	) by tmsis_passthrough;

	** Roll up to the bene/date level in the inner query, and then in the outer query, count the
	   number of unique service dates for each condition and assign the condition for those with 2+;

	execute (
		create temp table outp_bene as

		select submtg_state_cd,
		       msis_ident_num
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,sum(&ind._SUD_DSRDR_DGNS) as &ind._SUD_DSRDR_DGNS2_SUM
				%end;

		from (
	 
			select submtg_state_cd,
			       msis_ident_num,
				   srvc_dt
				   %do s=1 %to %sysfunc(countw(&indicators.));
				       %let ind=%scan(&indicators.,&s.);
					   ,max(&ind._SUD_DSRDR_DGNS) as &ind._SUD_DSRDR_DGNS
					%end;

			from outp_claims
			group by submtg_state_cd,
			         msis_ident_num,
				     srvc_dt )

		group by submtg_state_cd,
		         msis_ident_num

	) by tmsis_passthrough;

	** Join the inp and outp bene-level tables to identify benes with a condition from
       EITHER (must have count of 2 from outp table);

	execute (
		create temp table BENE_SUD_DX_ONLY as
		select coalesce(a.submtg_state_cd,b.submtg_state_cd) as submtg_state_cd,
		       coalesce(a.msis_ident_num,b.msis_ident_num) as msis_ident_num

				%do s=1 %to %sysfunc(countw(&indicators.));
				     %let ind=%scan(&indicators.,&s.);
					 ,&ind._SUD_DSRDR_DGNS1
					 ,case when &ind._SUD_DSRDR_DGNS2_SUM>1 
					       then 1 else 0
						   end as &ind._SUD_DSRDR_DGNS_OUTP

					%if &ind. ne PLYSBSTNCE %then %do;

						 ,case when &ind._SUD_DSRDR_DGNS1=1 or &ind._SUD_DSRDR_DGNS2_SUM>1
						       then 1 else 0
							   end as SUD_&ind._DX_ONLY
					%end;

				%end;

				/* Count the number of conditions, and create PLYSBSTNCE for those with 2+ OR where the original PLYSBSTNCE = 1. */

				,%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);
					%if &ind. ne PLYSBSTNCE %then %do;
						%if &s. > 1 %then %do; + %end;
						SUD_&ind._DX_ONLY
					%end;
				 %end; 
				 as CNT_SUD_DX_ONLY

				 ,case when CNT_SUD_DX_ONLY > 1 or (PLYSBSTNCE_SUD_DSRDR_DGNS1=1 or PLYSBSTNCE_SUD_DSRDR_DGNS2_SUM>1)
				       then 1 else 0
					   end as SUD_PLYSBSTNCE_DX_ONLY

				,case when CNT_SUD_DX_ONLY > 0 or SUD_PLYSBSTNCE_DX_ONLY=1
					   then 1 else 0
					   end as POP_SUD_DX_ONLY


		from inp_bene a
		     full join
			 outp_bene b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

	) by tmsis_passthrough;

	title2 "Creation of indicators/counts for method using diagnosis codes only";

	%crosstab(BENE_SUD_DX_ONLY,CNT_SUD_DX_ONLY);
	%crosstab(BENE_SUD_DX_ONLY,POP_SUD_DX_ONLY);
	%crosstab(BENE_SUD_DX_ONLY,SUD_PLYSBSTNCE_DX_ONLY PLYSBSTNCE_SUD_DSRDR_DGNS1 PLYSBSTNCE_SUD_DSRDR_DGNS_OUTP CNT_SUD_DX_ONLY)

	%do s=1 %to %sysfunc(countw(&indicators.));
		%let ind=%scan(&indicators.,&s.);

		%crosstab(BENE_SUD_DX_ONLY,SUD_&ind._DX_ONLY)
		%crosstab(BENE_SUD_DX_ONLY,&ind._SUD_DSRDR_DGNS1 &ind._SUD_DSRDR_DGNS_OUTP SUD_&ind._DX_ONLY)

	%end; 
	 


%mend SUD_DX_ONLY;
