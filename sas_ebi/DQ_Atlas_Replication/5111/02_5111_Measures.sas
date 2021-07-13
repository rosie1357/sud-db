/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/
/*******************************************************************************/
/* Program: 02_5111_Measures.sas                                        
/* Date   : 07/2019                                                            
/* Author : Rosie Malsberger                                                   
/* Purpose: Create measures from claims output
/*******************************************************************************/

%macro measures(cltype, startnum, suffix=);

	%droptable(&cltype._vcounts2);

	** Join claims and DE counts to create values to use to calculate medians;

	execute (
		create table if not exists &dbname..&prefix.&cltype._vcounts2 as
		select coalesce(a.submtg_state_cd, b.submtg_state_cd) as submtg_state_cd
		       ,cnt_headers/(cnt_mos_enrolled&suffix./1000) as headers_mos
			   ,cnt_lines/(cnt_mos_enrolled&suffix./1000) as lines_mos
			   ,cnt_headers
			   ,cnt_lines
			   ,avg_lines
			   ,cnt_mos_enrolled&suffix.
			   ,1 as dummy

		from &dbname..&prefix.&cltype._vcounts a
		     full join
			 &dbname..&prefix.bene_vcounts b

		on a.submtg_state_cd = b.submtg_state_cd

	) by tmsis_passthrough;

	%droptable(&cltype._meds)

	execute (
		create table if not exists &dbname..&prefix.&cltype._meds as
		select percentile(headers_mos, 0.5) as headers_mos_med
		       ,percentile(lines_mos, 0.5) as lines_mos_med
			   ,percentile(avg_lines, 0.5) as avg_lines_med
			   ,1 as dummy

		from &dbname..&prefix.&cltype._vcounts2

	) by tmsis_passthrough; 

	%droptable(&cltype._vcounts3a) 

	execute (
		create table if not exists &dbname..&prefix.&cltype._vcounts3a as
	
		select submtg_state_cd

		   		   %do add=2 %to 10;

				   		%if /* exclude IP DQ being recoded */
                            %eval(&startnum.+&add.) ne 4  and %eval(&startnum.+&add.) ne 7  and
						    %eval(&startnum.+&add.) ne 10 and 
							/* exclude LT DQ being recoded */
							%eval(&startnum.+&add.) ne 21 and 
							/* exclude OT DQ being recoded */
							%eval(&startnum.+&add.) ne 26 and %eval(&startnum.+&add.) ne 29  and 
                            %eval(&startnum.+&add.) ne 32 and
							/* exclude RX DQ being recoded */
							%eval(&startnum.+&add.) ne 37 and %eval(&startnum.+&add.) ne 40  and 
                            %eval(&startnum.+&add.) ne 43 and

                             %eval(&startnum.+&add.) ne 1 and %eval(&startnum.+&add.) ne 12 and %eval(&startnum.+&add.) ne 15 
                             and %eval(&startnum.+&add.) ne 18 and %eval(&startnum.+&add.) ne 23 and %eval(&startnum.+&add.) ne 34 %then %do;

							,%name_msr(%eval(&startnum.+&add.))

							%if &add.=2 or &add.=5 or &add.=8 %then %do;
								,%name_msr(%eval(&startnum.+&add.), median = 1)
							%end;							
						%end;

					%end;
			   %if "&cltype." = "lt"  %then %do;
                ,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. > 0) and (cnt_lines = 0 or cnt_lines is null) then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 'Unusable'
				      else %name_msr(%eval(&startnum. + 10)) end as %name_msr(%eval(&startnum. + 10))
			   %end;
			   %else  %do;
		        ,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_headers  > 0 then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. > 0) and (cnt_headers = 0 or cnt_headers is null) then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_headers = 0 or cnt_headers is null) then 'Unusable'
				      else %name_msr(%eval(&startnum. + 4)) end as %name_msr(%eval(&startnum. + 4))

                ,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. > 0) and (cnt_lines = 0 or cnt_lines is null) then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 'Unusable'
				      else %name_msr(%eval(&startnum. + 7)) end as %name_msr(%eval(&startnum. + 7))

                ,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. > 0) and (cnt_lines = 0 or cnt_lines is null) then 'Unclassified'
				      when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 'Unusable'
				      else %name_msr(%eval(&startnum. + 10)) end as %name_msr(%eval(&startnum. + 10))
				%end;
		from 

		(

			select *
				   	
				 %concern(value_num=%eval(&startnum.+3),
			             concern_num=%eval(&startnum.+4),
				         low1_a=%str(75 <=),
						 low1_b=%str(<= 150),

						 med1_a=%str(50 <=),
						 med1_b=%str(< 75),
						 med2_a=%str(150 <),
						 med2_b=%str(<= 200),

						 high1_a=%str(10 <=),
						 high1_b=%str(< 50),
						 high2_a=%str(200 <),

						 unus1_b=%str(< 10)
						 %if "&cltype." = "lt" %then %do;
						 	,all_NA=true
						 %end;
						 )

				%concern(value_num=%eval(&startnum.+6),
			             concern_num=%eval(&startnum.+7),
				         low1_a=%str(75 <=),
						 low1_b=%str(<= 150),

						 med1_a=%str(50 <=),
						 med1_b=%str(< 75),
						 med2_a=%str(150 <),
						 med2_b=%str(<= 200),

						 high1_a=%str(10 <=),
						 high1_b=%str(< 50),
						 high2_a=%str(200 <),

						 unus1_b=%str(< 10)
						 %if "&cltype." = "lt" %then %do;
						 	,all_NA=true
						 %end;
						 )

				%if "&cltype." ne "lt" %then %do;

					%concern(value_num=%eval(&startnum.+9),
				             concern_num=%eval(&startnum.+10),
					         low1_a=%str(50 <=),
							 low1_b=%str(<= 200),

							 high1_a=%str(10 <=),
							 high1_b=%str(< 50),
							 high2_a=%str(200 <),

							 unus1_b=%str(< 10)
							 )

				%end;

				%if "&cltype." = "lt" %then %do;

					%concern(value_num=%eval(&startnum.+9),
				             concern_num=%eval(&startnum.+10),

							 low_alt=%nrbquote( %name_msr(%eval(&startnum.+8)) >= 1 and 
                                                 %name_msr(%eval(&startnum.+9)) >= 10 ),

							 high_alt=%nrbquote( %name_msr(%eval(&startnum.+8)) < 1 and 
                                                 %name_msr(%eval(&startnum.+9)) >= 10 ),

							 unus_alt=%nrbquote( %name_msr(%eval(&startnum.+9)) < 10 ) )



				%end;

			from ( 
				select a.*
				       ,headers_mos_med
					   ,lines_mos_med
					   ,avg_lines_med
					   ,cnt_headers 
					   ,cnt_lines

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_headers > 0 then null
				 	  when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_headers = 0 or cnt_headers is null) then 0
				      else headers_mos end as %name_msr(%eval(&startnum.+2))

				,headers_mos_med as %name_msr(%eval(&startnum.+2), median=1)

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_headers > 0 then null
				      when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_headers = 0 or cnt_headers is null) then 0
				      else 100 * (headers_mos / headers_mos_med) end as %name_msr(%eval(&startnum.+3))

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then null
				 	  when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 0
					  else lines_mos end as %name_msr(%eval(&startnum.+5))

				,lines_mos_med as %name_msr(%eval(&startnum.+5), median=1)

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then null
				 	  when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 0
					  else 100 * (lines_mos / lines_mos_med) end as %name_msr(%eval(&startnum.+6))

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then null
				 	  when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 0
					  else avg_lines end as %name_msr(%eval(&startnum.+8))

				,avg_lines_med as %name_msr(%eval(&startnum.+8), median=1)

				,case when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and cnt_lines > 0 then null
				 	  when (cnt_mos_enrolled&suffix. = 0 or cnt_mos_enrolled&suffix. is null) and (cnt_lines = 0 or cnt_lines is null) then 0
				      else 100 * (avg_lines / avg_lines_med) end as %name_msr(%eval(&startnum.+9))

				from &dbname..&prefix.&cltype._vcounts2 a
				     full join
					 &dbname..&prefix.&cltype._meds b 

				on a.dummy = b.dummy 

			) c 
		) d


	) by tmsis_passthrough; 

%droptable(&cltype._vcounts3) 

	execute (
		create table if not exists &dbname..&prefix.&cltype._vcounts3 as
	
		select *

              %if "&cltype." = "lt" %then %do;
               %concern_overall_v2(value_nums=%eval(&startnum.+10),
			                  concern_num=%eval(&startnum.+11) )
			  %end;

			  %else %do;
				 %concern_overall_v2(value_nums=%eval(&startnum.+4) %eval(&startnum.+7) %eval(&startnum.+10),
			                  concern_num=%eval(&startnum.+11))
			  %end;
		from 
            &dbname..&prefix.&cltype._vcounts3a

		) by tmsis_passthrough; 

/*
			create table &cltype._vcounts2 as 
   select * from connection to tmsis_passthrough
		(select * from 	&dbname..&prefix.&cltype._vcounts2 limit 100);


create table &cltype._vcounts3 as 
   select * from connection to tmsis_passthrough
		(select * from 	&dbname..&prefix.&cltype._vcounts3 limit 100);
*/
%mend measures;


%macro measures_comb(types, startnums);

	%droptable_perm(&briefnum._fnl);

	** Join all claims measures to state dummy - do not create 15 or 18 (measues droped);

	execute (
		create table if not exists &dbperm..&prefix.&briefnum._fnl as

		select a.*
		      
		       %do t=1 %to 4;
			   	   %let cltype=%scan(&types., &t.);
				   %let startnum=%scan(&startnums., &t.);
				   %do add=2 %to 11;

				   		%if %eval(&startnum.+&add.) ne 1 and %eval(&startnum.+&add.) ne 12 and %eval(&startnum.+&add.) ne 15 
                             and %eval(&startnum.+&add.) ne 18 and %eval(&startnum.+&add.) ne 23 and %eval(&startnum.+&add.) ne 34 %then %do;

							,%name_msr(%eval(&startnum.+&add.))

							%if &add.=2 or &add.=5 or &add.=8 %then %do;
								,%name_msr(%eval(&startnum.+&add.), median = 1)
							%end;							
						%end;

					%end;
				%end;

			   ,f.cnt_mos_enrolled    as %name_msr(45)
			   ,f.cnt_mos_enrolled    as %name_msr(45,suffix=A)
			   ,f.cnt_mos_enrolled    as %name_msr(45,suffix=B)
			   ,f.cnt_mos_enrolled_65 as %name_msr(46)

		from &dbperm..&prefix.state_lookup a
			  %do t=1 %to 4;
			   	  %let cltype=%scan(&types., &t.);

				  left join
				  &dbname..&prefix.&cltype._vcounts3 t&t.

				  on a.submtg_state_cd = t&t..submtg_state_cd

			  %end;

		 left join &dbname..&prefix.bene_vcounts as f
		 on a.submtg_state_cd = f.submtg_state_cd
	) by tmsis_passthrough;


	create table DQ&briefnum._fnl as 
	select * from connection to tmsis_passthrough
	(select * from 	&dbperm..&prefix.&briefnum._fnl);

%mend measures_comb;

