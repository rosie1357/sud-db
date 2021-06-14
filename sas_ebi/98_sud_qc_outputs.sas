/**********************************************************************************************/
/*Program: 98_sud_qc_outputs
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to create output Excel with QC outputs
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro SUD_QC_OUTPUTS;

	** Create dummy state dataset to merge onto output to include state abbrev;

	data stdummy (drop=i);
		do i = 1 to 56;	
			state = fipstate(i);
		 	submtg_state_cd = put(i,z2.);
			if state > 'AA' then output;
		end;
		** Add PR and US;
		submtg_state_cd='72';
		state='PR';
		output;

		submtg_state_cd='00';
		state='US';
		output;

	run;

	proc sort data=stdummy;
		by submtg_state_cd;
	run;

	data sud_methods;
		set sasout.national_sud_methods (in=a)
		    sasout.state_sud_methods;
		if a then submtg_state_cd='00';
	run;

	proc sort data=sud_methods;
		by submtg_state_cd;
	run;

	data sud_methods;
		merge sud_methods
		      stdummy;
		by submtg_state_cd;
	run;

	** Also read in state-level attrition counts, and sum to get national;

	proc summary data=sasout.state_attrition nway;
		var TOT ENROLLED ENROLLED_FULL ENROLLED_FULL_AGE ENROLLED_FULL_AGE_NO6;
		output out=national_attrition sum=;
	run;

	proc sort data=sasout.state_attrition out=state_attrition;
		by submtg_state_cd;
	run;

	data attrition;
		set national_attrition (in=a)
            state_attrition;

		if a then submtg_state_cd='00';
	run;

	data attrition;
		merge stdummy
		      attrition;
		by submtg_state_cd;
	run;


	** Output to Excel;

	options device=ACTXIMG;
		ods excel file="&basedir./Excel/QC_SUD_DB_Initial_Counts_&sysdate..xlsx" style=statistical
		options(sheet_name="1: Bene Counts" sheet_interval='table' index='yes' embedded_titles='yes');

		title1 "TAF &year.:";
		title2 "US- and State-Level Counts of Benes in Population and with an SUD via Any/Each of the Three Methods";

		proc print data=sud_methods noobs label;
			var state POP_TOT POP_SUD_TOT POP_SUD_TOOL1_TOT POP_SUD_DX_ONLY_TOT POP_SUD_NODX_TOT;
			format POP: comma15.;
			label state = 'State'
			      POP_TOT = '# of Benes in Population'
			      POP_SUD_TOT = '# of Benes with an SUD (Any Method)'
                  POP_SUD_TOOL1_TOT = '# of Benes (Tool 1)'
                  POP_SUD_DX_ONLY_TOT = '# of Benes (DX Only)'
                  POP_SUD_NODX_TOT = '# of Benes (No DX)';
		run;

		ods excel options(sheet_name="2: Bene Age (Tool 1)");

		title2 "US Frequency of Age for Benes with an SUD via Tool 1";

		proc print data=sasout.national_sud_tool1_age noobs label;
			var age count pct;
			format count comma15. pct 8.2;
			label age='Age'
			      count='Count'
				  pct='Percent';
		run;

		ods excel options(sheet_name="3: Bene Age (Any Method)");

		title2 "US Frequency of Age for Benes with an SUD via Any of the Three Methods";

		proc print data=sasout.national_sud_age noobs label;
			var age count pct;
			format count comma15. pct 8.2;
			label age='Age'
			      count='Count'
				  pct='Percent';
		run;

		ods excel options(sheet_name="4: Bene Method Overlap");

		title2 "US Bene Counts by Method (Crosstab)";

		proc print data=sasout.national_sud_crosstab noobs label;
			var POP_SUD_TOOL1 POP_SUD_DX_ONLY POP_SUD_NODX count pct;
			format count comma15.;
			label POP_SUD_TOOL1 = 'SUD: Tool 1'
			      POP_SUD_DX_ONLY = 'SUD: DX Only'
				  POP_SUD_NODX = 'SUD: No DX'
				  count='Count'
                  pct='Percent';

		run;

		ods excel options(sheet_name="5: Bene Attrition Counts");

		title2 "US- and State-Level Bene Attrition Counts";

		proc print data=attrition noobs label;
			var state TOT ENROLLED ENROLLED_FULL ENROLLED_FULL_AGE ENROLLED_FULL_AGE_NO6;
			format TOT ENROLLED: comma15.;

			label state = 'State'
			      TOT = "Total # Enrollees in DE &year."
                  ENROLLED = '# Enrolled in Medicaid 1+ Month'
                  ENROLLED_FULL = '# Enrolled in Medicaid 1+ Month with All Months of Full Benefits' 
                  ENROLLED_FULL_AGE = '# Enrolled in Medicaid 1+ Month with All Months of Full Benefits AND Age 12+'
                  ENROLLED_FULL_AGE_NO6 = '# Enrolled in Medicaid 1+ Month with All Months of Full Benefits AND Age 12+ AND Not Only CHIP EL Group Enrolled Months';

		run;

	ods excel close;

	** Create additional output Excel that shows N and % nulls for each file;

	%macro FORMAT_NULLS(fltype,vars);

		proc summary data=sasout.&fltype._nulls nway;
			var %do i=1 %to %sysfunc(countw(&vars.));
					%let var=%scan(&vars.,&i.);
					&var._null
				%end; nrecs ;
			output out=&fltype._null_us sum=;
		run;

		proc sort data=sasout.&fltype._nulls;
			by submtg_state_cd;
		run;

		data &fltype._nulls;
			set &fltype._null_us (in=a)
            sasout.&fltype._nulls;

			if a then submtg_state_cd='00';
		run;

		data &fltype._nulls;
			merge stdummy
			      &fltype._nulls;
			by submtg_state_cd;

			%do i=1 %to %sysfunc(countw(&vars.));
				%let var=%scan(&vars.,&i.);
					&var._pct = 100*(&var._null/nrecs);
			%end;
		run;

	%mend FORMAT_NULLS;

	%FORMAT_NULLS(DE, birth_dt rstrctd_bnfts_cd);
	%FORMAT_NULLS(IPH, admsn_dt dschrg_dt);
	%FORMAT_NULLS(IPL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%FORMAT_NULLS(LTH, admsn_dt dschrg_dt srvc_bgnng_dt srvc_endg_dt)
	%FORMAT_NULLS(LTL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%FORMAT_NULLS(OTH, srvc_plc_cd bill_type_cd bill_type_srvc_plc srvc_bgnng_dt srvc_endg_dt);
	%FORMAT_NULLS(OTL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%FORMAT_NULLS(RXH, rx_fill_dt);
	%FORMAT_NULLS(RXL, ndc_cd suply_days_cnt);

	%macro OUTPUT_NULLS(fltype,vars,first=0,last=0);

		%if &first.=1 %then %do;

			options device=ACTXIMG;
			ods excel file="&basedir./Excel/QC_SUD_DB_Count_Nulls_&sysdate..xlsx" style=statistical
			options(sheet_name="&fltype. Nulls" sheet_interval='table' index='yes' embedded_titles='yes');

		%end;

		%if &first.=0 %then %do;

			ods excel options(sheet_name="&fltype. Nulls");

		%end;

		title "Counts and Percents of Nulls: &fltype. (&year.)";
		%if &fltype. ne DE %then %do;
			title2 "(Medicaid and Unknown FFS/Encounter Claims Only";
		%end;
		%else %do;
			title2 "(Full DE Population)";
		%end;

		proc print data=&fltype._nulls noobs label;
			var state nrecs %do i=1 %to %sysfunc(countw(&vars.));
								%let var=%scan(&vars.,&i.);
									&var._null &var._pct 
							%end; ;
			label state = 'State'
			      nrecs = '# of Records'
				  %do i=1 %to %sysfunc(countw(&vars.));
					 %let var=%scan(&vars.,&i.);
					 &var._null = "&var.: # Null"
					 &var._pct = "&var.: % Null"
				  %end; ;

			format nrecs %do i=1 %to %sysfunc(countw(&vars.));
					 		 %let var=%scan(&vars.,&i.);
							 &var._null
						 %end; comma15. 
						 %do i=1 %to %sysfunc(countw(&vars.));
					 		 %let var=%scan(&vars.,&i.);
							 &var._pct
						 %end; 8.2 ;

		run;

		%if &last.=1 %then %do;
			ods excel close;
		%end;


	%mend OUTPUT_NULLS;

	%OUTPUT_NULLS(DE, birth_dt rstrctd_bnfts_cd,first=1);
	%OUTPUT_NULLS(IPH, admsn_dt dschrg_dt);
	%OUTPUT_NULLS(IPL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%OUTPUT_NULLS(LTH, admsn_dt dschrg_dt srvc_bgnng_dt srvc_endg_dt)
	%OUTPUT_NULLS(LTL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%OUTPUT_NULLS(OTH, srvc_plc_cd bill_type_cd bill_type_srvc_plc srvc_bgnng_dt srvc_endg_dt);
	%OUTPUT_NULLS(OTL, srvc_bgnng_dt_line srvc_endg_dt_line);
	%OUTPUT_NULLS(RXH, rx_fill_dt);
	%OUTPUT_NULLS(RXL, ndc_cd suply_days_cnt,last=1);

%mend SUD_QC_OUTPUTS;

%macro SUD_QC_SAMP_CLAIMS;

	** Mask MSIS IDs of sample claims and output to Excel;

	data ids;
		set sampbenes_ip_claims (keep=submtg_state_cd msis_ident_num bene_group)
		    sampbenes_lt_claims (keep=submtg_state_cd msis_ident_num bene_group)
			sampbenes_ot_claims (keep=submtg_state_cd msis_ident_num bene_group)
			sampbenes_rx_claims (keep=submtg_state_cd msis_ident_num bene_group);
	run;

	proc sort data=ids nodupkey;
		by bene_group submtg_state_cd msis_ident_num;
	run;

	data ids2;
		set ids;
		BENEID=_n_;
	run;

	%macro sampclaims(fltype);

		proc sort data=sampbenes_&fltype._claims;
			by bene_group submtg_state_cd msis_ident_num;
		run;
		
		data sampbenes_&fltype._claims2 (drop=msis_ident_num);
			length BENEID BENE_GROUP 8;
			merge ids2
	              sampbenes_&fltype._claims (in=a);
			by bene_group submtg_state_cd msis_ident_num;
			if a;
		run;

		%if &fltype.=IP %then %do;

			options device=ACTXIMG;
			ods excel file="&basedir./Excel/SUD_Sample_Claims_Prints_&sysdate..xlsx" style=statistical
			options(sheet_name="&fltype." sheet_interval='table' index='yes' embedded_titles='yes');

		%end;

		%else %do;

			ods excel options(sheet_name="&fltype.");

		%end;

		title "Print of all &fltype. claims";

		proc print data=sampbenes_&fltype._claims2 noobs;
		run;

		%if &fltype.=RX %then %do;
			ods excel close;
		%end;

	%mend sampclaims;

	%sampclaims(IP)
	%sampclaims(LT)
	%sampclaims(OT)
	%sampclaims(RX);


%mend SUD_QC_SAMP_CLAIMS;

%macro SUD_QC_OT_SETTING_TYPES;

	options device=ACTXIMG;
		ods excel file="&basedir./Excel/QC_OT_Setting_Service_Types_&sysdate..xlsx" style=statistical
		options(sheet_name="1a: Comm Emer Srvc Procs" sheet_interval='table' index='yes' embedded_titles='yes');

		title "Frequency of All Procedure Codes IDed as Emergency Services on Community Setting SUD Claims";

		proc print data=community_emer_services noobs;
		run;

		ods excel options(sheet_name="1b: Comm Emer Srvc Revs");

		title "Frequency of All Revenue Codes IDed as Emergency Services on Community Setting SUD Claims";

		proc print data=community_emer_services_r noobs;
		run;


		ods excel options(sheet_name="1c: Comm Emer Srvc Samp");

		title "Print of 100 Sample Claim Lines from Community Setting SUD Claims with Emergency Services";

		proc print data=community_emer_services_samp noobs;
		run;

		ods excel options(sheet_name="1d: Comm Procs Emer Srvc");

		title "Frequency of All Community Service Procedure Codes on Claims with Emergency Services in Setting=Community";

		proc print data=comm_proc_codes_emer noobs;
		run; 

		ods excel options(sheet_name="1e: Comm Procs NOT Emer Srvc");

		title "Frequency of All Community Service Procedure Codes on Claims WITH NO Emergency Services in Setting=Community";

		proc print data=comm_proc_codes_notemer noobs;
		run;

		**** Outpatient/Inpatient *** ;

		ods excel options(sheet_name="2a: Outpat Inpat Srvc Procs");

		title "Frequency of All Procedure Codes IDed as Inpatient Services on Outpatient Setting SUD Claims";

		proc print data=outpatient_inpat_services noobs;
		run;

		ods excel options(sheet_name="2b: Outpat Inpat Srvc Revs");

		title "Frequency of All Revenue Codes IDed as Inpatient Services on Outpatient Setting SUD Claims";

		proc print data=outpatient_inpat_services_r noobs;
		run;

		ods excel options(sheet_name="2c: Outpat Inpat Srvc Samp");

		title "Print of 100 Sample Claim Lines from Outpatient Setting SUD Claims with Inpatient Services";

		proc print data=outpatient_inpat_services_samp noobs;
		run;

ods excel close;

%mend SUD_QC_OT_SETTING_TYPES;
