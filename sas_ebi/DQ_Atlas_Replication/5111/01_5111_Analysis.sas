/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/
/*******************************************************************************/
/* Program: 01_5111_Analysis.sas                                        
/* Date   : 07/2019                                                            
/* Author : Rosie Malsberger                                                   
/* Purpose: Calculate claims volume by enrolled months/enrolled benes
/*******************************************************************************/

%macro volume;

	%let claimtypes=ip lt ot rx;

	%do type=1 %to 4;
		%let cltype=%scan(&claimtypes.,&type.);

			** Pull headers, keep needed vars and drop headers not wanted;
			%droptable(&cltype.h_vol_0);

			execute (
				create table if not exists &dbname..&prefix.&cltype.h_vol_0 as

				select submtg_state_cd,
				       &cltype._link_key,
					   xovr_ind,
					   clm_type_cd,
					   adjstmt_ind

				from &dbname..&prefix.&cltype.h_autib

				where clm_type_cd in ('1','A','3','C') and
				      msis_ident_num is not null and
					  substring(msis_ident_num,1,1) != '&'

			) by tmsis_passthrough;

			** Read in lines;

			%droptable(&cltype.l_vol)

			execute (
				create table if not exists &dbname..&prefix.&cltype.l_vol as

				select submtg_state_cd,
					   &cltype._link_key,
					   cll_stus_cd

				from &dbname..&prefix.&cltype.l_autib

				where denied_clm_line_flag=0

			) by tmsis_passthrough;


			%droptable(&cltype._vol);

			execute (
				create table if not exists &dbname..&prefix.&cltype._vol as

				select submtg_state_cd
				       ,&cltype._link_key
					   ,sum(line) as cnt_lines

				from (

					select a.*
					       ,case when b.submtg_state_cd is not null
						         then 1 else 0
								 end as line

					from &dbname..&prefix.&cltype.h_vol_0 a
					     left join
						 &dbname..&prefix.&cltype.l_vol b

					on a.submtg_state_cd = b.submtg_state_cd and
					   a.&cltype._link_key = b.&cltype._link_key ) c

				group by submtg_state_cd
				         ,&cltype._link_key

				) by tmsis_passthrough;


			%droptable(&cltype._vcounts)

			execute (
				create table if not exists &dbname..&prefix.&cltype._vcounts as
				select submtg_state_cd
				        ,count(submtg_state_cd) as cnt_headers
						,sum(cnt_lines) as cnt_lines
						,avg(cnt_lines) as avg_lines

				from &dbname..&prefix.&cltype._vol
				group by submtg_state_cd

			) by tmsis_passthrough ;

		%end; ** end claims loop; 

		** Now read in DE;

		%droptable(de_vol)

		execute (
			create table if not exists &dbname..&prefix.de_vol as

			select *,
					 ENROLLED_01 + ENROLLED_02 + ENROLLED_03 + ENROLLED_04 + ENROLLED_05 + ENROLLED_06 + 
					 ENROLLED_07 + ENROLLED_08 + ENROLLED_09 + ENROLLED_10 + ENROLLED_11 + ENROLLED_12
						as NMOS_ENROLLED

			from (
				select submtg_state_cd,
					   age_num
					  
					   %do m=1 %to 12;
					   	  %if %sysfunc(length(&m.))=1 %then %let m=0&m.;

						
						  ,case when chip_flag_&m. in (0,1)						             
						        then 1 else 0
								end as ENROLLED_&m.

						 
					    %end;


			from &dbname..&prefix.de_autib
                 where MISG_ELGBLTY_DATA_IND=0 or MISG_ELGBLTY_DATA_IND is null ) c

		) by tmsis_passthrough;

		  ** Output bene-month counts by state and month.
		     Create a second set of indicators for LT only, to subset to those age 65+;

		 %droptable(bene_vcounts)

		  execute (
		  	create table if not exists &dbname..&prefix.bene_vcounts as 
			select submtg_state_cd
		  		  ,sum(NMOS_ENROLLED) as cnt_mos_enrolled

				  ,sum(case when age_num >= 65 then NMOS_ENROLLED else 0 end) as cnt_mos_enrolled_65

			from &dbname..&prefix.de_vol
		    
			group by submtg_state_cd

		) by tmsis_passthrough ;	
	

%mend volume;
