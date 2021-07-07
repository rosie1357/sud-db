/**********************************************************************************************/
/*Program: id_intensive_outpatient
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 06/2021
/*Purpose: Identify specific codes in TAF OT
/***********************************************************************************************/

libname tmsi_lib SASIORST PRESERVE_COL_NAMES=YES PRESERVE_TAB_NAMES=YES
         dsn=RedShift  authdomain="AWS_TMSIS_QRY" ;

%let basedir=/sasdata/users/&sysuserid/tmsisshare/prod/Task_4_and_5_TAF_analyses/020_SUD_DB_2020;
%let year=2020;

%include "&basedir./Programs/99_sud_inner_macros.sas";

libname out "&basedir./Output/run_prep";

proc sql;
	%tmsis_connect;

	%let fltype=ot;

	execute (
		create temp table &fltype.H as
		select %recode_state_codes(prefix=a)
		       ,&fltype._fil_dt,
			   &fltype._link_key

		from cms_prod.data_anltcs_taf_&fltype.h_vw a

		where ltst_run_ind=1 and 
              substring(&fltype._fil_dt,1,4) = %nrbquote('&year.') and
              clm_type_cd in ('1','U','3','W') and
		      (submtg_state_cd != '17' or (submtg_state_cd = '17' and adjstmt_ind = '0' and adjstmt_clm_num is null)) 

	) by tmsis_passthrough;

	execute (
		create temp table &fltype.L as

		select &fltype._link_key
		       ,prcdr_cd
			   ,hcpcs_rate
			   ,rev_cd

			   ,case when prcdr_cd='H0015' or hcpcs_rate='H0015'
			   	     then 1 else 0
					 end as proc_H0015

				,case when prcdr_cd='S9480' or hcpcs_rate='S9480'
			   	     then 1 else 0
					 end as proc_S9480

				,case when rev_cd='0906'
					  then 1 else 0
					  end as rev_0906

				,case when rev_cd='0905'
					  then 1 else 0
					  end as rev_0905

		from cms_prod.data_anltcs_taf_&fltype.l_vw a

		where ltst_run_ind=1 and 
              substring(&fltype._fil_dt,1,4) = %nrbquote('&year.')

	) by tmsis_passthrough;

	create table out.intensive_outpatient_counts as select * from connection to tmsis_passthrough (
		
		select submtg_state_cd

		       ,sum(proc_H0015) as cnt_lines_proc_H0015
			   ,count(distinct (case when proc_H0015=1 then msis_ident_num else null end)) as cnt_benes_proc_H0015

			   ,sum(proc_S9480) as cnt_lines_proc_S9480
			   ,count(distinct (case when proc_S9480=1 then msis_ident_num else null end)) as cnt_benes_proc_S9480

			   ,sum(rev_0906) as cnt_lines_rev_0906
			   ,count(distinct (case when rev_0906=1 then msis_ident_num else null end)) as cnt_benes_rev_0906

			   ,sum(rev_0905) as cnt_lines_rev_0905
			   ,count(distinct (case when rev_0905=1 then msis_ident_num else null end)) as cnt_benes_rev_0905

		from (

			select a.*
			       ,proc_H0015
				   ,proc_S9480
				   ,rev_0906
				   ,rev_0905

			from &fltype.H a
			     left join
				 &fltype.L b

			on a.&fltype._link_key = b.&fltype._link_key ) b

		group by submtg_state_cd

	);

	data out.intensive_outpatient_counts;
		set out.intensive_outpatient_counts;
		state = fipstate(submtg_state_cd);
	run;

	proc sort data=out.intensive_outpatient_counts out=intensive_outpatient_counts (drop=submtg_state_cd);
		by state;
	run;

	proc export data=intensive_outpatient_counts dbms=xlsx outfile="&basedir./Excel/Intensive_Outpatient_Counts_&year._20210614.xlsx" replace;
	run;
		
