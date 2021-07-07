/**********************************************************************************************/
/*Program: 06_sud_claims_pull
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to pull all SUD claims (based on diagnosis code/NDC or SUD-specific procedure/
/*         rev/place of service, join to our population of benes with an SUD, and get bene-level
/*         stats with SUD claim info 
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro sud_claims_pull;

	** Identify SUD claims from the following files:
         1. Tool 1 (all four file types): header/line-level files marked as SUD based on diagnosis OR NDC code (&fltype._sud)
         2. Method 3 (no DX): IP/OT inpatient files with INP_SUD indicator at line or header level, so must roll up to header level if 
              need to define INP_SUD at header-level (&fltype._inp_sud_nodx)
         3. Method 3 (no DX): LT/OT outpatient files with OUTP_SUD indicator at line or header level, so must roll up to header level if 
              need to define INP_SUD at header-level (&fltype._outp_sud_nodx);

	** The first thing to do is get a table of unique claim values (link_key values) from claims in the above tables, because there will be
       overlap in the Tool 1 vs. Method 3 claims. Get this table of unique link_key values along with FFS/MC indicators. After getting the
       FFS/MC bene-level stats, we will need to join back to the raw claims to pull all information (so can put claims into setting types);


	%unique_sud_claims(IP, t2=inp_sud_nodx, t2ind=INP_SUD)
	%unique_sud_claims(LT, t2=outp_sud_nodx, t2ind=OUTP_SUD)
	%unique_sud_claims(OT, t2=inp_sud_nodx, t2ind=INP_SUD, t3=outp_sud_nodx, t3ind=OUTP_SUD)
	%unique_sud_claims(RX);

	** Now union the above four tables that have unique link_key values for SUD claims for each of the four file types,
	   and get max of FFS/MC by bene for table E, before examining actual claims;

	execute (
		create temp table bene_sud_ffs_mc as
		select submtg_state_cd,
		       msis_ident_num,
			   max(CLAIM_MC) as CLAIM_MC,
			   max(CLAIM_FFS) as CLAIM_FFS

		from ( select * from IP_sud_unq_claims
		       union all

			   select * from LT_sud_unq_claims
		       union all

			   select * from OT_sud_unq_claims
		       union all

			   select * from RX_sud_unq_claims 

			)

		group by submtg_state_cd,
		         msis_ident_num

	) by tmsis_passthrough;

	** Join to table of SUD population - note there may claims for benes who are not
	   in the population, but all benes in population must have SUD claims from above;

	execute (
		create temp table population_sud_ffs_mc as
		select a.submtg_state_cd,
		       a.msis_ident_num,
			   SUD_OPIOIDS,
			   ELGBLTY_GRP_CAT,
			   CLAIM_MC,
			   CLAIM_FFS

		from population_sud a
		     left join
			 bene_sud_ffs_mc b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

	) by tmsis_passthrough;

	** Output count of benes with MC and FFS  (nationally and by state) - overall and opioids only;

	%macro mccounts(suffix=);

		%crosstab(population_sud_ffs_mc,CLAIM_MC,
				   %if &suffix. ne  %then %do;
					 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
				   %end;
		           outfile=sasout.national_sud_bene_mc&suffix.)

		%crosstab(population_sud_ffs_mc,CLAIM_FFS,
				   %if &suffix. ne  %then %do;
					 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
				   %end;
		           outfile=sasout.national_sud_bene_ffs&suffix.)

		%frequency_strat(population_sud_ffs_mc,CLAIM_MC,
				   %if &suffix. ne  %then %do;
					 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
				   %end;
		           outfile=sasout.state_sud_bene_mc&suffix.)

		%frequency_strat(population_sud_ffs_mc,CLAIM_FFS,
				   %if &suffix. ne  %then %do;
					 	wherestmt=%nrstr(where SUD_OPIOIDS=1),
				   %end;
		           outfile=sasout.state_sud_bene_ffs&suffix.)

	%mend mccounts;

	%mccounts;
	%mccounts(suffix=_OP);




%mend sud_claims_pull;
