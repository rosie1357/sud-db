/**********************************************************************************************/
/*Program: 05_sud_analytic_pop
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to join the three bene-level files created in the prior three macros (one per
/*         SUD method) to create one analytic population, and output bene-level stats to be read 
/*         into initial Excel QC tables (directly from Redshift), and to be downloaded and 
/*         output to Excel formatted tables in PC SAS
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/


%macro SUD_ANALYTIC_POP;

	** Join the full population to the three bene-level method tables;

	execute (
		create temp table population2 as
		select a.submtg_state_cd,
		       a.msis_ident_num,
			   age,
			   ELGBLTY_GRP_CAT,
			   FULL_DUAL,
			   AGECAT,
			   coalesce(DISABLED_YR,0) as DISABLED_YR,
			   rstrctd_bnfts_cd_null,
			   coalesce(POP_SUD_TOOL1,0) as POP_SUD_TOOL1,
			   coalesce(POP_SUD_DX_ONLY,0) as POP_SUD_DX_ONLY,
			   coalesce(POP_SUD_NODX,0) as POP_SUD_NODX,
			   coalesce(OUD_NODX,0) as OUD_NODX,

			   case when POP_SUD_TOOL1=1 or POP_SUD_DX_ONLY=1 or POP_SUD_NODX=1
			        then 1 else 0
					end as POP_SUD

				%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);

					,SUD_&ind._TOOL1
					,SUD_&ind._DX_ONLY

					%if &ind. ne OTHER %then %do;
						,case when SUD_&ind._TOOL1=1 or SUD_&ind._DX_ONLY=1 %if &ind. = OPIOIDS %then %do; or OUD_NODX=1 %end;
						      then 1 else 0
							  end as SUD_&ind.

					%end;

				%end;

				/* For OTHER (only for purposes of tabulation for table A), group caffeine/hallucinogens/SHA/inhalants into other */

				,case when SUD_OTHER_TOOL1=1 or SUD_OTHER_DX_ONLY=1 or SUD_CFFNE=1 or SUD_HLLCNGN=1 or SUD_INHLNTS=1 or SUD_SHA=1
					      then 1 else 0
						  end as SUD_OTHER


		from population a
		     left join
			 (select * from BENE_SUD_TOOL1 where POP_SUD_TOOL1=1) b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

		   left join

		   (select * from BENE_SUD_DX_ONLY where POP_SUD_DX_ONLY=1) c

		on a.submtg_state_cd = c.submtg_state_cd and
		   a.msis_ident_num = c.msis_ident_num

		   left join

		   (select * from BENE_SUD_NODX where POP_SUD_NODX=1) d

		on a.submtg_state_cd = d.submtg_state_cd and
		   a.msis_ident_num = d.msis_ident_num

	) by tmsis_passthrough;


	title2 "Join of all three methods";
	
	%crosstab(population2,POP_SUD_TOOL1 POP_SUD_DX_ONLY POP_SUD_NODX);
	%crosstab(population2,rstrctd_bnfts_cd_null);

	%crosstab(population2,SUD_OPIOIDS SUD_OPIOIDS_TOOL1 SUD_OPIOIDS_DX_ONLY OUD_NODX);

	** Also create a table with only SUD benes to be used in all further analyses (except initial method counts);

	execute (
		create temp table population_sud as
		select *

		from population2
		where POP_SUD=1

	) by tmsis_passthrough;

	%crosstab(population_sud,POP_SUD_TOOL1 POP_SUD_DX_ONLY POP_SUD_NODX,
	          outfile=sasout.national_sud_crosstab);

	%crosstab(population_sud,age,
		       outfile=sasout.national_sud_age);

	%crosstab(population_sud,age,wherestmt=%nrstr(where POP_SUD_TOOL1=1),
		       outfile=sasout.national_sud_tool1_age);

	** Output tables with counts - run for everyone AND also only those with an OPIOID;

	%macro initialcounts(suffix=);

		create table sasout.state_sud_methods&suffix. as select * from connection to tmsis_passthrough
		(select submtg_state_cd,
		        count(*) as POP_TOT,
		        sum(POP_SUD) as POP_SUD_TOT,
	            sum(POP_SUD_TOOL1) as POP_SUD_TOOL1_TOT,
		        sum(POP_SUD_DX_ONLY) as POP_SUD_DX_ONLY_TOT,
				sum(POP_SUD_NODX) as POP_SUD_NODX_TOT
				%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);
					,sum(SUD_&ind.) as POP_SUD_&ind._TOT
				%end;

		from population2
		%if &suffix. ne  %then %do;
			where SUD_OPIOIDS=1
		%end;
	    group by submtg_state_cd);

		create table sasout.national_sud_methods&suffix. as select * from connection to tmsis_passthrough
		(select count(*) as POP_TOT,
		        sum(POP_SUD) as POP_SUD_TOT,
	            sum(POP_SUD_TOOL1) as POP_SUD_TOOL1_TOT,
		        sum(POP_SUD_DX_ONLY) as POP_SUD_DX_ONLY_TOT,
				sum(POP_SUD_NODX) as POP_SUD_NODX_TOT
				%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);
					,sum(SUD_&ind.) as POP_SUD_&ind._TOT
				%end;

		from population2
        %if &suffix. ne  %then %do;
			where SUD_OPIOIDS=1
		%end;);

		create table sasout.state_sud_counts_cond&suffix. as select * from connection to tmsis_passthrough
		(select submtg_state_cd,
		        sum(POP_SUD) as POP_SUD_TOT
				%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);
					,sum(SUD_&ind.) as POP_SUD_&ind._TOT
				%end;

		from population_sud
		%if &suffix. ne  %then %do;
			where SUD_OPIOIDS=1
		%end;
	    group by submtg_state_cd);

		** Output frequencies by eligibility group for those with an SUD;

		%frequency_strat(population2,POP_SUD,stratcol=ELGBLTY_GRP_CAT,
		                 %if &suffix. ne  %then %do;
						 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
						 %end;
		                 outfile=sasout.national_elgblty_grp_sud&suffix.);

		%frequency_strat(population2,POP_SUD,stratcol2=ELGBLTY_GRP_CAT,
						%if &suffix. ne  %then %do;
						 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
						 %end;
		                 outfile=sasout.state_elgblty_grp_sud&suffix.);

		%frequency_strat(population_sud,ELGBLTY_GRP_CAT,
						 %if &suffix. ne  %then %do;
						 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
						 %end;
		                 outfile=sasout.state_sud_elgblty_grp&suffix.);

		%crosstab(population_sud,ELGBLTY_GRP_CAT,
				  %if &suffix. ne  %then %do;
						wherestmt=%nrstr(where SUD_OPIOIDS=1),
				  %end;
		           outfile=sasout.national_sud_elgblty_grp&suffix.);

		** Create tables for ad hoc analysis looking at duals;

		%frequency_strat(population_sud,FULL_DUAL,
					 	%if &suffix. ne  %then %do;
							wherestmt=%nrstr(where SUD_OPIOIDS=1),
					    %end;
		           		outfile=sasout.state_duals&suffix.);

		** Get counts for new DISABLTY tables;

		%frequency_strat(population2,DISABLED_YR,stratcol2=agecat,
						%if &suffix. ne  %then %do;
							wherestmt=%nrstr(where SUD_OPIOIDS=1),
					    %end;
		           		outfile=sasout.state_disabled2&suffix.);

		%frequency_strat(population_sud,DISABLED_YR,stratcol2=agecat,
					%if &suffix. ne  %then %do;
							wherestmt=%nrstr(where SUD_OPIOIDS=1),
					  %end;
	           		outfile=sasout.state_disabled&suffix.);

		%if &suffix. =  %then %do;

			%frequency_strat(population2,POP_SUD,stratcol2=FULL_DUAL,
			           		outfile=sasout.state_duals2&suffix.);

			%frequency_strat(population2,POP_SUD,stratcol2=agecat,
						 	wherestmt=%nrstr(where ELGBLTY_GRP_CAT=4 ),
			           		outfile=sasout.state_abd2&suffix.);

			%frequency_strat(population_sud,agecat,
					 	wherestmt=%nrstr(where ELGBLTY_GRP_CAT=4),
		           		outfile=sasout.state_abd&suffix.);

		%end;

		%if &suffix. ne  %then %do;

			%frequency_strat(population2,SUD_OPIOIDS,stratcol2=FULL_DUAL,
			           		outfile=sasout.state_duals2&suffix.);

			%frequency_strat(population2,SUD_OPIOIDS,stratcol2=agecat,
						 	wherestmt=%nrstr(where ELGBLTY_GRP_CAT=4 ),
			           		outfile=sasout.state_abd2&suffix.);

			%frequency_strat(population_sud,agecat,
					 	wherestmt=%nrstr(where ELGBLTY_GRP_CAT=4 and SUD_OPIOIDS=1),
		           		outfile=sasout.state_abd&suffix.);

		%end;

	%mend initialcounts;

	%initialcounts;
	%initialcounts(suffix=_OP)

%mend SUD_ANALYTIC_POP;
