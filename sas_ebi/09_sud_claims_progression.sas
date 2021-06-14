/**********************************************************************************************/
/*Program: 09_sud_claims_progression
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in all SUD claims for benes with inpatient/residential care and
/*         see how many have outpatient/home/community services in 30 days following
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro sud_claims_progression;

	** Pull in all OT SUD claims identified as Setting = Inpatient. Create end date as header service
       end date if not null, otherwise max of line service end date;

	execute (
		create temp table OT_INPATIENT as
		select submtg_state_cd,
		       msis_ident_num,
			   srvc_endg_dt,
			   srvc_endg_dt_line_max,
			   case when srvc_endg_dt is not null then srvc_endg_dt
			        else srvc_endg_dt_line_max
					end as end_date

		from OT_SUD_SETTING_ROLLUP
		where SETTING in ('1. Inpatient','2. Residential')

	) by tmsis_passthrough;

	title2 "Sample print of OT records in Inpatient setting";

	select * from connection to tmsis_passthrough
	(select * 
	 from OT_INPATIENT
	 limit 20);

	select * from connection to tmsis_passthrough
	(select *
	 from OT_INPATIENT
	 where srvc_endg_dt != srvc_endg_dt_line_max
	 limit 20);

	** Pull ALL IP SUD claims, rolling up to header-level and creating end_date;

	execute (
		create temp table IP_INPATIENT as
		select submtg_state_cd,
		       msis_ident_num,
			   IP_LINK_KEY,
			   dschrg_dt,
			   max(srvc_endg_dt_line) as srvc_endg_dt_line_max,
			   case when dschrg_dt is not null then dschrg_dt
			        else max(srvc_endg_dt_line)
					end as end_date

			from IP_SUD_FULL
			group by submtg_state_cd,
			         msis_ident_num,
					 IP_LINK_KEY,
					 dschrg_dt


	) by tmsis_passthrough;

	title2 "Sample print of IP records in Inpatient setting";

	select * from connection to tmsis_passthrough
	(select *
	 from IP_INPATIENT
	 limit 20);

	select * from connection to tmsis_passthrough
	(select *
	 from IP_INPATIENT
	 where dschrg_dt != srvc_endg_dt_line_max
	 limit 20);


	** Pull ALL LT SUD claims, rolling up to header-level and creating end_date;

	execute (
		create temp table LT_RESIDENTIAL as
		select submtg_state_cd,
		       msis_ident_num,
			   LT_LINK_KEY,
			   dschrg_dt,
			   srvc_endg_dt,
			   max(srvc_endg_dt_line) as srvc_endg_dt_line_max,
			   case when srvc_endg_dt is not null then srvc_endg_dt
			        when max(srvc_endg_dt_line) is not null then max(srvc_endg_dt_line)
					else dschrg_dt
					end as end_date

			from LT_SUD_FULL
			group by submtg_state_cd,
			         msis_ident_num,
					 LT_LINK_KEY,
					 dschrg_dt,
			         srvc_endg_dt

	) by tmsis_passthrough;

	title2 "Sample print of LT records in Residential setting";

	select * from connection to tmsis_passthrough
	(select submtg_state_cd, srvc_endg_dt, srvc_endg_dt_line_max, dschrg_dt, end_date 
	 from LT_RESIDENTIAL
	 limit 20);

	select * from connection to tmsis_passthrough
	(select submtg_state_cd, srvc_endg_dt, srvc_endg_dt_line_max, dschrg_dt, end_date 
	 from LT_RESIDENTIAL
	 where srvc_endg_dt != srvc_endg_dt_line_max
	 limit 20);


	** For all three of the above, union and get all unique bene/date values - subset to those between
	   01/01 and 12/01 (because cannot look at 30 days after end date if end after 12/01);

	execute (
		create temp table INPATIENT_RES_DATES as 
		select distinct submtg_state_cd,
		                msis_ident_num,
						end_date

		from (select submtg_state_cd,
		             msis_ident_num,
				     end_date

				from OT_INPATIENT

				union
				select submtg_state_cd,
		               msis_ident_num,
				       end_date

				from IP_INPATIENT

				union
				select submtg_state_cd,
		               msis_ident_num,
				       end_date

				from LT_RESIDENTIAL)

		where date_cmp(end_date,%nrbquote('&year.-01-01')) in (0,1) and
		      date_cmp(end_date,%nrbquote('&year.-12-01')) in (0,-1)

	) by tmsis_passthrough;

	title2 "Month/Year of all distinct end_date values from Inpatient/Residential SUD records (on or before 12/01)";

	select * from connection to tmsis_passthrough
	(select end_date_mon, count(*) as count from
		(select to_char(end_date,'YYYY-MM') as end_date_mon from INPATIENT_RES_DATES ) 
	group by end_date_mon
    order by end_date_mon); 


	** Now must look at OT SUD claims marked as Outpatient, Home or Community, to compare beginning dates
	   and see if within 30 days of ending date. 

	   Create a table with all Outpatient/Home/Community claim headers, with
	   only needed cols. Will then join each of these to Inpatient/Residential.
	   We will take the minimum and maximum line service begin dates and compare all three (header, min and max
	   of lines) to end date of above Inpatient/Residential records;

	execute (
		create temp table OT_OUT_HOME_COMM as
		select submtg_state_cd,
		       msis_ident_num,
			   ot_link_key,
			   srvc_bgnng_dt,
			   srvc_bgnng_dt_line_min,
			   srvc_bgnng_dt_line_max

		from OT_SUD_SETTING_ROLLUP
		where SETTING in ('0. Community','3. Home','4. Outpatient')

	) by tmsis_passthrough;


	** Now do a many-to-many join by bene of the INPATIENT_RES_DATES table to the above dates table, 
	   and creates indicators for ANY of the beginning dates within 30 days of the ending date.
	   Then roll up to the bene-level to see whether ANY inpatient/residential records for the
	   bene met the 30 date rule, and count the number of distinct headers to identify those with 2+.

	** Do a many-to-many join of the inpatient/residential claims file to the 
       outpatient or home/community bene/dates file;

	execute (
		create temp table INP_RES_DATES as
		select a.submtg_state_cd,
		       a.msis_ident_num,
			   b.ot_link_key,
			   end_date,
			   srvc_bgnng_dt,
			   srvc_bgnng_dt_line_min,
			   srvc_bgnng_dt_line_max,

			   case when (datediff(day,end_date,srvc_bgnng_dt) >=0 and datediff(day,end_date,srvc_bgnng_dt) <= 30) or
			             (datediff(day,end_date,srvc_bgnng_dt_line_min) >=0 and datediff(day,end_date,srvc_bgnng_dt_line_min) <= 30) or
						 (datediff(day,end_date,srvc_bgnng_dt_line_max) >=0 and datediff(day,end_date,srvc_bgnng_dt_line_max) <= 30)
					then 1 else 0
					end as SERVICE30

		from INPATIENT_RES_DATES a
		     left join
			 OT_OUT_HOME_COMM b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num


	) by tmsis_passthrough;

	title2 "Print of sample records from join of Inpatient/Residential dates to Outpatient/Home/Community Dates";

	select * from connection to tmsis_passthrough
	(select * from INP_RES_DATES
 	 where SERVICE30=1
	 limit 50);

	select * from connection to tmsis_passthrough
	(select * from INP_RES_DATES
 	 where SERVICE30=0
	 limit 50);

	 ** Now roll up to the bene-level, taking the max of SERVICE30, Also create a separate table to count the number of
	    distinct link_key (claim header) values where SERVICE30=1;

	 execute (
	 	create temp table INP_RES_DATES_BENE_ANY as
		select submtg_state_cd,
		       msis_ident_num,
			   max(SERVICE30) as ANY_SERVICE30

		from INP_RES_DATES
		group by submtg_state_cd,
		         msis_ident_num

	 ) by tmsis_passthrough;

	 execute (
	 	create temp table INP_RES_DATES_BENE_MULT as
		select submtg_state_cd,
		       msis_ident_num,
			   count(*) as N_CLAIMS30

		from (
			select distinct submtg_state_cd,
		                    msis_ident_num,
			                ot_link_key

			from INP_RES_DATES
			where SERVICE30=1 )

		group by submtg_state_cd,
		         msis_ident_num

	 ) by tmsis_passthrough;

	** Join to population_sud to get OPIOIDS indicator;

	execute (
		create temp table INP_RES_DATES_BENE as
		select a.*,
		       b.N_CLAIMS30,
		       c.SUD_OPIOIDS

		from INP_RES_DATES_BENE_ANY a
		     left join
			 INP_RES_DATES_BENE_MULT b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num

		   left join
		   population_sud c

		on a.submtg_state_cd = c.submtg_state_cd and
		   a.msis_ident_num = c.msis_ident_num

	) by tmsis_passthrough;

	 title2 "QC creation of N_CLAIMS30 (# of unique claims with ANY_SERVICE30)";

	 select * from connection to tmsis_passthrough
	 (select ANY_SERVICE30,
             min(N_CLAIMS30) as N_CLAIMS30_MIN,
	         max(N_CLAIMS30) as N_CLAIMS30_MAX

	 from INP_RES_DATES_BENE
	 group by ANY_SERVICE30); 

	 ** Output stratified and national counts of ANY_SERVICE30, and count those where N_CLAIMS30>1;

	%macro counts(suffix=);

		create table sasout.state_sud_dates_30&suffix. as select * from connection to tmsis_passthrough
			(select submtg_state_cd,
			        count(*) as nbenes,
					sum(ANY_SERVICE30) as ANY_SERVICE30,
					sum(case when N_CLAIMS30>1 then 1 else 0 end) as MULT_SERVICE30

			from INP_RES_DATES_BENE
			%if &suffix. ne  %then %do;
				where SUD_OPIOIDS=1
			%end;
			group by submtg_state_cd );

		create table sasout.national_sud_dates_30&suffix. as select * from connection to tmsis_passthrough
			(select count(*) as nbenes,
					sum(ANY_SERVICE30) as ANY_SERVICE30,
					sum(case when N_CLAIMS30>1 then 1 else 0 end) as MULT_SERVICE30

			from INP_RES_DATES_BENE
			%if &suffix. ne  %then %do;
				where SUD_OPIOIDS=1
			%end;);

	%mend counts;

	%counts;
	%counts(suffix=_OP);

%mend sud_claims_progression;
