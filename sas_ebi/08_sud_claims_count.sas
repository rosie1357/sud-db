/**********************************************************************************************/
/*Program: 08_sud_claims_count
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in all SUD claims with assigned service types and count services - either
/*         by count of claims or count of unique days
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro sud_claims_count;

	******* STEP 1: GET COUNTS OF CLAIMS FOR SERVICES WHERE WE COUNT CLAIMS ***** ;

	** For each of the services for which we want to count claims, get a count of the unique
       service dates where the service indicator = 1;

	execute (
		create temp table SUD_SERVICES_COUNT_CLAIMS0 as
		select submtg_state_cd,
		       msis_ident_num
			   %do i=1 %to %sysfunc(countw(&services_count_claims.));
			   	   %let ind=%scan(&services_count_claims.,&i.);
			   	  ,count(distinct (case when TRT_SRVC_&ind.=1 then srvc_dt end)) as count_&ind.
				%end;


		from SUD_SERVICES
		group by submtg_state_cd,
		         msis_ident_num

	) by tmsis_passthrough;

	** Join to population_sud to get OPIOIDS indicator;

	execute (
		create temp table SUD_SERVICES_COUNT_CLAIMS as
		select a.*,
		       b.SUD_OPIOIDS

		from SUD_SERVICES_COUNT_CLAIMS0 a
		     inner join
			 population_sud b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

	) by tmsis_passthrough;

	** Look at summary stats for counts by bene - max must be 365;

	title2 "Summary stats for # of services by bene (where counts are claim counts)";

	select * from connection to tmsis_passthrough
	(select count(*) as nbenes
            %do i=1 %to %sysfunc(countw(&services_count_claims.));
			   %let ind=%scan(&services_count_claims.,&i.);
			   ,min(count_&ind.) as min_count_&ind.
			   ,avg(count_&ind. :: float) as avg_count_&ind.
			   ,max(count_&ind.) as max_count_&ind.
			%end;
	from SUD_SERVICES_COUNT_CLAIMS);

	** Now get total counts of services and benes with each service;

	%macro counts(suffix=);

		create table sasout.state_sud_count_claims&suffix. as select * from connection to tmsis_passthrough
		(select submtg_state_cd,
		        count(*) as nbenes
				%do i=1 %to %sysfunc(countw(&services_count_claims.));
				   %let ind=%scan(&services_count_claims.,&i.);
				   ,sum(count_&ind.) as tot_count_&ind.
				   ,sum(case when count_&ind.>0 then 1 else 0 end) as nbenes_&ind.
				%end;
		from SUD_SERVICES_COUNT_CLAIMS
		%if &suffix. ne  %then %do;
			where SUD_OPIOIDS=1
		%end;
		group by submtg_state_cd);

		create table sasout.national_sud_count_claims&suffix. as select * from connection to tmsis_passthrough
		(select count(*) as nbenes
				%do i=1 %to %sysfunc(countw(&services_count_claims.));
				   %let ind=%scan(&services_count_claims.,&i.);
				   ,sum(count_&ind.) as tot_count_&ind.
				   ,sum(case when count_&ind.>0 then 1 else 0 end) as nbenes_&ind.
				%end;
		from SUD_SERVICES_COUNT_CLAIMS
		%if &suffix. ne  %then %do;
			where SUD_OPIOIDS=1
		%end;);

	%mend counts;

	%counts;
	%counts(suffix=_OP);

	******* STEP 2: GET COUNTS OF DAYS FOR SERVICES WHERE WE COUNT DAYS ***** ;

	** Now to count services for service types that depend on a count of days, must go back to the 
	   line-level file and assign begin/end dates for all identified services based on what column
	   was used to map the service.
	   RX will be run separately from the other three files because all we care about there is 
	   line-level NDC;


	%service_type_days(IP, nprocs=6,
	                   bdate1=srvc_bgnng_dt_line,
					   bdate2=admsn_dt,
					   edate1=srvc_endg_dt_line,
					   edate2=dschrg_dt,

					   bdate1_p=admsn_dt,
					   bdate2_p=srvc_bgnng_dt_line_min,
					   edate1_p=dschrg_dt,
					   edate2_p=srvc_endg_dt_line_max);

	%service_type_days(LT,
	                   bdate1=admsn_dt,
					   bdate2=srvc_bgnng_dt,
					   edate1=dschrg_dt,
					   edate2=srvc_bgnng_dt,

					   bdate1_p=admsn_dt,
					   bdate2_p=srvc_bgnng_dt,
					   edate1_p=dschrg_dt,
					   edate2_p=srvc_bgnng_dt);

	%service_type_days(OT, nprocs=2,
	                   bdate1=srvc_bgnng_dt_line,
					   bdate2=srvc_bgnng_dt,
					   edate1=srvc_endg_dt_line,
					   edate2=srvc_endg_dt,

					   bdate1_p=srvc_bgnng_dt_line,
					   bdate2_p=srvc_bgnng_dt,
					   edate1_p=srvc_endg_dt_line,
					   edate2_p=srvc_endg_dt);

	%service_type_days(RX);

	** Loop through all service types AND MAT med categories again to stack daily indicators across all
	   four file types (daily indicators were created in macro above) ;

	%do t=1 %to %sysfunc(countw(&services_count_days.,'#'));
		%let ind=%scan(&services_count_days.,&t.,'#');

		** Now must stack all four file types before taking max across all days;

		execute (
			create temp table SUD_SRVC_&ind. as

			select * from IP_SUD_SRVC_&ind.

			union all
			select * from LT_SUD_SRVC_&ind.

			union all
			select * from RX_SUD_SRVC_&ind.

			union all
			select * from OT_SUD_SRVC_&ind.

		) by tmsis_passthrough;

		** Create sample output SAS tables to examine;

		create table &ind._days_sample as select * from connection to tmsis_passthrough
		(select submtg_state_cd, bdt_ndc_&ind., edt_ndc_&ind. 
		        ,bdt_proc_&ind. ,edt_proc_&ind.
				%do num=1 %to &totdays.;
					,&ind._day&num.
				%end;
		 from SUD_SRVC_&ind.

		 limit 50);

		** Now summarize to the bene-level and count the number of unique days of each service type by taking the max of 
		   each daily indicator and summing;

		execute (
			create temp table SUD_SRVC_&ind._BENE0 as
			select submtg_state_cd,
			       msis_ident_num
					,%do num=1 %to &totdays.;
						%if &num. > 1 %then %do; + %end;
						&ind._day&num.
					%end;
					as TOT_DAYS_&ind.

			 from (select submtg_state_cd,
			              msis_ident_num
							%do num=1 %to &totdays.;
								,max(&ind._day&num.) as &ind._day&num.
							%end;

					from SUD_SRVC_&ind.
					group by submtg_state_cd,
					         msis_ident_num )

		) by tmsis_passthrough;

		** Join to population_sud to get OPIOIDS indicator;

		execute (
			create temp table SUD_SRVC_&ind._BENE as
			select a.*,
			       b.SUD_OPIOIDS

			from SUD_SRVC_&ind._BENE0 a
			     inner join
				 population_sud b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.msis_ident_num = b.msis_ident_num

		) by tmsis_passthrough;

		title2 "Summary stats for # of services by bene (where counts are day counts) - &ind.";

		select * from connection to tmsis_passthrough
		(select count(*) as nbenes
	            ,min(TOT_DAYS_&ind.) as min_days_&ind.
				,avg(TOT_DAYS_&ind. :: float) as avg_days_&ind.
				,max(TOT_DAYS_&ind.) as max_days_&ind.

		from SUD_SRVC_&ind._BENE);

		** Now get total counts of service days and benes with each service;

		%macro counts(suffix=);

			create table sasout.stdy_&ind.&suffix. as select * from connection to tmsis_passthrough
			(select submtg_state_cd,
			        count(*) as nbenes
					,sum(TOT_DAYS_&ind.) as tot_count_&ind.
					,sum(case when TOT_DAYS_&ind.>0 then 1 else 0 end) as nbenes_&ind.
			from SUD_SRVC_&ind._BENE
			%if &suffix. ne  %then %do;
				where SUD_OPIOIDS=1
			%end;
			group by submtg_state_cd);

		%mend counts;

		%counts;
		%counts(suffix=_OP);

	%end; ** end service types loop;


%mend sud_claims_count;
