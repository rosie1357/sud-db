/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/

/*************************************************************************/
/*** organization : Mathematica Policy Research
/*** project      : 50139 MACBIS, Task 5 IAH
/*** program      : 20_5131_Extract_Line.sas
/*** author       : Preeti Gill
/***              :
/*** purpose      : Construct claim type files at line level with select variables for the  
/***              : denominator population.
/***              :   
/*** inputs       :taf_mon_bsf
/***              :data_anltcs_taf_lth_vw
				  :data_anltcs_taf_ltl_vw
				  :data_anltcs_taf_&type.h_vw
				  :data_anltcs_taf_&type.l_vw
			  	  :data_anltcs_taf_rxh_vw
				  :data_anltcs_taf_rxl_vw
				  :data_anltcs_taf_oth_vw
				  :data_anltcs_taf_otl_vw

/*** outputs      : SAS - &type_bene_counts 
/***              :	Redshift - &type_line
/*************************************************************************/

*===================================================================================;
* Define macro variables  ;
*===================================================================================;
%macro extract_claims(type = /*claim type: ip, ot, lt, rx*/)/minoperator ;
*===================================================================================;
* Extract header claims 
*===================================================================================;
		  %if &type. = ip %then %let count = 12;
	%else %if %quote(&type.) = %str(lt) %then %let count = 5;
	%else %if &type. = ot %then %let count = 2;

	%droptable(&type._hdr_raw)
	execute (
	create table if not exists &dbname..&prefix.&type._hdr_raw as	
	    select 
			a.da_run_id
			,a.submtg_state_cd
			,a.msis_ident_num
			,a.&type._link_key
			,a.&type._fil_dt
			,a.&type._vrsn
			,a.adjstmt_ind

			,xovr_ind
			,clm_type_cd

			%do i=1 %to &count.;
				,dgns_&i._cd
			%end;

		from &dbname..&prefix.&type.h_autib as a

		where a.clm_type_cd in (&clm_type_keep.) 
            and (a.xovr_ind <> 1 or a.xovr_ind is null) 
		) by tmsis_passthrough;

		%macro print(ds);
		title "&ds.";
		select * from connection to tmsis_passthrough
		(select * from &dbname..&prefix.&ds. limit 10);
		%mend;
		%print(&type._hdr_raw);


*===================================================================================;
* For IP and LT, join to the look up tables using a broadcast join
*===================================================================================;
	%if &type. ne ot %then %do;

		%do i=1 %to &count.;
			%droptable(&type._claim_&i.)
			execute (
			create table if not exists &dbname..&prefix.&type._claim_&i. as
			select /*+ BROADCAST(&dqatlas.icd10_2019) */
				submtg_state_cd
				,msis_ident_num
				,&type._link_key
				,dgns_&i._cd
				,case when dgns_&i._cd is null then 1 else 0 end as dx&i._null
				,case when dgns_&i._cd = icd10_&i..code then 1 else 0 end as dx&i._icd10
			from &dqatlas.icd10_2019 as icd10_&i.
			right join &dbname..&prefix.&type._hdr_raw as a
				on icd10_&i..code = a.dgns_&i._cd 
			) by tmsis_passthrough;

			title"&dbname..&prefix.&type._state_&i.";
			select * from connection to tmsis_passthrough 
			(select 
			*
			from &dbname..&prefix.&type._claim_&i.
			limit 10);
		%end;

		%droptable(&type._state)
		execute (
		create table if not exists &dbname..&prefix.&type._state as
		select /*+ BROADCAST(&dqatlas.icd9_2019) */
			h.submtg_state_cd
			,count(submtg_state_cd) as m1
			,sum(dx1_icd10) as m2 
			,sum(dx1_null) as m3
			,sum(case when dgns_1_cd = icd9.code and dx1_icd10 = 0 then 1 else 0 end) as m4 
			,sum(case when icd9.code is null and dx1_icd10 = 0 and dx1_null = 0 then 1 else 0 end) as m5  
		from &dqatlas.icd9_2019 as icd9
			right join &dbname..&prefix.&type._claim_1 as h
			on icd9.code = h.dgns_1_cd
		group by 1
		) by tmsis_passthrough;

	%end;


*===================================================================================;
* For OT, extract line level data merged to header and join to look up table ;
*===================================================================================;
	%if &type = ot %then %do;

		%droptable(&type._merge)
		execute (
		create table if not exists &dbname..&prefix.&type._merge as  
		select  
		    a.*
			,case when b.submtg_state_cd is not null then 1 else 0 end as ot_tos
		from &dbname..&prefix.&type._hdr_raw  as a
		left join 
			(select distinct submtg_state_cd, &type._link_key 
			from &dbname..&prefix.&type.l_autib 
			where tos_cd in ('002','012','028'))as b 
		on b.submtg_state_cd     = a.submtg_state_cd and
		     b.&type._link_key   = a.&type._link_key	 
		) by tmsis_passthrough;


		%droptable(&type._lne)
		execute (
		create table if not exists &dbname..&prefix.&type._lne as  
		select  /*+ BROADCAST(&dqatlas.icd10_2019) */
		    a.*
			,case when dgns_1_cd = icd10.code then 1 else 0 end as dx1_icd10
		from &dqatlas.icd10_2019 as icd10 
		right join &dbname..&prefix.&type._merge as a on
		  icd10.code = a.dgns_1_cd
		) by tmsis_passthrough;
	%end;
%mend;



