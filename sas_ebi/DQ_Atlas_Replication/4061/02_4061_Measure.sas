/*********************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                   */
/* This code cannot be copied, distributed or used                   */
/* without the express written permission of                         */
/* Mathematica Policy Research, Inc.                                 */
/*********************************************************************/
*====================================================================*         
*                PROJECT 50139 MACBIS - TASK4                        *                 
*====================================================================*;
* PROGRAM NAME: 10_4061_Measure.sas                                                          
* PROGRAMMER  : Preeti Gill                                                
* DESCRIPTION : Medicaid Enrollment Brief
* MODIFICATION: 
*====================================================================*;          

%macro measure;


%droptable(count_mdcd);

execute(
   create table if not exists &dbname..&prefix.count_mdcd as
   select  submtg_state_cd
		   %do m=1 %to 12 %by 1; 
           %if %sysfunc(length(&m.)) = 1 %then %let m=%sysfunc(putn(&m.,z2)); 
          ,sum(mdcd_bene_&m.) as cnt_mdcd_bene_&m.
           %end;

   from (select  submtg_state_cd
                ,msis_ident_num
		         %do m=1 %to 12 %by 1; 
                 %if %sysfunc(length(&m.)) = 1 %then %let m=%sysfunc(putn(&m.,z2)); 
                ,case when chip_flag_&m.=0 and 
                           (rstrctd_bnfts_flag_&m. =1 or 
						    rstrctd_bnfts_flag_&m.=2)
                      then 1 else 0 end as mdcd_bene_&m.
				 %end;
           from  &dbname..&prefix.de_autib
		   where MISG_ELGBLTY_DATA_IND=0 ) c

   group by submtg_state_cd
   order by submtg_state_cd
) by tmsis_passthrough;

 
%droptable(calc_diff);
execute(
   create table if not exists &dbname..&prefix.calc_diff as
	select *

		/*average TAF monthly*/
		  ,(cnt_mdcd_bene_01  %do m = 2 %to 12; + cnt_mdcd_bene_%sysfunc(putn(&m.,z2)) %end;)/12  as %name_msr(1) 

		/*average PI monthly*/
		  ,(mdcd_&year.01 %do m = 2 %to 12; + mdcd_&year.%sysfunc(putn(&m.,z2)) %end;)/12       as %name_msr(2)  

		/*average monthly difference*/
		  ,(diff_mdcd_01 %do m = 2 %to 12; + diff_mdcd_%sysfunc(putn(&m.,z2)) %end;)/12           as %name_msr(3) 

		/*average percent difference*/
		  ,(pct_mdcd_01  %do m = 2 %to 12; + pct_mdcd_%sysfunc(putn(&m.,z2)) %end;)/12            as %name_msr(4)  

		from (select  
              coalesce(a.submtg_state_cd, b.submtg_state_cd) as submtg_state_cd
	       %do m=1 %to 12 %by 1; 
	       %if %sysfunc(length(&m.)) = 1 %then %let m=%sysfunc(putn(&m.,z2)); 
		      ,a.cnt_mdcd_bene_&m.
		      ,b.mdcd_&year.&m. 
		      ,a.cnt_mdcd_bene_&m.- b.mdcd_&year.&m. as diff_mdcd_&m.
			  ,case when a.cnt_mdcd_bene_&m. =0 and b.mdcd_&year.&m.=0 then 0
		      	  when a.cnt_mdcd_bene_&m. > 0 and b.mdcd_&year.&m. = 0 then 100
	              when a.cnt_mdcd_bene_&m. < 0 and b.mdcd_&year.&m. = 0 then -100
				  else ((a.cnt_mdcd_bene_&m.- b.mdcd_&year.&m.)/b.mdcd_&year.&m.)*100 end as pct_mdcd_&m.
	       %end; 
		from &dbname..&prefix.count_mdcd a
	    /*left*/ full outer join &dbname..&prefix.pi_mdcd_&year. b
		on a.submtg_state_cd = b.submtg_state_cd ) a 
) by tmsis_passthrough;


** Take differences from wide to long to calculate stddev;

	%droptable(stddev)

	execute (
		create table if not exists &dbname..&prefix.stddev as

		select submtg_state_cd
		      ,stddev_pop(pct_mdcd) as %name_msr(5)
		from (
			 %do m=1 %to 12;
				  %if &m. > 1 %then %do; union all %end;
				  	select 
						submtg_state_cd
						,pct_mdcd_%sysfunc(putn(&m.,z2)) as pct_mdcd
					from &dbname..&prefix.calc_diff
			%end;

		) a
		group by submtg_state_cd 

	) by tmsis_passthrough;

** Create table final table;
%droptable_perm(&briefnum._fnl);
execute(
   create table if not exists &dbperm..&prefix.&briefnum._fnl as
  select 
	a.*
		%do i = 1 %to 6;
			,%name_msr(&i.)
		%end;
	from &dbperm..&prefix.state_lookup as a 
	left join 
	(select *
		%concern(value_num=4,
			     concern_num=6,

				 low_alt=%nrbquote(abs(%name_msr(4)) <= 10 ),

				 med_alt=%nrbquote((abs(%name_msr(4)) > 10 and abs(%name_msr(4))<= 20)),

				 high_alt=%nrbquote((abs(%name_msr(4)) > 20 and abs(%name_msr(4))<= 50)),

				 unus_alt=%nrbquote(abs(%name_msr(4)) > 50 ))

	 from &dbname..&prefix.calc_diff) as b 
	on a.submtg_state_cd = b.submtg_state_cd 
	left join &dbname..&prefix.stddev as  c 
	on a.submtg_state_cd = c.submtg_state_cd  
	) by tmsis_passthrough;

	
%mend measure;
