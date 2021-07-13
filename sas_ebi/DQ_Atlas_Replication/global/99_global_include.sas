/************************************************************************************
* © 2020 Mathematica Inc. 
* The Covid Analytics Code using TAF was developed by Mathematica Inc. as part 
* of the MACBIS Business Analytics and Data Quality Development project funded by 
* the U.S. Department of Health and Human Services – Centers for Medicare and 
* Medicaid Services (CMS) through Contract No. HHSM-500-2014-00034I/HHSM-500-T0005 
*************************************************************************************/

/*===========================================================================          
                PROJECT 50139 MACBIS - TASK 5 COVID ANALYSIS
-----------------------------------------------------------------------------           
PROGRAM NAME: 99_Global_Include.sas                                                           
PROGRAMMER  : Preeti Gill, Rosie Malsberger, Ben Schneedecker
DESCRIPTION : Contains macros to be called in other programs for COVID analysis            
======================================================================= */ 

%macro tmsis_connect;

	LIBNAME TMSISDBK ODBC  DATASRC=Databricks authdomain="TMSIS_DBK";
	CONNECT USING TMSISDBK as tmsis_passthrough;
	EXECUTE (set val user = VALUEOF(&sysuserid)) by tmsis_passthrough;

%mend tmsis_connect;

%macro tmsis_disconnect;
  DISCONNECT FROM tmsis_passthrough;
%mend tmsis_disconnect;


%macro timestamp_log();
  %let actual_time = %sysfunc(putn(%sysfunc(datetime()),datetime22.));
  %put *----------------------------------------------------*;
  %put Timestamp: &sysuserid. &actual_time. ;
  %put *----------------------------------------------------*;
%mend;

%macro IB_timestamp_log(IB);
  %let actual_time = %sysfunc(putn(%sysfunc(datetime()),datetime22.));
  %put *----------------------------------------------------*;
  %put Timestamp: IB&IB. &actual_time. ;
  %put *----------------------------------------------------*;
%mend;

** Create state abbreviation dataset to match fips code to abbrev for output - SAS dataset and AREMAC table;     
%macro state_dummy_table;

	data stdummy (drop=i);
		length state $30;
		do i = 1 to 56;	
			state2 = fipstate(i);
			state = propcase(stname(state2));
			if state='District Of Columbia' then state='District of Columbia';
		 	submtg_state_cd = put(i,z2.);
			if state2 > 'AA' then output;
		end;

		state2='PR';
		state='Puerto Rico';
		submtg_state_cd='72';
		output;

		state2='VI';
		state='Virgin Islands';
		submtg_state_cd='78';
		output;

		state2='GU';
		state='Guam';
		submtg_state_cd='66';
		output;

		state2='MP';
		state='Northern Mariana Islands';
		submtg_state_cd='69';
		output;

	run;

	proc sort data=stdummy;
		by submtg_state_cd;
	run;


	data stdummy;
		set stdummy end=eof;
		length insert $200.;

		if eof=0 then insert = cats("('",submtg_state_cd,"','",state2,"'),");
		if eof then insert = cats("('",submtg_state_cd,"','",state2,"');");

		if submtg_state_cd not in ('60','69') then output;
	run;

	** Build a text file of the needed SQL commands;

	filename inscmds "&progpath./state_lookup.txt";
	data _null_; 
		set stdummy end=eof;
		file inscmds;
		if _n_ = 1 then do;
			put 'execute(';
			put "create table if not exists &dbperm..&prefix.state_lookup (submtg_state_cd varchar(2), state varchar(2));";
			put ') by tmsis_passthrough;';
			put 'execute(';
			put "insert into &dbperm..&prefix.state_lookup values";
		end;
		put insert;
		if eof then put ') by tmsis_passthrough;';
	run; 

	proc sql;
		%tmsis_connect;

		%droptable_perm(state_lookup);

		%include "&progpath/state_lookup.txt";

		select * from connection to tmsis_passthrough
		(select * From mprscratch.suddb2020state_lookup);

		%tmsis_disconnect;
	quit;

%mend state_dummy_table;



** Create tables with valid values for stratification cols so can do cartesian join before creating visualization tables to get
   all possible combinations of values. Note must also add 'Null' and 'All' values;

%macro valid_vals_lookup(col=, length=, values=);

	data &col.;
		length value $&length.;
		%if &col. = month %then %do;
			%do y=1 %to %sysfunc(countw(&years.));
				%let rptyr=%scan(&years.,&y.);
				%do m=1 %to 12;
					%if &m.<10 %then %let m=0&m.;
					value = "&rptyr.&m.";
					if value <= "&lastmo." then output;
				%end;
			%end;

		%end;

		%else %do v=1 %to %sysfunc(countw(&values., '\'));
			%let value=%scan(&values.,&v.,'\');
			value = "&value.";
			output;
		%end;
	run;

	** Create a dataset with the commands for inserting each row;

	data &col.;
		set &col. end=eof;
		length insert $150.;
		if not eof then insert = cats("('",value,"'),");
		if eof then insert = cats("('",value,"');");
		 
	run;

	** Build a text file of the needed SQL commands;

	filename inscmds "&lookups./values_&col..txt";
	data _null_; 
		set &col. end=eof;
		file inscmds;
		if _n_ = 1 then do;
			put 'execute(';
			put "drop table if exists &dbperm..values_&col.;";
			put ') by tmsis_passthrough;';
			put 'execute(';
			put "create table if not exists &dbperm..values_&col. (&col. varchar(&length.));";
			put ') by tmsis_passthrough;';
			put 'execute(';
			put "insert into &dbperm..values_&col. values";
		end;
		put insert;
		if eof then put ') by tmsis_passthrough;';
	run; 

%mend valid_vals_lookup;

%macro create_valid_val_lookups;

	%valid_vals_lookup(col=month, length=6)

	%valid_vals_lookup(col=sex, length=5, 
					  values= F \ M \ Null \ All);

	** For age group valid values, also include 3 additional aggregate groups that must be manually created in 04_TABLES;

	%valid_vals_lookup(col=age_group, length=5, 
	                   values= %nrstr(<1 \ 1-2 \ 3-5 \ 6-9 \ 10-14 \ 15-18 \ 19-24 \ 25-34 \ 35-44 \ 45-54 \ 55-64 \ 65-74 \ 75+ \
                                      <=18 \ 19-64 \ 65+ \ Null \ All))

	%valid_vals_lookup(col=eligibility_group, length=30,
	                   values = Medicaid children \ Pregnant \ Adult \ Blind and disabled \ Aged \ Adult expansion \ CHIP children \ COVID newly eligible \ Null \ All)

	%valid_vals_lookup(col=dual_status, length=20,
	                   values = Dually eligible \ Non-dually eligible \ Null \ All)

	%valid_vals_lookup(col=age_group_under19, length=5, 
	                   values= %nrstr(<1 \ 1-2 \ 3-5 \ 6-9 \ 10-14 \ 15-18 \ Null \ All))

	%valid_vals_lookup(col=age_group_1544, length=10, 
	                   values= %nrstr(15-20 \ 21-33 \ 34-44 \ All))

	%valid_vals_lookup(col=race_ethnicity, length=60, 
	                   values = %nrstr(White \ Black \ Asian \ American Indian and Alaska Native \ Hawaiian/Pacific Islander \
					                   Multiracial \ Hispanic %(all races%) \ Null \ All ))

	%valid_vals_lookup(col=age_group_dth, length=10, 
                   		values= %nrstr(<=18 \ 19-24 \ 25-34 \ 35-44 \ 45-54 \ 55-64 \ 65-74 \ 75+ \ Null \ All))


%mend create_valid_val_lookups;

/* Macro recode_state_codes to be included when reading in raw BSF/DE/claim header data to recode submtg_state_cd to Medicaid values,
   and create new version of msis_ident_num as concatentation of raw submtg_state_cd and msis_ident_num for given states

   NOTES: Assumes this will be included as the first two columns after select - if not, must add comma before calling macro
          Does not retain the original values of either column - must add additional code if needed 

*/

%macro recode_state_codes;

	case when submtg_state_cd in ('30', '42', '56',
                                  '94', '97', '93')
           then concat(msis_ident_num, submtg_state_cd)
           else msis_ident_num  
           end as msis_ident_num
                     
	,case when submtg_state_cd in ('30','94') then '30'
	      when submtg_state_cd in ('42','97') then '42'
	      when submtg_state_cd in ('56','93') then '56'
	      else submtg_state_cd 
          end as submtg_state_cd

%mend recode_state_codes;

%macro droptable(table, schema=&dbname., tbl_prefix=&prefix.);

	execute(
		drop table if exists &schema..&tbl_prefix.&table.
	) by tmsis_passthrough;

%mend droptable;



%macro dropview(table, perm=0, tempview=0);

	%if &perm.=0 %then %let tablepre=&dbname..&prefix.;
	%if &perm.=1 %then %let tablepre=&dbperm..;

	%if &tempview.=1 %then %let tablepre = &prefix.;

	execute(
		drop view if exists &tablepre.&table.
	) by tmsis_passthrough;

%mend dropview;

** Macro to drop all tables and views - to be called before and after each production run.
   Drop all tables beginning with given prefix (those without prefix are permanent tables to be kpet);

%macro drop_all(schemaname=, prefix_drop=);

	proc sql;
		%tmsis_connect;

		create table alltables as select * from connection to tmsis_passthrough
		(show tables in &schemaname. );

		select tableName
		into :alltables
		separated by ' '
		from alltables
        where index(tableName,"&prefix_drop.") = 1 and index(tableName,'autib')=0;

		%local i next_tbl;
			%do i=1 %to %sysfunc(countw(&alltables));
	   		%let next_tbl = %scan(&alltables,  &i);
			execute(drop table if exists &schemaname..&next_tbl.) by tmsis_passthrough;
		%end;


%mend drop_all;


/* Macro crosstab to run crosstab (with percents) - assumes numeric input
   Macro parms:
      ds=input dataset
      col=col to run frequency on
      wherestmt=optional subset where statement
      outfile=optional name of SAS output dataset (if not specified will just print to lst file) */

%macro crosstab(ds,cols,wherestmt=,outfile=, perm=0);

	%if &perm.=0 %then %let tablepre=&dbname..&prefix.;
	%if &perm.=1 %then %let tablepre=&dbperm..;

	%if &outfile. ne  %then %do; create table &outfile. as %end;
	select * from connection to tmsis_passthrough (

		select %do i=1 %to %sysfunc(countw(&cols.));
				    %let col=%scan(&cols.,&i.);
					&col.,
                  %end;
				  count,
			   100*(a.count / b.totcount) as pct
				

		from (select %do i=1 %to %sysfunc(countw(&cols.));
				    	%let col=%scan(&cols.,&i.);
			         	%if &i. > 1 %then %do; , %end; &col.
                  	 %end;
                     ,count(*) as count
					 ,max(1) as dummy

              from &tablepre.&ds. &wherestmt.
              group by %do i=1 %to %sysfunc(countw(&cols.));
				    	   %let col=%scan(&cols.,&i.);
			         	   %if &i. > 1 %then %do; , %end; &col.
                       %end;) a

		      inner join

			 (select count(*) as totcount, 1 as dummy from &tablepre.&ds. &wherestmt.) b

			 on a.dummy = b.dummy

		order by %do i=1 %to %sysfunc(countw(&cols.));
				    %let col=%scan(&cols.,&i.);
			         %if &i. > 1 %then %do; , %end; &col.
                  %end; );


%mend crosstab;

/* Macro stats to get summary stats on continuous variable */

%macro stats(ds, col, wherestmt=, perm=0, groupby= );

	%if &perm.=0 %then %let tablepre=&dbname..&prefix.;
	%if &perm.=1 %then %let tablepre=&dbperm..;

	select * from connection to tmsis_passthrough
	(select %if &groupby. ne  %then %do; &groupby, %end;
            count(*) as n_recs,
            count(&col.) n_non_null,
			sum(case when &col. is null then 1 else 0 end) as n_null,
			min(&col.) as min_&col.,
			avg(&col.) as mean_&col.,
			max(&col.) as max_&col.

	from &tablepre.&ds.
	&wherestmt.
	%if &groupby. ne  %then %do;
		group by &groupby.
		order by &groupby.
	%end;

	);


%mend stats;


/* Macro print outputs a data set of 10 records */
%macro print(table, perm = 0, limit = %str(limit 10), where = );

	%if &perm.=0 %then %let tablepre=&dbname..&prefix.;
	%if &perm.=1 %then %let tablepre=&dbperm..;

	title2 "PRINT from &table.";
	create table &table. as 
	select * from connection to tmsis_passthrough 
	(select * from &tablepre.&table. &where. &limit.);

%mend;

/* Macro print outputs a data set of 10 records */
%macro print(table, perm = 0, where = );

	%if &perm.=0 %then %let tablepre=&dbname..&prefix.;
	%if &perm.=1 %then %let tablepre=&dbperm..;

	title "PRINT from &table.";
	create table &table. as 
	select * from connection to tmsis_passthrough 
	(select * from &tablepre.&table. &where. limit 10);

%mend;

/* Macros to create views for the DQ Briefs work*/
%macro get_taf_varlist(fl);

      %if &fl. = bsf %then %let ds = tmsis.taf_mon_bsf;
%else %if &fl. = de %then %let ds = taf.data_anltcs_taf_ade_base_vw;
%else %let ds = taf.data_anltcs_taf_&fl._vw;

proc sql;
  %tmsis_connect;
   create table list_vars_&fl. as
   select *  from connection to tmsis_passthrough
   (show columns from &ds.);
  %tmsis_disconnect;
quit;

%global varlist_&fl.;

proc sql noprint;
select col_name
into :varlist_&fl. separated by ","
from list_vars_&fl.
where col_name not in ('msis_ident_num', 'submtg_state_cd');
quit;

%mend;


%macro de_base_common;
%global ST_RBF_PREG1 ST_RBF_PREG0;

%let ST_RBF_PREG1 =
'05',
'66',
'16',
'72',
'46',
'78';

%let ST_RBF_PREG0 =
'01',	'02',	'04',	'06',	'08',	'09',	'10',	'11',	'12',	'13',	'15',	'17',	'18',	
'19',	'20',	'21',	'22',	'23',	'24',	'25',	'26',	'27',	'28',	'29',	'30',	'31',	
'32',	'33',	'34',	'35',	'36',	'37',	'38',	'39',	'40',	'41',	'42',	'44',	'45',
'47',	'48',	'49',	'50',	'51',	'53',	'54',	'55',	'56'
;

%do m=1 %to 12 %by 1; 
%if %sysfunc(length(&m.)) = 1 %then %let m=%sysfunc(putn(&m.,z2)); 
,case when (chip_cd_&m.='1' or 
		   (chip_cd_&m. is null and 
            (elgblty_grp_cd_&m. between '01' and '60' or 
             elgblty_grp_cd_&m. between '69' and '75'))) then 0
        
      when (chip_cd_&m. in ('2','3','4') or 
		   (chip_cd_&m. is null and 
            (elgblty_grp_cd_&m. between '61' and '68'))) then 1
      else null end as chip_flag_&m.

,case when dual_elgbl_cd_&m. in ('02','04','08') then 1
      when dual_elgbl_cd_&m. in ('01','03','05','06') then 2
	  when dual_elgbl_cd_&m. in ('09','10') then 3
	  else 0 end as dual_flag_&m.

%if &year. < 2020 %then %do;
,case when rstrctd_bnfts_cd_&m. in ('1','A','B','D') then 1
      when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_&m. in ('4','7') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_&m. in ('7') )          then 2

	  when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_&m. in ('2','3','5','6') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_&m. in ('2','3','4','5','6') ) then 3

	 when rstrctd_bnfts_cd_&m. in ('0') then 0
	 else null end as rstrctd_bnfts_flag_&m.
%end;
%else %if &year. >= 2020 %then %do;
,case when rstrctd_bnfts_cd_&m. in ('1','A','B','D') then 1
      when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_&m. in ('4','5','7') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_&m. in ('5','7') )      then 2

	  when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_&m. in ('2','3','6','E','F') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_&m. in ('2','3','4','6','E','F') ) then 3

	 when rstrctd_bnfts_cd_&m. in ('0') then 0
	 else null end as rstrctd_bnfts_flag_&m.
%end;

%end;

/**RBF latest outside monthly loop **/

%if &year. < 2020 %then %do;
,case when rstrctd_bnfts_cd_ltst in ('1','A','B','D') then 1
      when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_ltst in ('4','7') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_ltst in ('7') )          then 2

	  when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_ltst in ('2','3','5','6') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_ltst in ('2','3','4','5','6') ) then 3

	 when rstrctd_bnfts_cd_ltst in ('0') then 0
	 else null end as rstrctd_bnfts_flag_ltst
%end;
%else %if &year. >= 2020 %then %do;
,case when rstrctd_bnfts_cd_ltst in ('1','A','B','D') then 1
      when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_ltst in ('4','5','7') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_ltst in ('5','7') )      then 2

	  when (submtg_state_cd in (&st_rbf_preg0.) and 
            rstrctd_bnfts_cd_ltst in ('2','3','6','E','F') ) or

		   (submtg_state_cd in (&st_rbf_preg1.) and 
            rstrctd_bnfts_cd_ltst in ('2','3','4','6','E','F') ) then 3

	 when rstrctd_bnfts_cd_ltst in ('0') then 0
	 else null end as rstrctd_bnfts_flag_ltst
%end;
%mend de_base_common;

%macro clm_lne_common; 
,case when cll_stus_cd not in ('542','585','654') or 
           cll_stus_cd is null then 0 
		   else 1 end as denied_clm_line_flag
%mend clm_lne_common;

%macro create_views;

	%get_taf_varlist(iph);
	%get_taf_varlist(ipl);
	%get_taf_varlist(lth);
	%get_taf_varlist(ltl);
	%get_taf_varlist(rxh);
	%get_taf_varlist(rxl);
	%get_taf_varlist(oth);
	%get_taf_varlist(otl);
	%get_taf_varlist(de);


	proc sql;
	%tmsis_connect;

	%macro claimview(inview, fil, segments=, last=0);
		
		%if &segments. =  %then %let segments = &inview.;

		%do s=1 %to %sysfunc(countw(&segments.));
			%let segment=%scan(&segments.,&s.);
			
			%dropview(&segment._autib)

			execute (
				create view &dbname..&prefix.&segment._autib as

					select
 
					  %recode_state_codes
                      ,&&varlist_&segment.

						%if &segment = ipl or &segment = ltl or &segment = otl or &segment = rxl %then %do;
						%clm_lne_common
						%end;
				

					from taf.data_anltcs_taf_&segment._vw 

					where substring(&fil._fil_dt,1,4) = %nrbquote('&year.') 
						  and ltst_run_ind=1
				    %if &segment. = iph or &segment. = lth or &segment. = oth or &segment. = rxh %then %do;
						and (submtg_state_cd != '17' or (submtg_state_cd = '17' and adjstmt_ind = '0' and adjstmt_clm_num is null))				
					%end;

			) by tmsis_passthrough;
		
		title "PRINT and COUNT of  &dbname..&prefix.&segment._autib";
		select * from connection to tmsis_passthrough
		(select * from &dbname..&prefix.&segment._autib limit 10);

		select * from connection to tmsis_passthrough
		(select count(*) as total from &dbname..&prefix.&segment._autib);

		%end;
	
	%mend claimview;


	%claimview(iph, ip, segments = iph ipl)

	%claimview(lth, lt, segments = lth ltl);

	%claimview(oth, ot, segments = oth otl);

	%claimview(rxh, rx, segments = rxh rxl);


	%macro beneview(segment);
			
		      %if &segment. = bsf %then %let ds = tmsis.taf_mon_bsf;
		%else %if &segment. = de %then %let ds = taf.data_anltcs_taf_ade_base_vw;

		%dropview(&segment._autib)

		execute (
			create view &dbname..&prefix.&segment._autib as

				select

				  %recode_state_codes
                  ,&&varlist_&segment.

				  %de_base_common
		
				from &ds.

				where ltst_run_ind=1 and substring(&segment._fil_dt,1,4) = %nrbquote('&year.')

		) by tmsis_passthrough;

		title "PRINT and COUNT of  &dbname..&prefix.&segment._autib";
		select * from connection to tmsis_passthrough
		(select * from &dbname..&prefix.&segment._autib limit 10);

		select * from connection to tmsis_passthrough
		(select count(*) as total from &dbname..&prefix.&segment._autib);
		
	%mend beneview;

	%beneview(de);

%mend create_views;

/* states_expected adds submtg_state_cd onto a lookup table so that when the look up 
table is pushed to AREMAC, it can be joined to TAF data on submtg_state_cd 

The output is a sas data set called 'states expected' that can be joined 
to an existing look up table;

	params: 
        - lookup_dsn: the name of the SAS lookup table that needs to have a state value converted to a submtg_state_cd
		- state_name: Name of the state variables in the data set;
		- abbr      : if the state name on the look up table is an abbreviation, enter yes. otherwise the default
                for full propcase state name will be used;
*/
%macro states_expected(lookup_dsn = , state_name = , abbr  = no);
	data states_expected (keep=submtg_state_cd &state_name.);
		length state_prop $30;
		do i = 1 to 56;	
			state_abbr = fipstate(i);
			state_prop = propcase(stname(state_abbr));
			if state_prop='District Of Columbia' then state_prop='District of Columbia';
		 	submtg_state_cd = put(i,z2.);
			%if &abbr. = no %then %do; 
			&state_name. = state_prop;
			%end;
			%else %do;
			&state_name = state_abbr;
			%end;
			if state_abbr > 'AA' then output;
		end;


		%if &abbr. = no %then %do; 
		&state_name. = 'Puerto Rico';
		%end;
		%else %do;
		&state_name = 'PR';
		%end;
		submtg_state_cd='72';
		output;


		%if &abbr. = no %then %do; 
		&state_name. = 'Virgin Islands';
		%end;
		%else %do;
		&state_name = 'VI';
		%end;
		submtg_state_cd='78';
		output;

		%if &abbr. = no %then %do; 
		&state_name. = 'Guam';
		%end;
		%else %do;
		&state_name = 'Gu';
		%end;
		submtg_state_cd='66';
		output;

		%if &abbr. = no %then %do; 
		&state_name. = 'Northern Mariana Islands';
		%end;
		%else %do;
		&state_name = 'MP';
		%end;
		submtg_state_cd='69';
		output;

	run;

	* Merge the benchmarks to the state information;
proc sort data=&lookup_dsn.;  by &state_name.; run;
proc sort data=states_expected; by &state_name.; run;

data &lookup_dsn.;
  merge states_expected 
        &lookup_dsn.;
  by &state_name;
  if submtg_state_cd not in ('60','69') then output;
run;

%mend states_expected;

/* macro obs to return # of obs in ds */

%macro nobs(libname=work, ds=);
	%let DSID=%sysfunc(OPEN(&libname..&ds.,IN));
	%let NOBS=%sysfunc(ATTRN(&DSID,NOBS));
	%let RC=%sysfunc(CLOSE(&DSID));
	&NOBS.
%mend nobs;

/* 
 aremac_insert takes a SAS data set as an input and converts it into a text file that will generate an AREMAC based tables
 when called with a %include. 

  params:
	dsname: insert the name of the SAS dataset to convert into AREMAC.
	lookup_path: provide the name of the folder for the lookup table
*/

%macro aremac_insert(dsname, lookup_path);

	*get variable names and formats;
	proc contents data=&dsname. out=cnt (keep=name length type varnum formatd) noprint;
	run;

	*assign Redshift data type based on SAS format;
	data cnt (keep=name redshift_type varnum type);
		set cnt;
		if type=2 then redshift_type = cats('varchar(',length,')');
			/*else if type = 1 and formatd = 0 then redshift_type = 'bigint';*/
			else if type = 1 /*and formatd > 0*/ then redshift_type = 'float';
	run;

	proc sql noprint;
		*get lists of variables and their types;
		select name, redshift_type, type
		into :varlist separated by ' ', :rtypelist separated by ' ', :typelist separated by ' '
		from cnt
		order by varnum;

		*get a count of variables;
		select count(*)
		into :varcount
		from cnt;
	quit;
	run;

	** get count of obs - if 0 will not create/use insert but just create empty table;
	** NOTE!!! This is a hack to run quickly and should be fixed;

	%let obs = %nobs(ds=&dsname.);
	%put &obs.;

	*create a dataset with the commands for inserting each row;

	%if &obs. > 0 %then %do;

		data insertcmds (keep=insert);
			set &dsname end=eof;
			length insert $500.;
			insert = '(';
			*treat last variable differently, so only go through count - 1;
			%do j = 1 %to %eval(&varcount. - 1);
				*if numeric, the data can be uploaded without quotes;
					%if %scan(&typelist.,&j.) = 1 %then %do;
					if not missing(%scan(&varlist.,&j.)) then  insert = cats(insert,%scan(&varlist.,&j.),',');
					else insert = cats(insert,'null',',');
				%end;		
				%else %do;
					if not missing(%scan(&varlist.,&j.))  then insert = cats(insert,'''',%scan(&varlist.,&j.),''',');
				    else insert = cats(insert,'null',',');
			      %end;
			%end;
			*this is for the last variable on the list;
			*if numeric, no quotes needed;
			%if %scan(&typelist.,&varcount.) = 1 %then %do;
				     if not eof and not missing(%scan(&varlist.,&j.)) then insert = cats(insert,%scan(&varlist.,&varcount.),'),');
				else if not eof and missing(%scan(&varlist.,&j.))     then insert = cats(insert,'null','),'); 
				else if eof and not missing(%scan(&varlist.,&j.)) then insert = cats(insert,%scan(&varlist.,&varcount.),');');
				else if eof and missing(%scan(&varlist.,&j.)) then insert = cats(insert,'null',');');
			%end;	
			%else %do;
					     if not eof and not missing(%scan(&varlist.,&j.)) then insert = cats(insert,'''',%scan(&varlist.,&varcount.),'''),');
				else if not eof and missing(%scan(&varlist.,&j.))     then insert = cats(insert,'null','),'); 
				else if eof and not missing(%scan(&varlist.,&j.)) then insert = cats(insert,'''',%scan(&varlist.,&varcount.),''');');
				else if eof and missing(%scan(&varlist.,&j.)) then insert = cats(insert,'null',');');
			%end;
		run;

	%end;

	data createcmd;
		length create $600.;
		create = '';
		%do j = 1 %to %eval(&varcount. - 1);
			create = cats(create,"%scan(&varlist.,&j.) %scan(&rtypelist.,&j.,,s)",', ');
		%end;
		create = cats(create,"%scan(&varlist.,&varcount.) %scan(&rtypelist.,&varcount.,,s)");
	run;
     
	*build a text file of the needed SQL commands;
   	filename inscmds "&lookup_path./&dsname..txt";
    
	data _null_;
	set 
	    createcmd
		%if &obs. > 0 %then %do; insertcmds %end; end=eof;
	file inscmds;
	if _n_ = 1 then do;
		put 'execute(';
		put "create table if not exists &dbname..&prefix.&dsname. (";
		put create;
		put ')) by tmsis_passthrough;';

		%if &obs. > 0 %then %do;
			put 'execute(';
			put "insert into &dbname..&prefix.&dsname values";
		%end;
	end;
	else do; ** NOTE! if obs=0 this is never executed because _n_ only ever equals 1 on the one-rec createcmd dataset;
	put insert;
	if eof then put ') by tmsis_passthrough;';
	end;
	run;

%mend aremac_insert;

/***
    Macro to get column names and types for AREMAC tables

    Parameters:
      table      = Name of table to describe (dbname and prefix omitted)
      schema     = Table schema (default is &dbname.)
      tbl_prefix = Table name prefix (default is &prefix.)
      out        = (optional) dataset to store query result
***/
%macro table_columns(table=, schema=&dbname., tbl_prefix=&prefix., out=);
        %if &out. ^= %then %do;
		    create table &out. as
		%end;
		select strip(col_name)  as col_name  label="Column Name" length=40
	          ,strip(data_type) as data_type label="Data Type"   length=25
	    from connection to tmsis_passthrough
		  (
		    describe table &schema..&tbl_prefix.&table.
		  );
%mend table_columns;



/***
     Parameters
       - schema: schema where the table is stored (default is &dbname.)
       - tbl_prefix: Table name prefix (default is &prefix.)
       - table: Name of table (with database name) to run frequencies on
       - columns: Comma delimited list of columns to run frequencies/crosstabs
       - where: subsetting where statement
       - out: dataset name to store output as SAS dataset if desired
***/
%macro spark_sql_freq(schema=&dbname., tbl_prefix=&prefix., table=, columns=, partition=, out=, where=);
    
    %if &partition. ^= %then %do;
	    %let partition_by = %str(partition by &partition.);
		%let columns = &partition., &columns.;
	%end;
	%else %do;
	    %let partition_by =;
	%end;

    %if &out. ^= %then %do;
        create table &out. as
	%end;
	select &columns.
	      ,frequency            format=comma30.
		  ,denom                format=comma30.          
		  ,percent              format=percent8.2
		  ,cumulative_frequency format=comma30.
		  ,cumulative_percent   format=percent8.2
    from connection to tmsis_passthrough
	  (
	    select &columns.
		      ,frequency
			  ,sum(frequency) over(&partition_by.) as denom
			  ,frequency/sum(frequency) over(&partition_by.) as percent
			  ,sum(frequency) over(&partition_by. order by &columns. rows unbounded preceding ) as cumulative_frequency
			  ,sum(frequency) over(&partition_by. order by &columns. rows unbounded preceding ) 
                /sum(frequency) over(&partition_by.) as cumulative_percent
	    from
          (
	        select &columns.
			      ,count(*) as frequency
			from &schema..&tbl_prefix.&table.
			&where.
			group by &columns.
		  )
	  )
    order by &columns.;
%mend spark_sql_freq;

** Macro tbl_exists to identify whether a table exists - will create global macro var tbl_exists
macro parms ->
	schema: schema name of table
	tbl: table name to search for

tbl_exists = 1 if table exists, otherwise 0

Note that if there happen to be a view and table with same name, this could return a value >1;

%macro tbl_exists(schema=, tbl=);

	%global tbl_exists;

	select count(*) into :tbl_exists from connection to tmsis_passthrough
	(show tables in &schema. like %nrbquote('&tbl.'));

%mend tbl_exists;

/*** Format to map state FIPS code to postal abbreviation ***/

proc format;
value $ st_fips
        '01' = "AL"
        '02' = "AK"
        '04' = "AZ"
        '05' = "AR"
        '06' = "CA"
        '08' = "CO"
        '09' = "CT"
        '10' = "DE"
        '11' = "DC"
        '12' = "FL"
        '13' = "GA"
        '15' = "HI"
        '16' = "ID"
        '17' = "IL"
        '18' = "IN"
        '19' = "IA"
        '20' = "KS"
        '21' = "KY"
        '22' = "LA"
        '23' = "ME"
        '24' = "MD"
        '25' = "MA"
        '26' = "MI"
        '27' = "MN"
        '28' = "MS"
        '29' = "MO"
        '30' = "MT"
        '31' = "NE"
        '32' = "NV"
        '33' = "NH"
        '34' = "NJ"
        '35' = "NM"
        '36' = "NY"
        '37' = "NC"
        '38' = "ND"
        '39' = "OH"
        '40' = "OK"
        '41' = "OR"
        '42' = "PA"
        '44' = "RI"
        '45' = "SC"
        '46' = "SD"
        '47' = "TN"
        '48' = "TX"
        '49' = "UT"
        '50' = "VT"
        '51' = "VA"
        '53' = "WA"
        '54' = "WV"
        '55' = "WI"
        '56' = "WY"
        '72' = "PR"
        '78' = "VI"
        '96' = "IA"
        '97' = "PA"
        Other = "XX"
        ;
run;

%macro fips_to_state_name(invar=);
	case when put(&invar.,$st_fips.) = 'DC'
	  then 'District of Columbia'
	  else propcase(stname(put(&invar.,$st_fips.)))
	end as state_name label = "State"
%mend fips_to_state_name;

/*** 
    Macro to verify a created table has > 0 records

    Inputs
      - schema     : Schema where table is stored
      - table      : Table name without prefix
      - tbl_prefix : Table name prefix
***/
%macro verify_has_records(schema=, table=, tbl_prefix=);
    ods exclude all;

	select record_count into :record_count
	from connection to tmsis_passthrough
	  (
	    select count(*) as record_count
		from &schema..&tbl_prefix.&table.
	  );

	%if &record_count. > 0 %then %do;
	    %put &schema..&tbl_prefix.&table. has &record_count. records;
	%end;
	%else %do;
	    %put ERROR: &schema..&tbl_prefix.&table. does not have records;
		%abort cancel;
	%end;

	ods exclude none;
%mend verify_has_records;

/***
    Macro to create opening wrapper for ODS Excel output

    Parameters
      - filename: Name of file to create
***/
%macro ods_excel_open(filename=, outdir=);
	options device = ACTXIMG;
	ods _all_ close;
	ods excel file = "&outdir./&filename..xlsx";
	ods excel options (embedded_titles="yes" gridlines="yes");
%mend ods_excel_open;

/*** 
    Macro to create closing wrapper for ODS Excel output
***/
%macro ods_excel_close();
	ods excel close;
	ods listing;
%mend ods_excel_close;

%macro load_sas_data_to_aremac(srcdata=, schema=, table=, tbl_prefix=&prefix., buffer=1000);
	
    /* do not load table without buffer specified */
	%if &buffer. = %then %do;
	    %put ERROR: No buffer specified, check load_sas_data_to_aremac macro;
		%abort cancel;
	%end;

	/* do not load without schema specified */
	%if &schema. = %then %do;
	    %put ERROR: No schema specified, check load_sas_data_to_aremac macro;
		%abort cancel;
	%end;

	/* do not load without table specified */
	%if &table. = %then %do;
	    %put ERROR: No table name specified, check load_sas_data_to_aremac macro;
		%abort cancel;
	%end;	

	/* do not load without srcdata specified */
	%if &srcdata. = %then %do;
	    %put ERROR: No table name specified, check load_sas_data_to_aremac macro;
		%abort cancel;
	%end;

	/* do not load if table name is too long */
	%if %eval(%sysfunc(length(&tbl_prefix.&table.)) > 32) %then %do;
	   %put ERROR: &tbl_prefix.&table. is too long. Must be <32 characters. Check load_sas_data_to_aremac macro;
	   %abort cancel;
	%end;
    /* Begin data load ---------------------------------------------------------------*/
    LIBNAME TBL_LOAD ODBC DATASRC=Databricks authdomain="TMSIS_DBK"
    SCHEMA=&schema. insertbuff=&buffer.;
    CONNECT USING TBL_LOAD as tmsis_table_load;
    EXECUTE (set val user = VALUEOF(&sysuserid)) by tmsis_table_load;

	/* Drop table if it exists */
    execute (drop table if exists &schema..&tbl_prefix.&table.) by tmsis_table_load;

	/* First, load a table in AREMAC with the lookup values;
	   one column of lookup values and each row contains one value */
    create table TBL_LOAD.&tbl_prefix.&table. as 
    select *
    from &srcdata.;

    DISCONNECT FROM tmsis_table_load;
    /* End data load -----------------------------------------------------------------*/

%mend load_sas_data_to_aremac;

/***
    Macro for generating code list macro variables

    Parameters
      - dataset: Dataset from which to extract code values
      - code_system: The code system(s) for the value set, in quotes surrounded by commas (e.g. 'CPT' or 'CPT','HCPCS')
      - macro_list_name: name of the macro variable where the list
                         of codes will be stored.
***/

%macro gen_code_list(dataset=, code_system=, macro_list_name=, gentable=no, tbl_prefix=&prefix.);

    %let max_obs = 650;	

	create table temp1 as
	select code_value
    from &dataset.
    where upcase(compress(code_system)) in %upcase((&code_system.));

	ods exclude all;
	select count(*) into :records
	from temp1;
	ods exclude none;

	/* If no records are selected, something has gone wrong.
	   Code will error and stop */
	%if &records. = 0 %then %do;
	    %put WARNING: No &code_system. codes selected for  &macro_list_name..;
        %put Check gen_code_list in 002_generate_code_lists.sas;		
		%abort cancel;
	%end;

	/* If number of records exceeds &max_obs. threshold, then we will
	   not reference the value set as a macro list. We will instead use
	   a lookup table in AREMAC. */
	%else %if %eval(&records. > &max_obs.) or (&gentable.=yes) %then %do;
	    %put INFO: &macro_list_name. has &records. elements, too big (max is &max_obs.);
        
		/* Parameter must be set to "yes" to for lookup table creation
		   to occur. Program will error and stop if this is not set */
		%if "&regen_vs_lookups." = "yes" %then %do;
		    %let table_name = &macro_list_name.;

			%put INFO: Storing in AREMAC Lookup Table &dbperm..&tbl_prefix._&table_name.;
			%load_sas_data_to_aremac(srcdata=temp1, schema=&dbperm., table=_&table_name., tbl_prefix=&tbl_prefix.);
		%end;

		/* Parameter for generating lookup tables not set, stop program
		   to alert user to potential unintentional creation of AREMAC
		   lookup table and/or use of too-large value set code list*/
		%else %do;
		    %put WARNING: regen_vs_lookups = &regen_vs_lookups., must be 'yes' to create table;
			%put WARNING: NOT GENERATED AREMAC Lookup Table &dbperm..&tbl_prefix._&table_name.;
			%abort cancel;
		%end;
	%end;

	/* If code list is less than or equal to the max list size,
	   store the code list as a comma separated macro list */
	%else %do;	    

        %global &macro_list_name;

		ods exclude all;
	    select cats("'",code_value,"'") into :&macro_list_name. separated by ","
		from temp1;
		ods exclude none;

		%if &macro_list_name. = %then %do;
		    %put WARNING: &macro_list_name. is empty. Check gen_code_list call;		
			%abort cancel;
		%end;
	%end;	

	drop table temp1;

%mend gen_code_list;


/* Macro name_msr to name a measure in the correct format with M + IB number + '_' + msr_num (left padded with 3 0s)

   input params:
       msr_num = numeric measure number will left pad with 0s to 3 digits, e.g. 1 becomes 001)
       median = default is 0, if = 1 then will add 'X' suffix to measure num
 	   suffix = default is nothing, if = a value then will add that value as a suffix to measure num
   should be called after assigning the actual value within a table statement (e.g. cnt_headers as %name_msr(1))

*/

%macro name_msr(msr_num,suffix=, median=0);

	%if &median=0 %then %do; 
		%if &suffix = %str() %then %do; &mprefix.%sysfunc(putn(&msr_num.,z3.)) %end;
		%else %do; &mprefix.%sysfunc(putn(&msr_num.,z3.))&suffix. %end;
	%end;

	%if &median=1 %then %do; 
		&mprefix.%sysfunc(putn(&msr_num.,z3.))X
	%end;
%mend;

	
/* Macro concern to create concern level based on input numeric measures. Params:
      value_num = numeric input value number from which to create concern (will left pad with 0s to 3 digits, e.g. 1 becomes 001)
      concern_num = output numeric concern number (will left pad with 0s to 3 digits, e.g. 1 becomes 001)

	  low/med/high/unus input ranges corresponding to 'Low concern', 'Medium concern', 'High concern', and 'Unusable', respectively
        for each pair, there are optional lower (a) and upper (b) range values, which must be accompanied by a preceding (for (a) or following (for (b)
        equality operator (e.g. '75 <=' for an (a) value or '>200' for a (b) value).
        If both (a) and (b) are given for the same pair, they will be combined with 'AND' to make a range.
        If both (1) and (2) are given for the same concern level, they will be combined with 'OR'.

       if there are concern assignments for a category that do not fit the above format, instead of filling in the above ranges,
       fill in low/med/high/unus _alt, where the entire parameter will be included as the assignment for the category

	if all_NA is set to 'true', the entire measure will be set to 'NA' (overriding any other ranges given)

*/

%macro concern(value_num=, 
                   concern_num=,

				   low1_a=,
				   low1_b=,
				   low2_a=,
				   low2_b=,

				   med1_a=,
				   med1_b=,
				   med2_a=,
				   med2_b=,

				   high1_a=,
				   high1_b=,
				   high2_a=,
				   high2_b=,

				   unus1_a=,
				   unus1_b=,
				   unus2_a=,
				   unus2_b=,

				   low_alt=,
				   med_alt=,
				   high_alt=,
				   unus_alt=,

				   all_NA=false


					);

		,case
		%if &all_NA.=true %then %do;
			when true then 'NA'
		%end;

		 	%if &low1_a. ne  or &low1_b. ne  %then %do;
				  when (%if &low1_a. ne %then %do; 
							&low1_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &low1_b. ne  %then %do; and %end;
						%end;
						%if &low1_b. ne %then %do; 
							&mprefix.%sysfunc(putn(&value_num.,z3.)) &low1_b. 
						%end;)

						%if &low2_a. ne  or &low2_b. ne  %then %do;

							or (%if &low2_a. ne %then %do; 
									&low2_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &low2_b. ne  %then %do; and %end;
								%end;
								%if &low2_b. ne %then %do; 
									&mprefix.%sysfunc(putn(&value_num.,z3.)) &low2_b. 
								%end;)

						%end;
					then 'Low concern'
				%end;

				%if &low_alt. ne  %then %do;
					when &low_alt. then 'Low concern'
				%end;

				%if &med1_a. ne  or &med1_b. ne  %then %do;
				  when (%if &med1_a. ne %then %do; 
							&med1_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &med1_b. ne  %then %do; and %end;
						%end;
						%if &med1_b. ne %then %do; 
							&mprefix.%sysfunc(putn(&value_num.,z3.)) &med1_b. 
						%end;)

						%if &med2_a. ne  or &med2_b. ne  %then %do;

							or (%if &med2_a. ne %then %do; 
									&med2_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &med2_b. ne  %then %do; and %end;
								%end;
								%if &med2_b. ne %then %do; 
									&mprefix.%sysfunc(putn(&value_num.,z3.)) &med2_b. 
								%end;)

						%end;
					then 'Medium concern'
				%end;

				%if &med_alt. ne  %then %do;
					when &med_alt. then 'Medium concern'
				%end;

				%if &high1_a. ne  or &high1_b. ne  %then %do;
				  when (%if &high1_a. ne %then %do; 
							&high1_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &high1_b. ne  %then %do; and %end;
						%end;
						%if &high1_b. ne %then %do; 
							&mprefix.%sysfunc(putn(&value_num.,z3.)) &high1_b. 
						%end;)

						%if &high2_a. ne  or &high2_b. ne  %then %do;

							or (%if &high2_a. ne %then %do; 
									&high2_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &high2_b. ne  %then %do; and %end;
								%end;
								%if &high2_b. ne %then %do; 
									&mprefix.%sysfunc(putn(&value_num.,z3.)) &high2_b. 
								%end;)

						%end;
					then 'High concern'
				%end;

				%if &high_alt. ne  %then %do;
					when &high_alt. then 'High concern'
				%end;

				%if &unus1_a. ne  or &unus1_b. ne  %then %do;
				  when (%if &unus1_a. ne %then %do; 
							&unus1_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &unus1_b. ne  %then %do; and %end;
						%end;
						%if &unus1_b. ne %then %do; 
							&mprefix.%sysfunc(putn(&value_num.,z3.)) &unus1_b. 
						%end; )

						%if &unus2_a. ne  or &unus2_b. ne  %then %do;

							or (%if &unus2_a. ne %then %do; 
									&unus2_a. &mprefix.%sysfunc(putn(&value_num.,z3.)) %if &unus2_b. ne  %then %do; and %end;
								%end;
								%if &unus2_b. ne %then %do; 
									&mprefix.%sysfunc(putn(&value_num.,z3.)) &unus2_b. 
								%end;)

						%end;

					then 'Unusable'
				%end;

				%if &unus_alt. ne  %then %do;
					when &unus_alt. then 'Unusable'
				%end;
					

			else 'Unclassified'
			end as &mprefix.%sysfunc(putn(%eval(&concern_num.),z3.))


%mend concern;

/* concern_overall macro to create overall concern level based on all input concerns, using the hierarchy Low < Medium < High < Unusable

  params:
    value_nums = input concern numbers (will left pad each with 0s to 3 digits, e.g. 1 becomes 001)
    concern_num = output numeric concern number (will left pad with 0s to 3 digits, e.g. 1 becomes 001)
*/

%macro concern_overall(value_nums=,
                       concern_num= );

	,case when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Unusable'
			  %end;
			  then 'Unusable'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'High concern'
			  %end;
			  then 'High concern'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Medium concern'
			  %end;
			  then 'Medium concern'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;
				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Low concern'
			  %end;
			  then 'Low concern'
		else 'Unclassified'
		end as &mprefix.%sysfunc(putn(%eval(&concern_num.),z3.))


%mend concern_overall;


/* concern_overall macro modified to create overall concern level based on all input concerns, using the hierarchy  Low < Medium < High < Unusable < Unclassified

  params:
    value_nums = input concern numbers (will left pad each with 0s to 3 digits, e.g. 1 becomes 001)
    concern_num = output numeric concern number (will left pad with 0s to 3 digits, e.g. 1 becomes 001)
*/
%macro concern_overall_v2(value_nums=,
                          concern_num=);

	,case when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Unclassified'
			  %end;
			  then 'Unclassified'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Unusable'
			  %end;
			  then 'Unusable'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'High concern'
			  %end;
			  then 'High concern'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Medium concern'
			  %end;
			  then 'Medium concern'

		when %do v=1 %to %sysfunc(countw(&value_nums.));
				 %let value=%scan(&value_nums.,&v.);
				 %if &v. > 1 %then %do; or %end;

				 &mprefix.%sysfunc(putn(%eval(&value.),z3.)) = 'Low concern'
			  %end;
			  then 'Low concern'

		end as &mprefix.%sysfunc(putn(%eval(&concern_num.),z3.))


%mend concern_overall_v2;




%macro droptable_perm(tblList,type=table);

%local i next_tbl;
%do i=1 %to %sysfunc(countw(&tblList));
   		%let next_tbl = %scan(&tblList,  &i);
		/*execute (drop &type. if exists &dbperm..&prefix.&next_tbl.) 
               by tmsis_passthrough;
        */

	%if "&type." = "table" %then %do;
		select count(1) into :exists_&i. from connection to tmsis_passthrough
	   (show tables in &dbperm. like %nrbquote('&prefix.&next_tbl.') );

	    %if &&exists_&i..=1 %then %do;
           
		   execute (
			   truncate &type. &dbperm..&prefix.&next_tbl.
		   ) by tmsis_passthrough;
           
		   execute(
			   drop &type. &dbperm..&prefix.&next_tbl.
		   ) by tmsis_passthrough;

	    %end;
	 %end;
	 %if "&type." = "view" %then %do;
	     execute(
			   drop &type. if exists &dbperm..&prefix.&next_tbl.
		   ) by tmsis_passthrough;
      %end;

%end;

%mend;
