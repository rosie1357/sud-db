/**********************************************************************************************/
/*Program: 02_sud_tool1
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in the claims pulled in %SUD_INITIAL and identify benes with SUD conditions
/*         using tool 1 logic
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/


%macro SUD_TOOL1;


	** For all files, join line-level NDC to the SUD NDC code table. For all files except RX, we will
	   then take the MAX across all lines for a given header, to then be able to join back
	   to the header and keep only SUD claims (identified through diagnosis code or NDC). For RX
       we do not need to join back because just the line on RX will qualify as the SUD condition.;

	%join_sud_rx(IP, tbl=HL_labt2);
	%join_sud_rx(LT, tbl=HL2);
	%join_sud_rx(OT, tbl=HL_labt2);
	%join_sud_rx(RX, tbl=HL1, suffix=);


	** For IP and LT, join to the list of overnight facility codes (bill type, rev, procedure) to identify
	   claims for SUD services - note only IP has procedure code.
	   For OT, join to list of facility codes (rev and procedure only);

	%join_sud_fac(IP, codetype=OFAC, nproc=6);
	%join_sud_fac(LT, codetype=OFAC);
	%join_sud_fac(OT, codetype=FAC, nproc=1);

	** For OT, join to list of professional service codes for SUD (procedure code only);

	%join_sud_prof(OT);

	** Now we have files for all SUD services identified through diagnosis code or NDC, with all associated rules.
	   On each claim, must roll up to the header level, taking the MINIMUM of all rules across lines and creating one
	   SERVICE DATE value (based on TAF rules). The rules are:

	   IP = discharge date (header) - if null then minimum service end date (line) - if null then minimum service begin date (line)
	   LT = service end date (header)
	   OT = service end date (header) - if null then service begin date (header) - if null then minimum service end date (line)
	   RX = fill date (header) 

       After rolling up to the header-level, must then rollup again across claims with the same value of service date,
	   taking the minimum value of SUD_TOOL_RULE and max value of all condition indicators.
	   The output from this macro will be one table per claim type that can then be unioned together because
	   all tables will have the same columns;

	%rollup(IP, 
             tbl=sud2, 
             rules=SUD_TOOL_RULE_RX SUD_TOOL_RULE_FAC, 
             dates=dschrg_dt srvc_endg_dt_line srvc_bgnng_dt_line);

	%rollup(LT, 
             tbl=sud2, 
             rules=SUD_TOOL_RULE_RX SUD_TOOL_RULE_FAC, 
             dates=srvc_endg_dt);

	%rollup(OT, 
             tbl=sud3, 
             rules=SUD_TOOL_RULE_RX SUD_TOOL_RULE_FAC SUD_TOOL_RULE_PROF, 
             dates=srvc_endg_dt srvc_bgnng_dt srvc_endg_dt_line);

	%rollup(RX, 
             tbl=sud, 
             rules=SUD_TOOL_RULE_RX, 
             dates=rx_fill_dt);

	** Now stack all four claim files to do a final rollup across the four file types (so can identify different dates
	   of service if the rule flags are set to 2 or 3 (where different dates of service are required);

	execute (
		create temp table allclaims_rollup as

		(select * from IP_rollup2 where SUD_TOOL_RULE_HDR is not null) 
		union all

		(select * from LT_rollup2 where SUD_TOOL_RULE_HDR is not null)
		union all

		(select * from OT_rollup2 where SUD_TOOL_RULE_HDR is not null)
		union all

		(select * from RX_rollup2 where SUD_TOOL_RULE_HDR is not null)

	) by tmsis_passthrough;

	/*title2 "Freq of SUD_TOOL_RULE_HDR on stacked rolled up claims from all file types - ";
	title3 "subset to claims with non-null value of SUD_TOOL_RULE_HDR only";

	%frequency(allclaims_rollup,SUD_TOOL_RULE_HDR); */

	** Now must create bene-level flags for each condition, based on the value of SUD_RULE values for individual indicators:
	    - If SUD_TOOL_RULE = 1 on any claim with the condition flag set to 1, then set the bene-level condition flag to 1
	    - If SUD_TOOL_RULE = 2 on two claims with different srvc_date values with the condition flag set to 1, set bene-level flag to 1
	    - If SUD_TOOL_RULE = 3 and = 2 on two claims with different srvc_date values with the condition flag set to 1, set bene-level flag to 1;

	** Loop through all the condition values and create separate tables for each condition;

	%do s=1 %to %sysfunc(countw(&indicators.));
		%let ind=%scan(&indicators.,&s.);

		** First create a bene-level table with any claim where TOOL_RULE = 1;

		execute (
			create temp table &ind._1 as
			select distinct submtg_state_cd,
			                msis_ident_num

			from allclaims_rollup
			where &ind._SUD_RULE=1

		) by tmsis_passthrough;

		** Now create a bene/date-level table for all claims with the given condition, where TOOL_RUL = 2 or 3.
		   Take the minimum of TOOL_RULE for the given date.
		   From this inner query, count the number of records (unique dates of service) for each value of TOOL_RULE.
		   If there are 2+ records where TOOL_RULE=2 OR
		                1+ record where TOOL_RULE=2 and 1+ record where TOOL_RULE=3,
		   then can set the bene condition flag to 1.;

		execute (
			create temp table &ind._23 as
				select submtg_state_cd,
				       msis_ident_num,
					   sum(case when &ind._SUD_RULE=2 then 1 else 0 end) as RULE2_SUM,
					   sum(case when &ind._SUD_RULE=3 then 1 else 0 end) as RULE3_SUM

			from ( 
				select submtg_state_cd,
				       msis_ident_num,
					   srvc_dt,
					   min(&ind._SUD_RULE) as &ind._SUD_RULE

				from allclaims_rollup
				where &ind._SUD_RULE in (2,3) 

				group by submtg_state_cd,
				         msis_ident_num,
					     srvc_dt )

			group by submtg_state_cd,
			         msis_ident_num

		) by tmsis_passthrough;

		/*title2 "Summary stats for RULE2_SUM and RULE3_SUM (# of unique dates with each rule) for &ind. (bene-level)";

		select * from connection to tmsis_passthrough
		(select count(*) as nbenes,
                min(RULE2_SUM) as RULE2_SUM_min,
		        avg(RULE2_SUM :: float) as RULE2_SUM_avg,
				max(RULE2_SUM) as RULE2_SUM_max,
				min(RULE3_SUM) as RULE3_SUM_min,
		        avg(RULE3_SUM :: float) as RULE3_SUM_avg,
				max(RULE3_SUM) as RULE3_SUM_max

		 from &ind._23 ); */

		 ** Now join the two tables together to create a table with ALL benes identified from
		    either method;

		 execute (
		 	create temp table &ind. as
			select coalesce(a.submtg_state_cd,b.submtg_state_cd) as submtg_state_cd,
			       coalesce(a.msis_ident_num,b.msis_ident_num) as msis_ident_num,
				   case when a.submtg_state_cd is not null then 1 
				        else 0
						end as RULE_1,

				   case when b.submtg_state_cd is not null then 1 
				        else 0
						end as RULE_23,

				   1 as POP_SUD_&ind.

			from &ind._1 a
			     full join
				 (select * from &ind._23 where RULE2_SUM >= 2 or (RULE2_SUM >= 1 and RULE3_SUM >= 1 ) )b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.msis_ident_num = b.msis_ident_num

		 ) by tmsis_passthrough;

		 /*title2  "Join of bene-level tables using rule 1 vs rule 2/3 for &ind.";

		 %crosstab(&ind.,RULE_1 RULE_23); */

	%end;

	** Now we have bene-level tables for every condition - must join all together. Join to a 
	   table of unique benes from the table before subsetting for each condition in the above loop.
	   Use NLTRXNE indicator to set alcohol/opioid.
	   For PLYSBSTNCE, also set to 1 if there are multiple conditions (excluding PLYSBSTNCE);


	execute (
		create temp table BENE_SUD_TOOL1 as 
		select 
			a.submtg_state_cd,
			a.msis_ident_num

			%do s=1 %to %sysfunc(countw(&indicators.));
				%let ind=%scan(&indicators.,&s.);

				,POP_SUD_&ind.

				%if &ind. ne OPIOIDS and &ind. ne PLYSBSTNCE and &ind. ne NLTRXNE %then %do;
					,coalesce(POP_SUD_&ind.,0) as SUD_&ind._TOOL1
				%end;

				/* For OPIOIDS, look at original NLTRXNE */ 
				%if &ind. = OPIOIDS %then %do;
					,case when (POP_SUD_NLTRXNE = 1 and coalesce(POP_SUD_ALCHL,0) = 0) or (POP_SUD_OPIOIDS=1) then 1
					      else 0
						  end as SUD_OPIOIDS_TOOL1
				%end; 

				/* Create new SUD_NLTRXNE_TOOL1 as 0 so that not counted when we count the number of conditions below */

				%if &ind. = NLTRXNE %then %do;
					,0 as SUD_NLTRXNE_TOOL1
				%end;
			%end;

			/* Count the number of conditions, and create PLYSBSTNCE for those with 2+ OR where the original PLYSBSTNCE = 1. */

			,%do s=1 %to %sysfunc(countw(&indicators.));
				%let ind=%scan(&indicators.,&s.);
				%if &ind. ne PLYSBSTNCE %then %do;
					%if &s. > 1 %then %do; + %end;
					SUD_&ind._TOOL1
				%end;
			 %end; 
			 as CNT_SUD_TOOL1 

			 ,case when CNT_SUD_TOOL1 > 1 or POP_SUD_PLYSBSTNCE=1
			       then 1 else 0
				   end as SUD_PLYSBSTNCE_TOOL1

			,case when CNT_SUD_TOOL1 > 0 or POP_SUD_PLYSBSTNCE=1
				   then 1 else 0
				   end as POP_SUD_TOOL1

		from (select distinct submtg_state_cd, msis_ident_num from allclaims_rollup) a

			%do s=1 %to %sysfunc(countw(&indicators.));
				%let ind=%scan(&indicators.,&s.);

				left join 
	            &ind. t&s.

				on a.submtg_state_cd = t&s..submtg_state_cd and
				   a.msis_ident_num = t&s..msis_ident_num

			%end;

	) by tmsis_passthrough;

	/*title2 "Frequencies of all final bene-level indicators";

	%frequency(BENE_SUD_TOOL1,POP_SUD_TOOL1)
	%crosstab(BENE_SUD_TOOL1,POP_SUD_TOOL1 CNT_SUD_TOOL1)
	%crosstab(BENE_SUD_TOOL1,CNT_SUD_TOOL1 SUD_PLYSBSTNCE_TOOL1)

	%do s=1 %to %sysfunc(countw(&indicators.));
		%let ind=%scan(&indicators.,&s.);

		%frequency(BENE_SUD_TOOL1,SUD_&ind._TOOL1);

	%end;   

	%crosstab(BENE_SUD_TOOL1,POP_SUD_NLTRXNE SUD_ALCHL_TOOL1 SUD_OPIOIDS_TOOL1 POP_SUD_OPIOIDS); */


%mend SUD_TOOL1;
