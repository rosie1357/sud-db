/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/

/*************************************************************************/
/*** organization : Mathematica Policy Research
/*** project      : 50139 MACBIS, Task 5 IAH
/*** program      : 20_5131_Measure.sas
/*** author       : Preeti Gill
/***              :
/*** purpose      : Construct claim type typees at line level with select variables for the  
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
/*************************************************************************/

%macro measure(type = , startnum = )/minoperator ;


	*identfy mean number of valid ICD10 codes by rotating table and summing;
	%if &type. = ip %then %let count = 12;
	%else %if %quote(&type.) = %str(lt) %then %let count = 5;
		%droptable(&type._rotate)
		execute ( 
		create table if not exists &dbname..&prefix.&type._rotate as 
		select
		 submtg_state_cd 
		 ,count(&type._link_key) as m6_denom 
		 ,sum(icds) as m6_num
		from (
			select 
				submtg_state_cd
				,&type._link_key
				,sum(dx_num) as icds
			from(
				 %do i=1 %to &count.;
			     select 
						submtg_state_cd
						,msis_ident_num
						,&type._link_key
						,dgns_&i._cd
						,dx&i._icd10 as dx_num
					from &dbname..&prefix.&type._claim_&i.

					%if &i. ne &count. %then %do; union %end;

				%end;
				) as a
			group by 1,2
		)as b
		group by 1
		) by tmsis_passthrough;


		*output final table;
		%droptable(&briefnum._&type.)
		execute (
		create table if not exists &dbname..&prefix.&briefnum._&type. as 
		select  * 
	 			%concern(value_num=%eval(&startnum.+1),
			             concern_num=%eval(&startnum.+6),
				         low1_a=%str(90 <=),

						 med1_a=%str(80 <=),
						 med1_b=%str(< 90),

						 high1_a=%str(50 <=),
						 high1_b=%str(< 80),

						 unus1_b=%str(< 50)
						 )
		 from (	select distinct
				a.submtg_state_cd
				,m1 as %name_msr(%eval(&startnum.)) 
				,case when m1  <> 0 then m2/m1 * 100 end as %name_msr(%eval(&startnum. + 1)) 
				,case when m1  <> 0 then m3/m1 * 100 end as %name_msr(%eval(&startnum. + 2)) 
				,case when m1  <> 0 then m4/m1 * 100 end as %name_msr(%eval(&startnum. + 3)) 
				,case when m1  <> 0 then m5/m1 * 100 end as %name_msr(%eval(&startnum. + 4)) 
				,case when m6_denom  <> 0 then m6_num/m6_denom end as %name_msr(%eval(&startnum. + 5))
				from &dbname..&prefix.&type._state as a 
				left outer join &dbname..&prefix.&type._rotate as b
				on a.submtg_state_cd = b.submtg_state_cd
			) a 
		) by tmsis_passthrough;

%mend;

%macro ot_measure(startnum=);

	%droptable(&briefnum._ot)
	execute (
	create table if not exists &dbname..&prefix.&briefnum._ot
	select 
	*
	%concern(value_num=%eval(&startnum.+1),
		             concern_num=%eval(&startnum.+4),
			         low1_a=%str(90 <=),

					 med1_a=%str(80 <=),
					 med1_b=%str(< 90),

					 high1_a=%str(50 <=),
					 high1_b=%str(< 80),

					 unus1_b=%str(< 50)
					 )

	from (select  
		submtg_state_cd
		,m1 as %name_msr(%eval(&startnum.)) 
		,case when m1  <> 0 then m2/m1 * 100 end as %name_msr(%eval(&startnum. + 1)) 
		,m3 as %name_msr(%eval(&startnum. + 2)) 
		,case when m3  <> 0 then m4/m3 * 100 end as %name_msr(%eval(&startnum. + 3)) 
	from ( 
		select
			submtg_state_cd
			,count(distinct case when ot_tos = 1 then ot_link_key end) as  m1
			,count(distinct case when ot_tos = 1 and dx1_icd10 = 1 then ot_link_key end) as m2
			,count(distinct ot_link_key) as m3
			,count(distinct case when dx1_icd10 = 1 then ot_link_key end)  as  m4
		from &dbname..&prefix.ot_lne
		group by submtg_state_cd
	 ) a
	) b 
 ) by tmsis_passthrough;
%mend;


%macro measures_comb();

	%droptable_perm(&briefnum._fnl);

	** Join all claims measures to state dummy;

	execute (
		create table if not exists &dbperm..&prefix.&briefnum._fnl as

		select distinct 
			a.*
			 %do i = 1 %to 19;
				,%name_msr(%eval(&i))
			 %end;
		from &dbperm..&prefix.state_lookup a
		left join &dbname..&prefix.&briefnum._ip t1
		on a.submtg_state_cd = t1.submtg_state_cd

		left join &dbname..&prefix.&briefnum._lt t2
		on a.submtg_state_cd = t2.submtg_state_cd

		left join &dbname..&prefix.&briefnum._ot t3
		on a.submtg_state_cd = t3.submtg_state_cd

	) by tmsis_passthrough;

%mend measures_comb;
