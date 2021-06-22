/*******************************************************************************/
/* Program: 99_sud_inner_macros.sas                                        
/* Date   : 01/2019                                                             
/* Author : Rosie Malsberger                                                   
/* Purpose: SUD macros - to be included in driver program
/*******************************************************************************/


** Connection statement;

%macro tmsis_connect;
  %let query_grp=set query_group to &sysuserid;
  LIBNAME tmsi_lib SASIORST DSN=RedShift authdomain="AWS_TMSIS_QRY"  DBCONINIT="&query_grp";

  CONNECT USING tmsi_lib as tmsis_passthrough;
		EXECUTE (set query_group to &sysuserid) by tmsis_passthrough;
		EXECUTE (set search_path to cms_prod) by tmsis_passthrough;
%mend tmsis_connect;

** Macro to determine if year is leap year - must be divisible by 4 and NOT divisible by 100, unless also divisible by 400;

%macro leapyear;

	%if %sysfunc(mod(&year.,4)) = 0 and (%sysfunc(mod(&year.,100)) > 0 or %sysfunc(mod(&year.,400)) = 0)
	    %then %let leap=1;

	%else %let leap=0;

	%if &leap.=1 %then %let totdays=366;
	%else %let totdays=365;

%mend leapyear;

** Macro redshift_insert, copied directly from tool 1 code;

%macro redshift_insert(dsname);

	*get variable names and formats;
	proc contents data=&dsname. out=cnt (keep=name length type varnum formatd) noprint;
	run;

	*assign Redshift data type based on SAS format;
	data cnt (keep=name redshift_type varnum type);
		set cnt;
		if type=2 then redshift_type = cats('varchar(',length,')');
			else if type = 1 and formatd = 0 then redshift_type = 'bigint';
			else if type = 1 and formatd > 0 then redshift_type = 'float8';
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

	*create a dataset with the commands for inserting each row;
	data insertcmds (keep=insert);
		set &dsname end=eof;
		length insert $200.;
		insert = '(';
		*treat last variable differently, so only go through count - 1;
		%do j = 1 %to %eval(&varcount. - 1);
			*if numeric, the data can be uploaded without quotes;
			%if %scan(&typelist.,&j.) = 1 %then %do;
				insert = cats(insert,%scan(&varlist.,&j.),',');
			%end;		
			%else %do;
				insert = cats(insert,'''',%scan(&varlist.,&j.),''',');
			%end;
		%end;
		*this is for the last variable on the list;
		*if numeric, no quotes needed;
		%if %scan(&typelist.,&varcount.) = 1 %then %do;
			if not eof then insert = cats(insert,%scan(&varlist.,&varcount.),'),');
			else insert = cats(insert,%scan(&varlist.,&varcount.),');');
		%end;	
		%else %do;
			if not eof then insert = cats(insert,'''',%scan(&varlist.,&varcount.),'''),');
			else insert = cats(insert,'''',%scan(&varlist.,&varcount.),''');');
		%end;
	run;

	data createcmd;
		length create $200.;
		create = '';
		%do j = 1 %to %eval(&varcount. - 1);
			create = cats(create,"%scan(&varlist.,&j.) %scan(&rtypelist.,&j.,,s)",', ');
		%end;
		create = cats(create,"%scan(&varlist.,&varcount.) %scan(&rtypelist.,&varcount.,,s)");
	run;

	*build a text file of the needed SQL commands;
	filename inscmds "&indata./&dsname..txt";
	data _null_;
	set 
	    createcmd
		insertcmds end=eof;
	file inscmds;
	if _n_ = 1 then do;
		put 'execute(';
		put "create temp table &dsname. (";
		put create;
		put ');';
		put "insert into &dsname. values";
	end;
	else do;
	put insert;
	if eof then put ') by tmsis_passthrough;';
	end;
	run;

	 
	 proc datasets lib=work;
	 delete insertcmds createcmd cnt;
	 run;

%mend redshift_insert;

** Macro create_tool1_lookups - modified code from tool 1 to read in lookup lists and create text files;

%macro create_tool1_lookups(excel=);

	******************************
	FACILITY
	******************************;
	PROC IMPORT DATAFILE = "&indata./&excel."
				DBMS	 = XLSX 
				OUT 	 = FAC_RAW
				REPLACE;
				GETNAMES = NO;
				SHEET    = "SUD Facility claims";
				DATAROW  = 3;
	RUN;

	DATA FAC_ALL CODES_FAC (keep=CODE_SOURCE CODE USE_DX RULE CATEGORY) CODES_OFAC (keep=CODE_SOURCE CODE USE_DX RULE CATEGORY);
	LENGTH CODE_SOURCE $10 CODE $15;
	SET FAC_RAW;
	if missing(A) then delete;

		IF SUBSTR(E,1,1) = '1' THEN RULE = 1;
		ELSE IF SUBSTR(E,1,1) = '2' THEN RULE = 2;
		ELSE RULE = 3;

		IF B = 'Type of bill codes' THEN CODE_SOURCE = "TOB";
		ELSE IF UPCASE(SCAN(B, 1, " ")) IN ("HCPCS", "CPT") THEN CODE_SOURCE = "CPT";
		ELSE IF UPCASE(SCAN(B, 1, " ")) IN ("ICD-10","ICD-9") THEN CODE_SOURCE = "ICD";
		ELSE IF UPCASE(SCAN(B, 1, " ")) = "REVENUE" THEN CODE_SOURCE = "REV";

		CODE = COMPRESS(C,"*");

		USE_DX = 1;

		IF A = 'Overnight facility claims' THEN CATEGORY = "OFAC";
		ELSE IF UPCASE(SCAN(A, 1, " ")) = "FACILITY" THEN CATEGORY = "FAC";

		OUTPUT FAC_ALL;

		IF CATEGORY = "OFAC" THEN OUTPUT CODES_OFAC;
		ELSE IF CATEGORY = "FAC" THEN OUTPUT CODES_FAC;
	RUN;

	title2 "QC creation of facility lists - full file";

	proc freq data=FAC_ALL;
		tables a * b * code_source * category e * rule / list missing;
	run;

	title2 "QC creation of facility lists - OFAC only";

	proc freq data=CODES_OFAC;
		tables category * code_source / list missing;;
	run;

	title2 "QC creation of facility lists - FAC only";

	proc freq data=CODES_FAC;
		tables category * code_source / list missing;;
	run;


	******************************
	PROFESSIONAL
	*****************************;
	PROC IMPORT DATAFILE = "&indata./&excel."
					DBMS	 = XLSX 
					OUT 	 = PROF_RAW
					REPLACE;
					GETNAMES = NO;
					SHEET    = "SUD Professional claims";
					DATAROW  = 3;
	RUN;


	DATA CODES_PROF;
	LENGTH CODE_SOURCE  $10 CODE $15;
	SET PROF_RAW;

			IF INDEX(UPCASE(D), "PLACE OF SERVICE") > 0 THEN RULE = 4;
		ELSE IF SUBSTR(D,1,1) = '1' THEN RULE = 1;
		ELSE IF SUBSTR(D,1,1) = '2' THEN RULE = 2;
		ELSE RULE = 3;

		IF UPCASE(SCAN(A, 1, " ")) IN ("HCPCS", "CPT") THEN CODE_SOURCE = "CPT";
		ELSE IF UPCASE(SCAN(A, 1, " ")) IN ("ICD-10","ICD-9") THEN CODE_SOURCE = "ICD";

		CODE = COMPRESS(B,"*");

		USE_DX = 1;

		CATEGORY = "PROF";

		IF NOT MISSING(C) THEN OUTPUT;
	RUN;

	title2 "QC creation of prof codes";

	proc freq data=CODES_PROF;
		tables a * code_source * category d * rule / list missing;
	run;

	data CODES_PROF;
		set CODES_PROF;
		keep CODE_SOURCE CODE USE_DX RULE CATEGORY;
	run;

	******************************
	All Diagnoses
	******************************;
	%MACRO READIN_SUD(SUD, sheet=);

	%if &sheet. =  %then %let sheet= &SUD. Dx;

	PROC IMPORT DATAFILE = "&indata./&excel."
				DBMS	 = XLSX 
				OUT 	 = &SUD._RAW
				REPLACE;
				GETNAMES = NO;
				SHEET    = "&sheet.";
				DATAROW  = 3;
	RUN;

	DATA &SUD.(KEEP = CODE DESC_LONG DESC_SHORT CATEGORY);
	SET &SUD._RAW;
	LENGTH CODE $ 15;


		%if &sud = OPIOIDS %then %let sud = opioid;
		RENAME B = CODE; 
		RENAME C = DESC_LONG;
		DESC_SHORT = LOWCASE("&SUD."); 
		CATEGORY = "DX";

		WHERE NOT MISSING(C) and B ne " > 1 SUD";

	RUN;

	title2 "Diagnosis codes: &sud.";

	proc freq;
		tables DESC_SHORT / missing;
	run;


	%MEND READIN_SUD;

	%READIN_SUD(ALCOHOL);
	%READIN_SUD(%STR( Tobacco));
	%READIN_SUD(OPIOIDS);
	%READIN_SUD(CANNABIS);
	%READIN_SUD(CAFFEINE);
	%READIN_SUD(HALLUCINOGENS);
	%READIN_SUD(INHALANTS);
	%READIN_SUD(STIMULANTS);
	%READIN_SUD(POLYSUBSTANCE);
	%READIN_SUD(SHA, sheet=%str(Sedatives, Hypnotics, Anxi. Dx))
	%READIN_SUD(OTHER, sheet=%str(Other or Unknown Dx))

	proc sql;

	CREATE TABLE CODES_SUD AS 
	SELECT CODE, DESC_SHORT FROM ALCOHOL WHERE LENGTH(CODE) < 12
	UNION ALL
	SELECT CODE, DESC_SHORT FROM TOBACCO WHERE LENGTH(CODE) < 12
	UNION ALL
	SELECT CODE, DESC_SHORT FROM OPIOIDS WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM CANNABIS WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM CAFFEINE WHERE LENGTH(CODE) < 12
	UNION ALL
	SELECT CODE, DESC_SHORT FROM HALLUCINOGENS WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM INHALANTS WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM STIMULANTS WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM POLYSUBSTANCE WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM SHA WHERE LENGTH(CODE) < 12
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM OTHER WHERE LENGTH(CODE) < 12
	;
	QUIT;


	title2 "All SUD diagnosis codes stacked";

	proc freq data=codes_sud;
		tables desc_short;
	run;


	******************************
	SUD RX
	******************************;
	%MACRO READIN_RX(SUD,SHEET);
	PROC IMPORT DATAFILE = "&indata./&excel."
				DBMS	 = XLSX 
				OUT 	 = &SUD.RX_RAW
				REPLACE;
				GETNAMES = NO;
				SHEET    = "&SHEET.";
				DATAROW  = 3;
	RUN;

	DATA &SUD.RX(KEEP = CODE DESC_LONG DESC_SHORT CATEGORY);
	SET &SUD.RX_RAW;
		LENGTH CODE $ 15;

		%if &sud = OPIOIDS %then %let sud = opioid;

		length desc_short $ 30;

		RENAME A = CODE; 
		RENAME B = DESC_LONG;
		DESC_SHORT = LOWCASE("&SUD.");
		CATEGORY = "RX";

		WHERE NOT MISSING(A) and A ne 'End of worksheet';
	RUN;
	%MEND READIN_RX;


	%READIN_RX(ALCOHOL, %STR(ALCOHOL RX));
	%READIN_RX(TOBACCO, %STR(TOBACCO RX));
	%READIN_RX(OPIOIDS, %STR(OPIOIDS_RX));

	DATA NATLRX;
	SET ALCOHOLRX;

	DESC_SHORT = "naltrexone";
	WHERE INDEX(DESC_LONG,"NALTREXONE") > 0;

	RUN;

	DATA NATLRX2;
	SET OPIOIDSRX;

	DESC_SHORT = "naltrexone";
	WHERE INDEX(DESC_LONG,"NALTREXONE") > 0;

	RUN;


	PROC SQL;
	CREATE TABLE CODES_RX AS 
	SELECT CODE, DESC_SHORT FROM ALCOHOLRX
	UNION ALL
	SELECT CODE, DESC_SHORT FROM TOBACCORX
	UNION ALL
	SELECT CODE, DESC_SHORT FROM OPIOIDSRX
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM NATLRX 
	UNION ALL 
	SELECT CODE, DESC_SHORT FROM NATLRX2
	;
	QUIT;

	title2 "All RX codes";

	proc freq data=codes_rx;
		tables desc_short / missing;
	run;


	/**OUTPUT ALL SHEETS*/

	%redshift_insert(codes_fac)
	%redshift_insert(codes_ofac)
	%redshift_insert(codes_prof)
	%redshift_insert(codes_sud)
	%redshift_insert(codes_rx)


%mend create_tool1_lookups;




** Read in SUD-specific procedure, revenue, and place of service codes to create a text file that will create a lookup table
   (used to identify SUD services with method 3, which does not use diagnosis codes);

%macro redshift_insert_sud_codes(excel=);

	proc import datafile="&indata./&excel." dbms=xlsx replace out=sud_codes;
		sheet="SUD specific codes";
		getnames=no;
	run;

	** Create a dataset with the commands for inserting each row - run for all three columns.
	   For procedure codes only, we will identify as OUD;

	%macro bycol(names,col);

		data codes_sud_&col. (keep=insert);
			set sud_codes end=eof;
			where B in (&names.) and E='Yes';
			length insert $200.;
			insert = "('";
			if not eof then insert = cats(insert,C,"','",F,"'),");
			if eof then insert = cats(insert,C,"','",F,"');");
		
		run;

		** Build a text file of the needed SQL commands;

		filename inscmds "&indata./codes_sud_&col..txt";
		data _null_; 
			set codes_sud_&col. end=eof;
			file inscmds;
			if _n_ = 1 then do;
				put 'execute(';
				put "create temp table codes_sud_&col. (&col. varchar(8), OUD varchar(3));";
				put "insert into codes_sud_&col. values";
			end;
			put insert;
			if eof then put ') by tmsis_passthrough;';
		run; 

	%mend bycol;

	%bycol(%nrstr('ICD-10 procedure code','HCPCS code','CPT code'),prcdr_cd)
	%bycol(%nrstr('Revenue code'),rev_cd)
	%bycol(%nrstr('Place of service code'),srvc_plc_cd);

%mend redshift_insert_sud_codes;

** Read in crosswalk of setting and service types (to map procedure/TOB/POS/rev codes);

%macro redshift_insert_mapping(excel=);

	proc import datafile="&indata./&excel." dbms=xlsx replace out=setting_types;
		sheet="Setting Types";
		getnames=no;
	run;

	data setting_types2;
		set setting_types end=eof;
		where B not in ('','Type of code') and E ne '';
		
		** Create TYPE;
		length TYPE $20;
		if B in ('CPT code','HCPCS code') then TYPE='PRCDR';
		else if B = 'Place of service code' then TYPE='SRVC_PLC';
		else if B = 'Type of bill code' then TYPE='BILL_TYPE';
		else if B = 'Revenue code' then TYPE='REV';

		** Recode Community-based to Community;

		if E='Community-based' then E='0. Community';

		** ADD NUMBERS TO BEGINNING OF EACH SETTING SO THAT CAN TAKE MAX ACROSS REV CODE VALUES;

		else if E='Outpatient' then E='4. Outpatient';
		else if E='Home' then E='3. Home';
		else if E='Residential' then E='2. Residential';
		else if E='Inpatient' then E='1. Inpatient';

		** DELETE all values with a setting = Unknown;

		if E='Unknown' then delete;

		length insert $200.;
		insert = "('";
		if not eof then insert = cats(insert,TYPE,"','",C,"','",E,"'),");
		if eof then insert = cats(insert,TYPE,"','",C,"','",E,"');");
	run;

	proc freq data=setting_types2;
		tables B * TYPE E / list missing;
		title "QC creation of TYPE for setting crosswalk";
	run;

	** Build a text file of the needed SQL commands;

	filename inscmds "&indata./codes_setting.txt";
	data _null_; 
		set setting_types2 end=eof;
		file inscmds;
		if _n_ = 1 then do;
			put 'execute(';
			put "create temp table codes_setting (TYPE varchar(15), CODE varchar(15), SETTING_TYPE varchar(20));";
			put "insert into codes_setting values";
		end;
		put insert;
		if eof then put ') by tmsis_passthrough;';
	run; 

	** Now do the same, but for Service Types;

	proc import datafile="&indata./&excel." dbms=xlsx replace out=service_types;
		sheet="Service types";
		getnames=no;
	run;

	data service_types2;
		set service_types end=eof;
		where B not in ('','Procedure Code Type') and E ne '';

		** For MAT, retain original Alcohol/Opioid/Tobacco values before collapsing.
           Remove Replacement from Nicotine Replacement so all categories are only one word long; 

		if index(E,'MAT')>0 then MAT_TYPE=E;
		MAT_MED_CAT=F;
		if MAT_MED_CAT='Nicotine replacement' then MAT_MED_CAT='Nicotine';
		
		** Create TYPE;
		length TYPE $20;
		if B = 'National drug code' then TYPE='NDC';
        else if B = 'Revenue code' then TYPE='REV';
        else TYPE='PRCDR';

		if index(E,'MAT')>0 then E = 'MAT';

		length insert $200.;
		insert = "('";
		if not eof then insert = cats(insert,TYPE,"','",C,"','",E,"','",MAT_TYPE,"','",MAT_MED_CAT,"'),");
		if eof then insert = cats(insert,TYPE,"','",C,"','",E,"','",MAT_TYPE,"','",MAT_MED_CAT,"');");
	run;

	proc freq data=service_types2;
		tables B * TYPE MAT_TYPE MAT_MED_CAT MAT_TYPE * MAT_MED_CAT / list missing;
		title "QC creation of TYPE for service crosswalk";
	run;

	** Build a text file of the needed SQL commands;

	filename inscmds "&indata./codes_services.txt";
	data _null_; 
		set service_types2 end=eof;
		file inscmds;
		if _n_ = 1 then do;
			put 'execute(';
			put "create temp table codes_services (TYPE varchar(15), CODE varchar(15), SERVICE_TYPE varchar(50), MAT_TYPE varchar(30), MAT_MED_CAT varchar(30));";
			put "insert into codes_services values";
		end;
		put insert;
		if eof then put ') by tmsis_passthrough;';
	run; 

%mend redshift_insert_mapping;

%macro recode_state_codes(prefix=);

	case when &prefix..submtg_state_cd in ('30','94') then '30'
	      when &prefix..submtg_state_cd in ('42','97') then '42'
	      when &prefix..submtg_state_cd in ('56','93') then '56'
	      else &prefix..submtg_state_cd 
          end as submtg_state_cd

	,case when &prefix..submtg_state_cd in ('30', '42', '56',
                                  '94', '97', '93')
           then concat(&prefix..msis_ident_num, &prefix..submtg_state_cd)
           else &prefix..msis_ident_num  
           end as msis_ident_num
                     

%mend recode_state_codes;

/* Macro readclaims to read in both header and line files for given year, keeping needed cols.
   Only keep FFS/ENC records;
   Macro parms:
      fltype=claim type
      hvars=header vars
      lvars=line vars
      hvars_nulls=header vars to examine for nulls
      lvars_nulls=line vars to examine for nulls */

%macro readclaims(fltype, hvars=, lvars=, hvars_nulls=, lvars_nulls=);

	execute (
		create temp table &fltype.H as
		select %recode_state_codes(prefix=a)
		       ,&fltype._fil_dt,
			   da_run_id,
			   &fltype._link_key,
			   mc_plan_id,
			   clm_type_cd,

			   /* Create indicators for MC or FFS claim */ 

			   case when mc_plan_id is not null or clm_type_cd in ('3','C','W')
			        then 1 else 0
					end as CLAIM_MC,

				case when CLAIM_MC=0
			        then 1 else 0
					end as CLAIM_FFS

			   %do h=1 %to %sysfunc(countw(&hvars.));
			   	  %let hvar=%scan(&hvars.,&h.);

				  	,&hvar.

				%end;

				%if &fltype. = IP %then %do;

					%do p=1 %to 6;
						,case when submtg_state_cd='06' and prcdr_&p._cd='Z7502' then '99281'
						      when submtg_state_cd='06' and prcdr_&p._cd='00001' then 'T1015'
							  when submtg_state_cd='24' and prcdr_&p._cd='W9520' then 'H0020'
                              else prcdr_&p._cd 
                              end as prcdr_&p._cd
					  %end; 

					  /* For GA only, must identify actual IP claims in IP file - all other claims must go into
						     OT file. For all other states just set IP_CLM=1. Will move claims with IP_CLM=0 to OT file. */

						 ,case when submtg_state_cd != '13' or
						           (submtg_state_cd = '13' and hosp_type_cd in ('01','05') and 
						 		    length(bill_type_cd)=4 and substring(bill_type_cd,2,2) in ('11','12'))
								then 1
								else 0
								end as IP_CLM

					/* for TN only, must apply diagnosis code fix to remove leading zeros */

					  %do d=1 %to 12;

						,dgns_&d._cd as dgns_&d._cd_orig
						,case when submtg_state_cd != '47' then dgns_&d._cd

						      when submtg_state_cd = '47' and substring(dgns_&d._cd,1,4) = '0000' then substring(dgns_&d._cd,5)
							  when submtg_state_cd = '47' and substring(dgns_&d._cd,1,3) = '000' then substring(dgns_&d._cd,4)
							  when submtg_state_cd = '47' and substring(dgns_&d._cd,1,2) = '00' then substring(dgns_&d._cd,3)
							  when submtg_state_cd = '47' and substring(dgns_&d._cd,1,1) = '0' then substring(dgns_&d._cd,2)

							  else dgns_&d._cd
							  end as dgns_&d._cd

					  %end;

				%end;

				/* For all files except RX, create second version of bill type code that adds asterisks (to be able
				   to match to lookup tables where we allow for any third/fourth digit) - look to any fourth digit for all values except
				   03, where we look to any third or fourth digit*/

				%if &fltype. ne RX %then %do;

					,case when length(bill_type_cd)=4 and substring(bill_type_cd,1,2) in ('03')
						 then substring(bill_type_cd,1,2)||'**'

                         when length(bill_type_cd)=4
				         then substring(bill_type_cd,1,3)||'*'

						 else null
						 end as bill_type_cd_lkup

				%end;


		from cms_prod.data_anltcs_taf_&fltype.h_vw a

		where ltst_run_ind=1 and 
              substring(&fltype._fil_dt,1,4) = %nrbquote('&year.') and
              clm_type_cd in ('1','U','3','W') and
		      (submtg_state_cd != '17' or (submtg_state_cd = '17' and adjstmt_ind = '0' and adjstmt_clm_num is null)) and
		       submtg_state_cd not in (&states_exclude.)

	) by tmsis_passthrough;

	title2 "Run IDs pulled - &fltype.";

	%crosstab(&fltype.H, &fltype._fil_dt da_run_id)

	** Now join to line - add _temp suffix to IP/OT files because must remove all non-IP claims from GA IP file and put 
	   into OT, and then create final tables.;

	%if &fltype. = IP or &fltype. = OT %then %let suffix=_temp;
	%else %let suffix=;

	execute (
		create temp table &fltype.HL&suffix. as
		select a.*
		       ,CLL_STUS_CD
			   ,orgnl_line_num
				%if &fltype. ne RX %then %do;
			       ,b.srvc_bgnng_dt as srvc_bgnng_dt_line
			   	   ,b.srvc_endg_dt as srvc_endg_dt_line
				%end;

			   %do l=1 %to %sysfunc(countw(&lvars.));
			   	  %let lvar=%scan(&lvars.,&l.);

				  	,&lvar.

				%end;


				/* For OT, want to rename prcdr_cd to prcdr_1_cd to more easily loop over
				   when joining to (so can loop over 1 code for OT and 6 codes for IP, with same naming convention).
				   Do same for hcpcs_rate (as procedure code 2);
				   Also for CA and MD, recode state-specific values */

				%if &fltype. = OT %then %do;

					,case when a.submtg_state_cd='06' and prcdr_cd='Z7502' then '99281'
						  when a.submtg_state_cd='06' and prcdr_cd='00001' then 'T1015'
						  when a.submtg_state_cd='24' and prcdr_cd='W9520' then 'H0020'
                          else prcdr_cd 
                          end as prcdr_1_cd

					,case when a.submtg_state_cd='06' and hcpcs_rate='Z7502' then '99281'
						  when a.submtg_state_cd='06' and hcpcs_rate='00001' then 'T1015'
						  when a.submtg_state_cd='24' and hcpcs_rate='W9520' then 'H0020'
                          when length(hcpcs_rate)=5 and hcpcs_rate != '00000' and
                               regexp_count(trim(substring(hcpcs_rate,1,5)),'[^0-9A-Z]+') = 0  
						  then hcpcs_rate
						  else null
                          end as prcdr_2_cd

				%end;


		from &fltype.H a
		     left join
			 cms_prod.data_anltcs_taf_&fltype.l_vw b

		on a.&fltype._fil_dt = b.&fltype._fil_dt and
		   a.da_run_id = b.da_run_id and
		   a.&fltype._link_key = b.&fltype._link_key

	) by tmsis_passthrough;


	**** Now must reformat GA IP to look like OT;

	%if &fltype. = IP %then %do;

		** Create dummy table with six procedure code records, which will then join to six IP procedure codes and
		   rename to get into the format of OT (one line per procedure code);

		   execute (
		   		create temp table dummyproc (procnum int);

				insert into dummyproc
				values (1), (2), (3), (4), (5), (6);

		   ) by tmsis_passthrough;

		   ** Now do a full join of the procedure codes;

		   execute (
		   	  create temp table GA_PROCS as

			  select &fltype._link_key
			         ,case %do p=1 %to 6;
					           when procnum=&p. then prcdr_&p._cd_orig
							%end;
					  end as prcdr_1_cd

			  from (

			  	 select &fltype._link_key
				        %do p=1 %to 6;
						 	,prcdr_&p._cd as prcdr_&p._cd_orig
						%end;
						,procnum

				 from (select * from &fltype.H where IP_CLM=0) a
				      join
					  dummyproc b
					  on true )

			 where prcdr_1_cd is not null 

		   ) by tmsis_passthrough;


			execute (
				create temp table GA_IP_TO_OT as
				select a.submtg_state_cd,
					   msis_ident_num,
				       a.&fltype._fil_dt,
					   a.da_run_id,
					   a.&fltype._link_key,
					   mc_plan_id,
					   clm_type_cd,
					   CLAIM_MC,
					   CLAIM_FFS,
					   admsn_dt as srvc_bgnng_dt,
					   dschrg_dt as srvc_endg_dt,
					   bill_type_cd,
					   null as srvc_plc_cd

					   %do i=1 %to 2;
						,dgns_&i._cd
					  %end;
					  ,bill_type_cd_lkup

					  ,CLL_STUS_CD
					  ,orgnl_line_num
					  ,srvc_bgnng_dt_line
					  ,srvc_endg_dt_line
					  ,rev_cd
					  ,ndc_cd
					  ,b.prcdr_1_cd
					  ,'XXXX' as prcdr_2_cd

				from (select * from &fltype.HL&suffix. where IP_CLM=0) a
				     left join
					 GA_PROCS b

				on a.&fltype._link_key = b.&fltype._link_key

			) by tmsis_passthrough;

			
		** Now subset IP lines to IP_CLM=1;

		execute (
			create temp table &fltype.HL as
			select * from &fltype.HL&suffix.
			where IP_CLM=1

		) by tmsis_passthrough;


	%end; ** end of IP loop;

	** Now for OT, must union extracted IP claims with full OT lines;

	%if &fltype. = OT %then %do;

		execute (
			create temp table &fltype.HL as

			select *, 0 as FROM_IP from &fltype.HL&suffix.

			union all
			select *, 1 as FROM_IP from GA_IP_TO_OT

		) by tmsis_passthrough;

	%end;

	** Finally join to the desired population to only keep claims for benes in the population;

	execute (	
		create temp table &fltype.HL1 as
		select b.*

		from population a
		     inner join
			 &fltype.HL b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num


	) by tmsis_passthrough; 


%mend readclaims;

%macro join_sud_dgns(fltype,ndiag=);

	** Join header diagnosis codes to lookup table. Keep descriptions and types for ALL slots. Create an indicator
       for SUD claim (look across all slots), and indicators for each condition; 

	execute (
		create temp table &fltype.HL2 as
		select a.*
		       %do d=1 %to &ndiag.;
			       ,d&d..desc as desc_&d.
				%end;

				,case when %do d=1 %to &ndiag.;
							 %if &d. > 1 %then %do; or %end;

							 desc_&d. is not null
							%end;
					 then 1 else 0
					 end as SUD_DGNS

				%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);

					,case when %do d=1 %to &ndiag.;
							      %if &d. > 1 %then %do; or %end;

							      desc_&d. = %nrbquote('&ind.')

							   %end;
					 then 1 else 0
					 end as &ind._SUD_DSRDR_DGNS

				%end;

				/* Create a count of unique different disorders to look at those with multiples and ensure assigned correctly */

				,%do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);
					&ind._SUD_DSRDR_DGNS
                        %if &s. < %sysfunc(countw(&indicators.)) %then %do; + %end;

				 %end; as SUD_DSRDR_CNT_DGNS


		from &fltype.HL1 a

			 %do d=1 %to &ndiag.;

		     	left join 
			 	codes_sud2 d&d.

				 on a.dgns_&d._cd = d&d..CODE 

			%end;

		) by tmsis_passthrough;

%mend join_sud_dgns;

%macro lab_transport(fltype, nproc=);

		** Identify any procedure code that is NOT lab/transport and not null. Count the number
           of lab/transport codes and number of non-null codes;

		execute (
			create temp table &fltype.HL_labt as

			select *
	 	            %do p=1 %to &nproc.;
					   	,case when (prcdr_&p._cd >= '70000' and prcdr_&p._cd <= '89999')
                                    or prcdr_&p._cd in ('G0480','G0481','G0482','G0483')
							  then 1
							  else 0
							  end as prcdr_&p._cd_labtrans

						,case when prcdr_&p._cd is not null
						      then 1 else 0
							  end as prcdr_&p._cd_not_null
					%end;

					,%do p=1 %to &nproc.;
					    %if &p. > 1 %then %do; + %end;
						prcdr_&p._cd_labtrans
					%end;
					as n_prcdr_labtrans

					,%do p=1 %to &nproc.;
					    %if &p. > 1 %then %do; + %end;
						prcdr_&p._cd_not_null
					%end;
					as n_prcdr_not_null

					,case when n_prcdr_not_null = n_prcdr_labtrans and n_prcdr_not_null != 0
					      then 1 else 0
						  end as all_prcdr_labtrans

			from &fltype.HL2

		) by tmsis_passthrough;

		 ** Now subset to those with all_prcdr_labtrans=0;

		 execute (
		 	create temp table &fltype.HL_labt2 as
			select * 
			from &fltype.HL_labt
			where all_prcdr_labtrans=0

		 ) by tmsis_passthrough;

%mend lab_transport;

%macro join_sud_rx(fltype, tbl, suffix=_RX);

	execute (
		create temp table &fltype.HL3 as
		select a.*,
			   case when b.CODE is not null 
			        then 1 else 0
					end as SUD_RX

			   %do s=1 %to %sysfunc(countw(&indicators.));
					%let ind=%scan(&indicators.,&s.);

					,case when b.desc = %nrbquote('&ind.')
					 then 1 else 0
					 end as &ind._SUD_DSRDR&suffix.

				%end;

		from &fltype.&tbl. a
		     left join
			 codes_rx2 b

		on a.ndc_cd = b.CODE

	) by tmsis_passthrough;

	** For all files except RX, take the MAX of all inds across the header (to then join back to header);

	%if &fltype. ne RX %then %do;

		execute (
			create temp table &fltype._rx_oneline as
			select submtg_state_cd,
			       &fltype._link_key,
				   max(SUD_RX) as SUD_RX
				   %do s=1 %to %sysfunc(countw(&indicators.));
						%let ind=%scan(&indicators.,&s.);
						,max(&ind._SUD_DSRDR_RX) as &ind._SUD_DSRDR_RX
					%end;

			from &fltype.HL3
			where SUD_RX=1
			group by submtg_state_cd,
			         &fltype._link_key

		) by tmsis_passthrough;

		** Now join the table with SUD diagnosis codes with SUD RX lines and 
		   keep if on either. For claims that had an RX line, set the SUD tool rule flag to 1 (so that
		   when combine with other files will then take the minimum rule across all the lines
		   within the given claim, and all RX records will be set to 1);

		execute (
			create temp table &fltype._sud as
			select a.*,
			       SUD_RX,
				   case when SUD_RX=1 
				        then 1 else null
						end as SUD_TOOL_RULE_RX

			       %do s=1 %to %sysfunc(countw(&indicators.));
					  %let ind=%scan(&indicators.,&s.);
						,&ind._SUD_DSRDR_RX

						,case when &ind._SUD_DSRDR_DGNS=1 or &ind._SUD_DSRDR_RX=1
						      then 1 else 0
							  end as &ind._SUD_DSRDR
					%end;

			from &fltype.&tbl. a
			     full join
				 &fltype._rx_oneline b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.&fltype._link_key = b.&fltype._link_key

			where SUD_DGNS=1 or SUD_RX=1

		) by tmsis_passthrough;


	%end; ** end ne RX loop;

	** For RX only, take SUD RX records and subset to SUD_RX records only. This file will now be the same
	   as for the other file types above - line-level and subset to SUD records;

	%if &fltype. = RX %then %do;

		execute (
			create temp table &fltype._sud as
			select *,
			       1 as SUD_TOOL_RULE_RX

			from &fltype.HL3
			where SUD_RX=1
		) by tmsis_passthrough;

	%end;

%mend join_sud_rx;

%macro join_sud_fac(fltype, codetype=, nproc=);

	** Join IP/LT to lookup table for overnight facilities based on bill type code,
       revenue code, or procedure code (IP only). 
       For OT, join rev and procedure only to the facilities lookup table.
       NOTE we will still allow to join to bill type code lookup for simplicity,
       but there are no bill type codes in the fac lookup list so there will be no hits.

	   Look across all the RULE values for
       the line to get the minimum for the line, which will then need to be rolled up to the
       header level to get the minimum across all lines on the claim;

	execute (
		create temp table &fltype._sud2 as
		select a.*,
		       b.RULE as bill_type_cd_rule,
			   r.RULE as rev_cd_rule

				%if &nproc. ne  %then %do p=1 %to &nproc.;
					,p&p..RULE as prcdr_&p._cd_rule
				%end;

				,least(bill_type_cd_rule, rev_cd_rule %if &nproc. ne  %then %do p=1 %to &nproc.; ,prcdr_&p._cd_rule %end;) 
                       as SUD_TOOL_RULE_FAC	


		from &fltype._sud a
		     left join
			 (select * from codes_&codetype. where CODE_SOURCE='TOB') b

			on a.bill_type_cd_lkup = b.CODE

			left join
			(select * from codes_&codetype. where CODE_SOURCE='REV') r

			on a.rev_cd = r.CODE

		%if &nproc. ne  %then %do p=1 %to &nproc.;

		     left join 
			 (select * from codes_&codetype. where CODE_SOURCE in ('ICD','CPT')) p&p.

			on a.prcdr_&p._cd = p&p..CODE

		%end;


	) by tmsis_passthrough;

%mend join_sud_fac;

%macro join_sud_prof(fltype);

	execute (
		create temp table &fltype._sud3 as
		select a.*,
			
			   /* For the rule - a value of 4 = 1+ claims of POS=21, 51, otherwise 2 claims. Reset the rule to align with all
		          other rules so that if POS=21, 51, the rule = 1, otherwise the rule = 2 */

		       b.rule as RULE,
			   case when RULE = 4 and srvc_plc_cd in ('21','51') then 1
			        when RULE = 4 then 2
					else RULE
					end as SUD_TOOL_RULE_PROF
		       

		from &fltype._sud2 a
		     left join
			 codes_prof b

		on a.prcdr_1_cd = b.CODE


	) by tmsis_passthrough;

%mend join_sud_prof;

%macro rollup(fltype, tbl=, rules=, dates=);

	** Roll up the line-level file to the header:
       Take the minimum value across all relevant RULE columns for the given file type to create one value for the claim.
 
       Take the minimum of all dates - note some dates are at the header-level, but can still take minimum (this
       will just retain the same value). Create service date from these minimum date values.
       Take MAX of all SUD condition indicators.;
	execute (
		create temp table &fltype._rollup as 

		select submtg_state_cd,
		       &fltype._link_key,
			   msis_ident_num
			   /* Take the minimum of all RULE values across the lines, then create one
			      value at the header level across those minimums */

			   %do r=1 %to %sysfunc(countw(&rules.));
			   	  %let rule=%scan(&rules.,&r.);
				  ,min(&rule.) as &rule.
				%end;

				,least(%do r=1 %to %sysfunc(countw(&rules.));
			   	        %let rule=%scan(&rules.,&r.);
						%if &r. > 1 %then %do; , %end;
						min(&rule.)
					  %end; ) as SUD_TOOL_RULE_HDR
				/* Take the minimum of all date values, then create srvc_dt as the first non-null of those */
				%do d=1 %to %sysfunc(countw(&dates.));
			   	  %let date=%scan(&dates.,&d.);
				  ,min(&date.) as &date.
				%end;

				,case %do d=1 %to %sysfunc(countw(&dates.));
			   	         %let date=%scan(&dates.,&d.);
							 when min(&date.) is not null then min(&date.)
						  %end;
					 end as srvc_dt

				/* Take the maximum of all condition-specific indicators. */

				%do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,max(&ind._SUD_DSRDR) as &ind._SUD_DSRDR
				%end;

				/* Create condition-specific rules - when the condition is identified, set the rule to the HDR rule from above */

				%do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,case when max(&ind._SUD_DSRDR) = 1 then SUD_TOOL_RULE_HDR
				         else null
						 end as &ind._SUD_RULE
				%end;

		from &fltype._&tbl.
		group by submtg_state_cd,
		         &fltype._link_key,
				 msis_ident_num

	) by tmsis_passthrough;

	
	 ** Finally roll up again across claims with same service date values;

	execute (
		create temp table &fltype._rollup2 as
		select submtg_state_cd,
		       msis_ident_num,
			   srvc_dt,
			   min(SUD_TOOL_RULE_HDR) as SUD_TOOL_RULE_HDR
			   %do s=1 %to %sysfunc(countw(&indicators.));
			       %let ind=%scan(&indicators.,&s.);
				   ,max(&ind._SUD_DSRDR) as &ind._SUD_DSRDR
				%end;
				%do s=1 %to %sysfunc(countw(&indicators.));
			       	%let ind=%scan(&indicators.,&s.);
					,min(&ind._SUD_RULE) as &ind._SUD_RULE
				%end;

		from &fltype._rollup
		group by submtg_state_cd,
		         msis_ident_num,
				 srvc_dt

	) by tmsis_passthrough;

%mend rollup;


%macro rollup_dgns_only(fltype, tbl=, rules=, dates=);

	** Roll up the line-level file to the header (using tables from diagnosis only method):
       Take the minimum of all dates - note some dates are at the header-level, but can still take minimum (this
       will just retain the same value). Create service date from these minimum date values.
       Subset to SUD_DGNS=1.

      For OT we will need to subset to POS != 21, 51.

       Take MAX of all SUD condition indicators.;

	execute (
		create temp table &fltype._rollup_dgns as 

		select * from (
           select submtg_state_cd,
		          &fltype._link_key,
			      msis_ident_num

				  /* Take the minimum of all date values, then create srvc_dt as the first non-null of those */

				  %do d=1 %to %sysfunc(countw(&dates.));
			   	    %let date=%scan(&dates.,&d.);
				    ,min(&date.) as &date.
				  %end;

			  	  ,case %do d=1 %to %sysfunc(countw(&dates.));
			   	           %let date=%scan(&dates.,&d.);
						  	 when min(&date.) is not null then min(&date.)
						    %end;
					   end as srvc_dt

				  /* Take the maximum of all condition-specific indicators */

				  %do s=1 %to %sysfunc(countw(&indicators.));
			         %let ind=%scan(&indicators.,&s.);
				     ,max(&ind._SUD_DSRDR_DGNS) as &ind._SUD_DSRDR_DGNS
				  %end;

				  %if &fltype. = OT %then %do;
				  	 ,max(srvc_plc_cd) as srvc_plc_cd
				  %end;

		  from &fltype.&tbl.
		  where SUD_DGNS=1 
                %if "&fltype." = "LT" %then %do; and inpat=0 %end; 

		  group by submtg_state_cd,
		           &fltype._link_key,
			  	   msis_ident_num )

		%if &fltype. = OT %then %do;
			where srvc_plc_cd is null or srvc_plc_cd not in ('21','51')	
		%end;

  	) by tmsis_passthrough;

%mend rollup_dgns_only;

%macro sud_inp_nodx(fltype,nproc=);

	** Take the IP/OT file with all lab/transport-only records dropped, and join to lookup tables
       of SUD-specific procedure/rev codes.
       For procedure codes, create indicator for whether marked as OUD;

	execute (
		create temp table &fltype._inp_sud_nodx as
		select submtg_state_cd,
		       msis_ident_num,
			   &fltype._link_key,
			   CLAIM_MC,
			   CLAIM_FFS
			   %if &fltype. = OT %then %do;
			    	,srvc_plc_cd
			   %end;
			   %do p=1 %to &nproc.;
				   	,prcdr_&p._cd 
	                ,case when p&p..prcdr_cd is not null 
					      then 1 else 0
						  end as prcdr_&p._cd_sud
					,case when p&p..OUD = 'OUD'
                          then 1 else 0
						  end as prcdr_&p._cd_OUD
				%end;
				,a.rev_cd
				,case when r.rev_cd is not null
					  then 1 else 0
					  end as rev_cd_sud

				,case when rev_cd_sud=1 %do p=1 %to &nproc.; or prcdr_&p._cd_sud=1 %end;
				      then 1 else 0
					  end as INP_SUD

				,case when %do p=1 %to &nproc.; %if &p. > 1 %then %do; or %end; prcdr_&p._cd_OUD=1 %end;
				      then 1 else 0
					  end as INP_OUD

		from (select * from &fltype.HL_labt2 %if &fltype. = OT %then %do; where srvc_plc_cd in ('21','51') %end; ) a

			 %do p=1 %to &nproc.;
			 	  left join
			      codes_sud_prcdr_cd p&p.

				  on a.prcdr_&p._cd = p&p..prcdr_cd
			 %end;

			 left join 
			 codes_sud_rev_cd r

			 on a.rev_cd = r.rev_cd

	) by tmsis_passthrough;

%mend sud_inp_nodx;

%macro sud_outp_nodx(fltype, tbl=, dates=);

	** Join the LT/OT files to the tables of SUD-specific procedure/rev/POS codes;

	execute (
		create temp table &fltype._outp_sud_nodx as
		select submtg_state_cd,
		       msis_ident_num,
			   &fltype._link_key,
			   CLAIM_MC,
			   CLAIM_FFS,
			   a.rev_cd
			   %do d=1 %to %sysfunc(countw(&dates.));
			   	    %let date=%scan(&dates.,&d.);
					,&date.
				%end;

			   ,case when r.rev_cd is not null
			        then 1 else 0
					end as rev_cd_sud

				%if &fltype.=OT %then %do;
					,bill_type_cd_lkup

					,a.srvc_plc_cd
					,case when s.srvc_plc_cd is not null
						 then 1 else 0
						 end as srvc_plc_cd_sud

					,prcdr_1_cd
					,prcdr_2_cd
					,case when p.prcdr_cd is not null or p2.prcdr_cd is not null
						  then 1 else 0
						  end as prcdr_cd_sud

					,case when p.OUD = 'OUD' or p2.OUD = 'OUD'
                          then 1 else 0
						  end as OUTP_OUD
				%end;
				%else %do;
				    ,0 as srvc_plc_cd_sud
					,0 as prcdr_cd_sud
					,0 as OUTP_OUD
				%end;

				,case when rev_cd_sud=1 or srvc_plc_cd_sud=1 or prcdr_cd_sud=1
				      then 1 else 0
					  end as OUTP_SUD

		from %if &fltype.=OT %then %do; (select * from &fltype.&tbl. where srvc_plc_cd is null or srvc_plc_cd not in ('21','51') ) %end;
             %else %do; &fltype.&tbl. %end; a

		     left join
			 codes_sud_rev_cd r
			 on a.rev_cd = r.rev_cd

			 %if &fltype.=OT %then %do;

				 left join
				 codes_sud_srvc_plc_cd s
				 on a.srvc_plc_cd = s.srvc_plc_cd

				left join
				codes_sud_prcdr_cd p
				on a.prcdr_1_cd = p.prcdr_cd

				left join
				codes_sud_prcdr_cd p2
				on a.prcdr_2_cd = p2.prcdr_cd

			%end;

	) by tmsis_passthrough;

	** Now must rollup to the header-level to get one service date on each claim, and take MAX
	   of OUTP_SUD and OUTP_OUD;

	execute (
		create temp table &fltype._outp_sud_nodx2 as 

		select * from (
           select submtg_state_cd,
		          &fltype._link_key,
			      msis_ident_num

				  /* Take the minimum of all date values, then create srvc_dt as the first non-null of those */

				  %do d=1 %to %sysfunc(countw(&dates.));
			   	    %let date=%scan(&dates.,&d.);
				    ,min(&date.) as &date.
				  %end;

			  	  ,case %do d=1 %to %sysfunc(countw(&dates.));
			   	           %let date=%scan(&dates.,&d.);
						  	 when min(&date.) is not null then min(&date.)
						    %end;
					   end as srvc_dt

				  /* Take the maximum of OUTP_SUD and OUTP_OUD */

				  ,max(OUTP_SUD) as OUTP_SUD
				  ,max(OUTP_OUD) as OUTP_OUD 

		  from &fltype._outp_sud_nodx

		  group by submtg_state_cd,
		           &fltype._link_key,
			  	   msis_ident_num )

		where OUTP_SUD=1


  	) by tmsis_passthrough;

%mend sud_outp_nodx;

%macro unique_sud_claims(fltype, t2=, t2ind=, t3=, t3ind=);

	** The inner query unions the up to 3 tables of SUD claims for the given claim type. The outer query
	   deduplicates over those by making a unique table of link_key values;

	execute (
		create temp table &fltype._sud_unq_claims as

		select distinct submtg_state_cd,
		                msis_ident_num,
						&fltype._link_key,
						CLAIM_MC,
						CLAIM_FFS

		from ( select submtg_state_cd,
		              msis_ident_num,
					  &fltype._link_key,
					  CLAIM_MC,
					  CLAIM_FFS

				from &fltype._sud

				%if &t2. ne  %then %do;

					union all 

					 select submtg_state_cd,
			                msis_ident_num,
						    &fltype._link_key,
						    CLAIM_MC,
						    CLAIM_FFS

					 from &fltype._&t2.
					 where &t2ind.=1

				%end;

				%if &t3. ne  %then %do;

					union all 

					 select submtg_state_cd,
			                msis_ident_num,
						    &fltype._link_key,
						    CLAIM_MC,
						    CLAIM_FFS
					 from &fltype._&t3.
					 where &t3ind.=1
				%end;

			)

	) by tmsis_passthrough;

%mend unique_sud_claims;

%macro pull_sud_claims(fltype);
	** Join unique SUD link_keys back to raw lines to pull all SUD claims with raw cols to be
       able to assign to setting/service types.
       NOTE now that we are counting services, we will drop denied lines.
       In an outer query, only keep claims for benes who are in our SUD population;

	execute (
		create temp table &fltype._SUD_FULL as
		select a.*
		from (
				select b.*

				from &fltype._sud_unq_claims a
				     inner join
					 &fltype.HL b

				on a.submtg_state_cd = b.submtg_state_cd and
				   a.msis_ident_num = b.msis_ident_num and
				   a.&fltype._link_key = b.&fltype._link_key

				where CLL_STUS_CD not in ('542','585','654') or CLL_STUS_CD is null 
              ) a

			inner join
			population_sud b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.msis_ident_num = b.msis_ident_num


	) by tmsis_passthrough;


%mend pull_sud_claims;

%macro crosswalk_service_type(fltype, nprocs=0, setting=, dates=);

	** Pull in all SUD claims to crosswalk to service types;

	execute (
		create temp table &fltype._SUD_SRVC as
		select a.*,
		       b.SERVICE_TYPE as SERVICE_TYPE_NDC,
			   case when b.MAT_MED_CAT is not null and b.MAT_MED_CAT != '' then b.MAT_MED_CAT
                    else null
                    end as MAT_MED_CAT_NDC,
			   case when SERVICE_TYPE_NDC is not null
			        then 1 else 0
					end as NDC_HAS_SERVICE,
			   case when MAT_MED_CAT_NDC is not null
			        then 1 else 0
					end as NDC_HAS_MAT

			   %if &nprocs.>0 %then %do p=1 %to &nprocs.;
			   	   ,p&p..SERVICE_TYPE as SERVICE_TYPE_PRCDR&p.
			       ,case when p&p..MAT_MED_CAT is not null and p&p..MAT_MED_CAT != '' then p&p..MAT_MED_CAT
                         else null
                         end as MAT_MED_CAT_PRCDR&p.
				   ,case when SERVICE_TYPE_PRCDR&p. is not null
				   	     then 1 else 0
						 end as PRCDR&p._HAS_SERVICE
					,case when MAT_MED_CAT_PRCDR&p. is not null and MAT_MED_CAT_PRCDR&p. != ''
				   	     then 1 else 0
						 end as PRCDR&p._HAS_MAT
			   %end;

			   %if &fltype. ne RX %then %do;
			   	   ,r.SERVICE_TYPE as SERVICE_TYPE_REV
				   ,case when SERVICE_TYPE_REV is not null
				   	     then 1 else 0
						 end as REV_HAS_SERVICE
				%end;

			   /* Now must take service type word values and convert to indicators -
			      look across all word values (NDC and procedures if exist).
				  Do for regular service types and for MAT medication categories */

			   %do t=1 %to %sysfunc(countw(&service_types.,'#'));
			   	  %let type=%scan(&service_types.,&t.,'#');
				  %let ind=%scan(&service_inds.,&t.,'#');

				  ,case when SERVICE_TYPE_NDC = %nrbquote('&type.')
			             %if &nprocs.>0 %then %do p=1 %to &nprocs.;
						 	or SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
						  %end;

				        then 1 else 0
						end as TRT_SRVC_&ind._P

				%end;

				%do m=1 %to %sysfunc(countw(&mat_meds.,'#'));
			   	  %let med=%scan(&mat_meds.,&m.,'#');

				  ,case when MAT_MED_CAT_NDC = %nrbquote('&med.')
			             %if &nprocs.>0 %then %do p=1 %to &nprocs.;
						 	or MAT_MED_CAT_PRCDR&p. = %nrbquote('&med.') 
						  %end;

				        then 1 else 0
						end as MAT_&med.

				%end;

				/* Sum the total number of service indicators set - will then sum across all lines and if > 0, will use these.
				   If = 0, will use the values created below for the rev codes. */

				,%do t=1 %to %sysfunc(countw(&service_types.,'#'));
				    %let ind=%scan(&service_inds.,&t.,'#');
					%if &t. > 1 %then %do; + %end;
					TRT_SRVC_&ind._P
				 %end; 
					 as TRT_SRVC_TOT_P


				/* Do the same thing for REV code - note we must keep these separate because we will only
				   use the REV code values if NONE of the procedure or NDC codes mapped (sum of all above TRT_SRVC indicators =0 for the claim) */

				%if &fltype. ne RX %then %do;

					%do t=1 %to %sysfunc(countw(&service_types.,'#'));
				   	  %let type=%scan(&service_types.,&t.,'#');
					  %let ind=%scan(&service_inds.,&t.,'#');

					  ,case when SERVICE_TYPE_REV = %nrbquote('&type.')

					        then 1 else 0
							end as TRT_SRVC_&ind._R

					%end;

					,%do t=1 %to %sysfunc(countw(&service_types.,'#'));
					    %let ind=%scan(&service_inds.,&t.,'#');
						%if &t. > 1 %then %do; + %end;
							TRT_SRVC_&ind._R
					 %end; 
						 as TRT_SRVC_TOT_R

				%end;

				%if &setting. ne  %then %do;
					,%nrbquote('&setting') as SETTING
				%end;

				%if "&fltype." = "LT" %then %do;
					,case when rev_cd in (&inpat_psych_rev.) then 1 else 0 end as rev_cd_inpat
				%end;

		from &fltype._SUD_FULL a

			 left join
			 (select * from codes_services where TYPE='NDC') b
			 on a.ndc_cd = b.CODE

			%if &nprocs.>0 %then %do p=1 %to &nprocs.;
					  	
			  	 left join
				  (select * from codes_services where TYPE='PRCDR') p&p.
				  on a.prcdr_&p._cd = p&p..CODE

			 %end;

			 %if &fltype. ne RX %then %do;

			  	 left join
				 (select * from codes_services where TYPE='REV') r
				 on a.rev_cd = r.CODE

			  %end;


	) by tmsis_passthrough;

	%if "&fltype." = "LT" %then %do;

		title "Freq of rev_cds on LT lines identified as inpatient psych";

		%crosstab(&fltype._SUD_SRVC, rev_cd rev_cd_inpat, wherestmt=%str(where rev_cd_inpat=1))

	%end;


	** Roll up to the header-level, taking the MAX of all indicators,
	   and creating the needed date vars to calculate one service date for the entire claim.
	   Take the sum of TRT_SRVC_TOT_P and TRT_SRVC_TOT_R - if TRT_SRVC_TOT_P > 0 (procedure/NDC codes mapped to services),
	   then use the _P indicators.
	   if TRT_SRVC_TOT_P =0, use the _R indicators;

	execute (
		create temp table &fltype._SUD_SRVC_ROLLUP as 

		select submtg_state_cd,
		       msis_ident_num,
		       &fltype._link_key

				/* Take the minimum of all date values, and create srvc_dt as the first non-null of those */

				,case %do d=1 %to %sysfunc(countw(&dates.));
			   	         %let date=%scan(&dates.,&d.);
							 when min(&date.) is not null then min(&date.)
						  %end;
				 end as srvc_dt

				/* Take the maximum of all indicators and total values */

				%if &fltype. ne RX %then %do;

					,sum(TRT_SRVC_TOT_P) as TRT_SRVC_TOT_P
					,sum(TRT_SRVC_TOT_R) as TRT_SRVC_TOT_R

					%do t=1 %to %sysfunc(countw(&service_inds.,'#'));
						%let ind=%scan(&service_inds.,&t.,'#');

					   ,case when sum(TRT_SRVC_TOT_P)>0 then max(TRT_SRVC_&ind._P) 
                              when sum(TRT_SRVC_TOT_R)>0 then max(TRT_SRVC_&ind._R)

                              else 0 
                              end as TRT_SRVC_&ind.
					%end;

				%end;

				%if &fltype. = RX %then %do;

					,sum(TRT_SRVC_TOT_P) as TRT_SRVC_TOT_P
					,0 as TRT_SRVC_TOT_R

					%do t=1 %to %sysfunc(countw(&service_inds.,'#'));
						%let ind=%scan(&service_inds.,&t.,'#');

					   ,max(TRT_SRVC_&ind._P) as TRT_SRVC_&ind.

					%end;

				%end;

				/* Take max of all MAT med indicators (all file types) */

				%do m=1 %to %sysfunc(countw(&mat_meds.,'#'));
			   	    %let med=%scan(&mat_meds.,&m.,'#');
					,max(MAT_&med.) as MAT_&med.
				%end;

				/* For IP, also take the min service begin date and max service end date. Will use when join this
				   rolled-up claims table back to the raw lines when counting service days.
				   For the other file types we will just set to null because must union all file types and must have
				   same cols */

				%if &fltype. = IP %then %do;

					,min(srvc_bgnng_dt_line) as srvc_bgnng_dt_line_min
					,max(srvc_endg_dt_line) as srvc_endg_dt_line_max

				%end;

				%if &fltype. ne IP %then %do;

					,null :: date as srvc_bgnng_dt_line_min
					,null :: date as srvc_endg_dt_line_max

				%end;

				%if &setting. ne  %then %do;
				   ,max(SETTING) as SETTING
				%end;

				%if "&fltype." = "LT" %then %do;
					,case when max(rev_cd_inpat)=1 then 'Inpatient' else 'Residential'
						end as SETTING
				%end;


		from &fltype._SUD_SRVC
		group by submtg_state_cd,
		         msis_ident_num,
		         &fltype._link_key

	) by tmsis_passthrough;


	** For OT only, must join on Setting created above. Delete the first three bytes (which is just the number,
	   but is not needed anymore);

	%if &fltype. = OT %then %do;

		execute (
			create temp table &fltype._SUD_SRVC_ROLLUP2 as
			select a.*,
			       substring(b.SETTING,4) as SETTING

			from &fltype._SUD_SRVC_ROLLUP a
			     full join 
				 &fltype._SUD_SETTING_ROLLUP b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.msis_ident_num = b.msis_ident_num and
			   a.&fltype._link_key = b.&fltype._link_key

		) by tmsis_passthrough;


	%end;

%mend crosswalk_service_type;

%macro service_type_days(fltype, nprocs=0,
                         bdate1=, bdate2=, edate1=, edate2=,
						 bdate1_p=, bdate2_p=, edate1_p=, edate2_p=);

	%if &fltype.=RX %then %do;

		execute (
			create temp table &fltype._SUD_SRVC_DAYS as
			select *

			  	/* Assign RX begin and end dates based on rx_fill_dt and suply_days_cnt. Must do for services where we count days, AND
			       for all MAT medication categories */

				   %do t=1 %to %sysfunc(countw(&services_count_days_types.,'#'));
				   	  %let type=%scan(&services_count_days_types.,&t.,'#');
					  %let ind=%scan(&services_count_days.,&t.,'#');

					  ,case when SERVICE_TYPE_NDC = %nrbquote('&type.') 
					        then rx_fill_dt 
							else null
							end as bdt_ndc_&ind.

					 ,case when SERVICE_TYPE_NDC = %nrbquote('&type.') and suply_days_cnt > 0 and suply_days_cnt <= 120
					        then (dateadd(day,suply_days_cnt,rx_fill_dt)-1) :: date 
							else null
							end as edt_ndc_&ind.

					%end;

			from &fltype._SUD_SRVC

		) by tmsis_passthrough;

	%end; ** end RX loop;

	** For the other three file types, must join the count of services identified through PROC/NDC vs REV back on, so that we only
	   use the REV dates if there were 0 PROC/NDC services;

	%if &fltype. ne RX %then %do;

		execute (
			create temp table &fltype._SUD_SRVC_DAYS as
			select a.*,
			       b.TRT_SRVC_TOT_P as TRT_SRVC_TOT_P_CLM, 
				   b.TRT_SRVC_TOT_R as TRT_SRVC_TOT_R_CLM

				   /* For IP only, must bring min service begin date and max service ending date across lines back on 
				      (used in date assignment if admission or discharge dates are missing) */

				   %if &fltype. = IP %then %do;

					   ,b.srvc_bgnng_dt_line_min
					   ,b.srvc_endg_dt_line_max

				   %end;

			  	/* Look at both NDC and REV codes and assign dates using primary and secondary rules -
				   use REV code only if TRT_SRVC_TOT_P=0 */

				   %do t=1 %to %sysfunc(countw(&services_count_days_types.,'#'));
				   	  %let type=%scan(&services_count_days_types.,&t.,'#');
					  %let ind=%scan(&services_count_days.,&t.,'#');

					  ,case when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &bdate1. is not null) or
					             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &bdate1. is not null)
					        then &bdate1. 

							when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &bdate2. is not null) or
					             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &bdate2. is not null)
					        then &bdate2.
 
							else null
							end as bdt_ndc_&ind.

						/* Edit for MAT to hard code dats */

						%if &ind. ne MAT %then %do;

						 ,case when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &edate1. is not null) or
						             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &edate1. is not null)
						        then &edate1. 

								when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &edate2. is not null) or
						             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &edate2. is not null)
						        then &edate2.
	 
								else null
								end as edt_ndc_&ind.

						 %end;

						 %if &ind. = MAT %then %do;

						 ,case when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &edate1. is not null and
                                     ndc_cd not in (&ndc30.) and ndc_cd not in (&ndc77.) and ndc_cd not in (&ndc180.)) or
						             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &edate1. is not null)
						        then &edate1. 

								when (SERVICE_TYPE_NDC = %nrbquote('&type.') and &edate2. is not null and
                                     ndc_cd not in (&ndc30.) and ndc_cd not in (&ndc77.) and ndc_cd not in (&ndc180.)) or
						             (TRT_SRVC_TOT_P_CLM=0 and SERVICE_TYPE_REV = %nrbquote('&type.') and &edate2. is not null)
						        then &edate2.

								when SERVICE_TYPE_NDC = %nrbquote('&type.') and ndc_cd in (&ndc30.)
								then (dateadd(day,30,bdt_ndc_&ind.)-1) :: date 

								when SERVICE_TYPE_NDC = %nrbquote('&type.') and ndc_cd in (&ndc77.)
								then (dateadd(day,77,bdt_ndc_&ind.)-1) :: date 

								when SERVICE_TYPE_NDC = %nrbquote('&type.') and ndc_cd in (&ndc180.)
								then (dateadd(day,180,bdt_ndc_&ind.)-1) :: date 

								else null
								end as edt_ndc_&ind.


						 %end;


					%end;

				/* Now for OT and IP only, also look at procedure codes */

					%if &nprocs. > 0 %then %do t=1 %to %sysfunc(countw(&services_count_days_types.,'#'));
				   	    %let type=%scan(&services_count_days_types.,&t.,'#');
					    %let ind=%scan(&services_count_days.,&t.,'#');

						,case when (%do p=1 %to &nprocs.;
							         %if &p. > 1 %then %do; or %end;
							 	     SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
								  %end; ) 
								  and &bdate1_p. is not null
							  then &bdate1_p.

							  when (%do p=1 %to &nprocs.;
							         %if &p. > 1 %then %do; or %end;
							 	     SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
								  %end; ) 
								  and &bdate2_p. is not null
							  then &bdate2_p.
							  else null
							  end as bdt_proc_&ind.

						/* Edit for MAT to hard code dats */

						%if &ind. ne MAT %then %do;

							,case when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	     SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
									  %end; ) 
									  and &edate1_p. is not null
								  then &edate1_p.

								  when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	      SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
									  %end; ) 
									  and &edate2_p. is not null
								  then &edate2_p.
								  else null
								  end as edt_proc_&ind.

						%end;

						%if &ind. = MAT %then %do;
							/* identify whether any MAT and NOT 30/180, MAT 30, MAT 180 - create end date */
							,case when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	     (SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
                                              and prcdr_&p._cd not in (&proc30.) and prcdr_&p._cd not in (&proc180.))
									  %end; ) 
									and &edate1_p. is not null
								    then &edate1_p.

									when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	     (SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
                                              and prcdr_&p._cd not in (&proc30.) and prcdr_&p._cd not in (&proc180.))
									  %end; ) 
									and &edate2_p. is not null
								    then &edate2_p.

									else null
									end as edt_proc_&ind._orig 

							/* identify whether any MAT 30 - create end date */

							,case when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	     (SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
                                              and prcdr_&p._cd in (&proc30.) )
									  %end; ) 
									then (dateadd(day,30,bdt_ndc_&ind.)-1) :: date 
									else null
									end as edt_proc_&ind._30

							/* identify whether any MAT 180 - create end date */

							,case when (%do p=1 %to &nprocs.;
								         %if &p. > 1 %then %do; or %end;
								 	     (SERVICE_TYPE_PRCDR&p. = %nrbquote('&type.') 
                                              and prcdr_&p._cd in (&proc180.) )
									  %end; ) 
									then (dateadd(day,180,bdt_ndc_&ind.)-1) :: date 
									else null
									end as edt_proc_&ind._180

							/* now must take MAX across all three dates to be final end date for header/line for MAT */

							,greatest(edt_proc_&ind._orig, edt_proc_&ind._30, edt_proc_&ind._180) as edt_proc_&ind.					


						%end;

					%end;

			from &fltype._SUD_SRVC a 
			     inner join
				 &fltype._SUD_SRVC_ROLLUP b
			on a.submtg_state_cd = b.submtg_state_cd and 
			   a.msis_ident_num = b.msis_ident_num and
			   a.&fltype._link_key = b.&fltype._link_key

		) by tmsis_passthrough;


	%end; ** end ne RX loop;

	** Now for all file types, must create daily indicators for each service type and MAT med type based on begin and end dates. 
	   For IP and OT, must look at both ndc dates and proc dates. For RX and LT, only need to look at NDC dates.
	   Loop through service types/MAT med types and create separate tables for each type;

	%do t=1 %to %sysfunc(countw(&services_count_days. ,'#'));
		%let ind=%scan(&services_count_days. ,&t.,'#');

		%let num=0;

		execute (
			create temp table &fltype._SUD_SRVC_&ind. as 
			select submtg_state_cd,
	               msis_ident_num
				  ,bdt_ndc_&ind.
				  ,edt_ndc_&ind.

				  %if &nprocs. > 0 %then %do;
					  ,bdt_proc_&ind.
					  ,edt_proc_&ind.
				  %end;

				  %if &nprocs. = 0 %then %do;
					  ,null :: date as bdt_proc_&ind.
					  ,null :: date edt_proc_&ind.
				  %end;

				  %do month=1 %to 12;

					%if %sysfunc(length(&month.))=1 %then %let month=0&month.;
					%if &month. in (01 03 05 07 08 10 12) %then %let lday=31;
					%if &month. in (04 06 09 11) %then %let lday=30;
					%if &month. = 02 and &leap.=0 %then %let lday=28;
					%if &month. = 02 and &leap.=1 %then %let lday=29;

					%do day=1 %to &lday.;
						%if %sysfunc(length(&day.))=1 %then %let day=0&day.;

						%let num=%eval(&num.+1);

						,case when (date_cmp(bdt_ndc_&ind.,%nrbquote('&year.-&month.-&day.')) in (-1,0) and
					               date_cmp(edt_ndc_&ind.,%nrbquote('&year.-&month.-&day.')) in (0,1) )
								   %if &nprocs. > 0 %then %do;
								   	   or (date_cmp(bdt_proc_&ind.,%nrbquote('&year.-&month.-&day.')) in (-1,0) and
					                       date_cmp(edt_proc_&ind.,%nrbquote('&year.-&month.-&day.')) in (0,1) )
								   %end;
	                          then 1 else 0 
			                  end as &ind._day&num.

					%end;

				%end; 

			from &fltype._SUD_SRVC_DAYS

			/* Subset to records where there is at least one non-null begin/end date for the service type (NDC or proc) */

			where (bdt_ndc_&ind. is not null and edt_ndc_&ind. is not null)
					  %if &nprocs. > 0 %then %do;
					  	 or (bdt_proc_&ind. is not null and edt_proc_&ind. is not null)
					  %end;

		) by tmsis_passthrough;

	%end;
	
%mend service_type_days;

%macro inp_res_dates(indates);

	** Do a many-to-many join of the inpatient/residential bene/dates file to the 
       outpatient or home/community bene/dates file;

	execute (
		create temp table INP_RES_&indates. as
		select a.submtg_state_cd,
		       a.msis_ident_num,
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
			 OT_&indates._DATES b

		on a.submtg_state_cd = b.submtg_state_cd and
		   a.msis_ident_num = b.msis_ident_num


	) by tmsis_passthrough;


	 ** Now roll up to the bene-level, taking the max of SERVICE30;

	 execute (
	 	create temp table INP_RES_&indates._BENE as
		select submtg_state_cd,
		       msis_ident_num,
			   max(SERVICE30) as ANY_SERVICE30

		from INP_RES_&indates.
		group by submtg_state_cd,
		         msis_ident_num


	 ) by tmsis_passthrough;

	 ** Output stratified and national counts of ANY_SERVICE30;

	create table sasout.state_sud_&indates._30 as select * from connection to tmsis_passthrough
		(select submtg_state_cd,
		        count(*) as nbenes,
				sum(ANY_SERVICE30) as ANY_SERVICE30

		from INP_RES_&indates._BENE
		group by submtg_state_cd );

%mend inp_res_dates;


/* Macro frequency_strat to run stratified frequencies 
      ds=input dataset
      col=col to run frequency on
	  type=num or char, default is num
      stratcol=col to stratify by (default is state)
      outfile=optional name of SAS output dataset (if not specified will just print to lst file) 
      stratcol2=additional col to stratify by
      stratcol3=additional col to stratify by*/
%macro frequency_strat(ds,col,type=num,stratcol=submtg_state_cd,wherestmt=,outfile=,stratcol2=);

%if &outfile. ne  %then %do; create table &outfile. as %end;
	select * from connection to tmsis_passthrough (

		select a.&col.,
               a.&stratcol.,
			   %if &stratcol2. ne  %then %do;
			   	 a.&stratcol2.,
			   %end;
			   %if &type.=num %then %do;
		           count(coalesce(a.&col.,9)) as count,
				   100.0*(count(coalesce(a.&col.,9)) / b.totcount) as pct
				%end;
				%if &type.=char %then %do;
	 				count(coalesce(a.&col.,'XXX')) as count,
				   100.0*(count(coalesce(a.&col.,'XXX')) / b.totcount) as pct
				%end;
				

		from (select * from &ds. &wherestmt.) a
		      inner join
			 (select &stratcol.,  %if &stratcol2. ne  %then %do; &stratcol2., %end;
                      count(*) as totcount from &ds. &wherestmt.
                      group by &stratcol. %if &stratcol2. ne  %then %do; ,&stratcol2. %end; ) b
			 on a.&stratcol. = b.&stratcol.
			 %if &stratcol2. ne  %then %do; and a.&stratcol2. = b.&stratcol2. %end;

		group by a.&stratcol.,
			 	 %if &stratcol2. ne  %then %do; 
				    a.&stratcol2.,
				 %end;
		         a.&col.,
                 b.totcount

		order by a.&stratcol.,
		         %if &stratcol2. ne  %then %do; 
				     a.&stratcol2.,
				 %end;
                 a.&col. );


%mend frequency_strat;
/* Macro crosstab to run crosstab (with percents) - assumes numeric input
   Macro parms:
      ds=input dataset
      col=col to run frequency on
      wherestmt=optional subset where statement
      outfile=optional name of SAS output dataset (if not specified will just print to lst file) */

%macro crosstab(ds,cols,wherestmt=,outfile=);

	%if &outfile. ne  %then %do; create table &outfile. as %end;
	select * from connection to tmsis_passthrough (

		select %do i=1 %to %sysfunc(countw(&cols.));
				    %let col=%scan(&cols.,&i.);
					&col.,
                  %end;
				  sum(1) as count

              from &ds. &wherestmt.
              group by %do i=1 %to %sysfunc(countw(&cols.));
				    	   %let col=%scan(&cols.,&i.);
			         	   %if &i. > 1 %then %do; , %end; &col.
                       %end;
			order by %do i=1 %to %sysfunc(countw(&cols.));
				    %let col=%scan(&cols.,&i.);
			         %if &i. > 1 %then %do; , %end; &col.
                  %end; );


%mend crosstab;
