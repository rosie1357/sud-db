/**********************************************************************************************/
/*Program: 01_sud_initial
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Initial SUD macro to identify DE population, pull all raw claims, and identify all SUD
/*         claims based on diagnosis code - this file of claims will be used to identify benes
/*         with SUD conditions via Tool 1 and using diagnosis codes only
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro SUD_INITIAL;

	** Read in all text files that create lookup tables;

	%macro readtext(infile);

		%include "&indata/&infile..txt";

	%mend readtext;

	%readtext(codes_sud)
	%readtext(codes_ofac);
	%readtext(codes_fac);
	%readtext(codes_prof);
	%readtext(codes_rx);

	%readtext(codes_sud_prcdr_cd);
	%readtext(codes_sud_rev_cd);
	%readtext(codes_sud_srvc_plc_cd);
	%readtext(codes_setting)
	%readtext(codes_services)

	** For SUD diagnosis codes, create new diagnosis code indicator to match TAF. Redo
	   descriptions to be the same name as the indicators;

	execute (
		create temp table codes_sud2 as
		select *

			   ,case %do s=1 %to %sysfunc(countw(&descriptions.));
			   			 %let desc=%scan(&descriptions.,&s.);
						 %let ind=%scan(&indicators.,&s.);

							 when desc_short=%nrbquote('&desc.') then %nrbquote('&ind.')

						  %end;
					  end as desc

		from codes_sud

	) by tmsis_passthrough;

	title "Diagnosis codes by category";

	%crosstab(codes_sud2, desc_short)

	** Do the same recoding for RX;

	execute (
		create temp table codes_rx2 as
		select *
		       ,case %do s=1 %to %sysfunc(countw(&descriptions.));
			   			 %let desc=%scan(&descriptions.,&s.);
						 %let ind=%scan(&indicators.,&s.);

							 when desc_short=%nrbquote('&desc.') then %nrbquote('&ind.')

						  %end;
					  end as desc

		from codes_rx

	) by tmsis_passthrough;

	** Read in the DE, identifying those with full benefits in all months of enrollment to keep, and
	   with age > 1 or < 12 to drop.
	   To identify months with enrollment, use CHIP_CD=1. For RI and WY which do not populate CHIP_CD,
	   use ELGBLTY_GRP_CD = 1-60 or 69-75.

	   Assign the value for each monthly eligibility group code to one of the five categories, and then sum
	   the number in each category to assign to one category for the year.

	   TO FIX PA CODING OF ELIGIBILITY GROUP CODE = 71 AS EXPANSION GROUP, RECODE A VALUE OF 71 TO 72 (SO CAN BE
	   INCLUDED AS EXPANSION);

	execute (
		create temp table DE_BASE as
		select %recode_state_codes(prefix=a)
			   ,de_fil_dt,
			   da_run_id,

			   DUAL_ELGBL_CD_LTST,
			   case when DUAL_ELGBL_CD_LTST in ('02','04','08') then 1
			        when DUAL_ELGBL_CD_LTST in ('01','03','05','06') then 0
					else null
					end as FULL_DUAL,

			   case when submtg_state_cd = '42' and ELGBLTY_GRP_CD_LTST = '71' then '72'
			        else ELGBLTY_GRP_CD_LTST
					end as NEW_ELGBLTY_GRP_CD_LTST

			   %do m=1 %to 12;
			   	  %if &m.<10 %then %let m=0&m.;
				  ,CHIP_CD_&m.
				  ,case when submtg_state_cd = '42' and ELGBLTY_GRP_CD_&m. = '71' then '72'
				        else ELGBLTY_GRP_CD_&m.
						end as NEW_ELGBLTY_GRP_CD_&m.

				  ,RSTRCTD_BNFTS_CD_&m.
			   %end;


			   %do m=1 %to 12;
			   	  %if &m.<10 %then %let m=0&m.;

					,case when CHIP_CD_&m. = '1' or 
				              (CHIP_CD_&m. is null and 
                              ((NEW_ELGBLTY_GRP_CD_&m. >= '01' and NEW_ELGBLTY_GRP_CD_&m. <= '60') or 
                               (NEW_ELGBLTY_GRP_CD_&m. >= '69' and NEW_ELGBLTY_GRP_CD_&m. <= '75')) )
						 then 1 
						 else 0
						 end as ENROLLED_&m.

				%end;

				,%do m=1 %to 12;
			   	    %if &m.<10 %then %let m=0&m.;
					ENROLLED_&m.
			        %if &m. < 12 %then %do; + %end;
				 %end;
				 as ENROLLED_MOS

				,case when %do m=1 %to 12;
			   	              %if &m.<10 %then %let m=0&m.;
							  %if &m. > 1 %then %do; or %end;
							  (&m. < 5 and ENROLLED_&m.=1 and (submtg_state_cd not in ('05','16','46') and RSTRCTD_BNFTS_CD_&m. not in ('1','4','7','A','B','D'))) or
							  (&m. < 5 and ENROLLED_&m.=1 and (submtg_state_cd in ('05','16','46') and RSTRCTD_BNFTS_CD_&m. not in ('1','7','A','B','D'))) or

							  (&m. >= 5 and ENROLLED_&m.=1 and (submtg_state_cd not in ('05','16','46') and RSTRCTD_BNFTS_CD_&m. not in ('1','4','5','7','A','B','D'))) or
							  (&m. >= 5 and ENROLLED_&m.=1 and (submtg_state_cd in ('05','16','46') and RSTRCTD_BNFTS_CD_&m. not in ('1','5','7','A','B','D')))


							%end;
					  then 1
					  else 0
					  end as NOT_FULL


				,case when %do m=1 %to 12;
			   	              %if &m.<10 %then %let m=0&m.;
							  %if &m. > 1 %then %do; and %end;
							  RSTRCTD_BNFTS_CD_&m. is null
							%end;
						then 1 else 0
						end as rstrctd_bnfts_cd_null

				,birth_dt
				,floor(datediff(day,birth_dt,to_date(%nrbquote('31 12 &year.'),'dd mm yyyy'))/365.25) as age
				,case when birth_dt is null then 1 else 0
				      end as birth_dt_null

				,case when age >= 12 and age <= 18 then 1
				      when age >= 19 and age < 65 then 2
					  when age >= 65 then 3
					  else null
					  end as agecat

				%do m=1 %to 12;
			   	    %if &m.<10 %then %let m=0&m.;
					%do c=1 %to 6;
						%let cat=%scan(&cats.,&c.);

					    ,case when NEW_ELGBLTY_GRP_CD_&m. in (&&&cat.) 
						      then 1 else 0
							  end as ELGBLTY_&m._&c.

					%end;
				%end;


				%do m=1 %to 12;
			   	    %if &m.<10 %then %let m=0&m.;
					,case %do c=1 %to 5;
						 	  %let cat=%scan(&cats.,&c.);

							  when NEW_ELGBLTY_GRP_CD_&m. in (&&&cat.) then &c.

						  %end;
						  else null
						  end as ELGBLTY_&m.
				%end;					   


				%do c=1 %to 6;

					,%do m=1 %to 12;
			   	    	%if &m.<10 %then %let m=0&m.;
						%if &m. > 1 %then %do; + %end;
						ELGBLTY_&m._&c.
					 %end;
					 as NMOS_ELGBLTY_&c.

				 %end;


				%do c=1 %to 5;

					,case when NMOS_ELGBLTY_&c. > 0 
                        %do c2=1 %to 5; 
						   %if &c. ne &c2. %then %do;
						   	  and NMOS_ELGBLTY_&c. >  NMOS_ELGBLTY_&c2.
							%end;
						 %end;
						 then 1 else 0
						 end as ELGBLTY_GRP_CAT_&c.

				%end;

				,case %do c=1 %to 5;
				          when ELGBLTY_GRP_CAT_&c. = 1 
                          then &c.
					   %end;

                      when NEW_ELGBLTY_GRP_CD_LTST is null
					  then 0

					  when NMOS_ELGBLTY_1 + NMOS_ELGBLTY_2 + NMOS_ELGBLTY_3 + NMOS_ELGBLTY_4 + NMOS_ELGBLTY_5 > 0

						   then coalesce(ELGBLTY_12,ELGBLTY_11,ELGBLTY_10,ELGBLTY_09,ELGBLTY_08,ELGBLTY_07,
						                 ELGBLTY_06,ELGBLTY_05,ELGBLTY_04,ELGBLTY_03,ELGBLTY_02,ELGBLTY_01)

					  when NMOS_ELGBLTY_6 > 0
					       then 6

						   else null
						   end as ELGBLTY_GRP_CAT

				%macro disabled(mo);

					,case when (NEW_ELGBLTY_GRP_CD_&mo. in (&disabled_yn.) and age <65) or
					           (NEW_ELGBLTY_GRP_CD_&mo. in (&disabled_y.))
						  then 1
						  else 0
						  end as DISABLED1_&mo.

					,case when (NEW_ELGBLTY_GRP_CD_&mo. in (&disabled_yn.) and age>=65) or
					           (NEW_ELGBLTY_GRP_CD_&mo. in (&disabled_n.))
						  then 1
						  else 0
						  end as DISABLED0_&mo.

				%mend disabled;


				%do m=1 %to 12;	
					%if &m.<10 %then %let m=0&m.;
					%disabled(&m.)
				%end;
				%disabled(ltst)

				,case when age >=65 then 1 
				      when age <65 then 0
					  else null
					  end as age_ge65


				%do d=0 %to 1;

					,%do m=1 %to 12;
			   	    	%if &m.<10 %then %let m=0&m.;
						%if &m. > 1 %then %do; + %end;
						DISABLED&d._&m.
					 %end;
					 as NMOS_DISABLED&d.

				 %end;

				 ,case when NMOS_DISABLED0 < NMOS_DISABLED1
				       then 1
					   when NMOS_DISABLED0 > NMOS_DISABLED1
					   then 0
					   when NMOS_DISABLED0 = NMOS_DISABLED1 and NMOS_DISABLED0>0 and DISABLED1_LTST=1
					   then 1
					   when NMOS_DISABLED0 = NMOS_DISABLED1 and NMOS_DISABLED0>0 and DISABLED0_LTST=1
					   then 0
					   else null
					   end as DISABLED_YR

		from cms_prod.data_anltcs_taf_ade_base_vw a
		where ltst_run_ind=1 and de_fil_dt=%nrbquote('&year.') and misg_elgblty_data_ind=0 and
		      submtg_state_cd not in (&states_exclude.)

	) by tmsis_passthrough; 

	title2 "run IDs pulled in for DE";

	%crosstab(DE_BASE,de_fil_dt da_run_id)

	** Now subset to our population of interest
	** EDIT: for those age_ge65, we are going to set DISABLED_YR=0 for ALL (to combine in tables);

	execute (
		create temp table population as
		select submtg_state_cd,
		       msis_ident_num,
			   age,
			   NOT_FULL,
			   rstrctd_bnfts_cd_null,
			   ELGBLTY_GRP_CAT,
			   ENROLLED_MOS,
			   FULL_DUAL,
			   AGECAT,
			   case when age_ge65=1 then 0 else DISABLED_YR
			        end as DISABLED_YR

		from DE_BASE
		where ENROLLED_MOS>0 and NOT_FULL=0 and age >= 12 and ELGBLTY_GRP_CAT != 6


	) by tmsis_passthrough;

	title2 "QC selection of benes for analytic population";

	%let cols=submtg_state_cd age not_full rstrctd_bnfts_cd_null ELGBLTY_GRP_CAT ENROLLED_MOS FULL_DUAL AGECAT DISABLED_YR;

	%do c=1 %to %sysfunc(countw(&cols.));
		%let col=%scan(&cols.,&c.);

		title3 "crosstab of &col.";

		%crosstab(population,&col.)

	%end;

	** Read in all claim types, joining header to line and keeping needed variables. Do a final
	   join to the above population to only keep claims for those benes. Note for
	   procedure codes (IP and OT only), because of the CA state-specific codes, procedure codes are
	   NOT listed here but will be specifically pulled in/recoded in the readclaims macro.
	   For diagnosis codes, they are not listed for IP because of the TN fix;

	%readclaims(IP,
                hvars=admsn_dt 
                      dschrg_dt 
                      bill_type_cd 
					  hosp_type_cd
					  ,

				lvars=rev_cd
				      ndc_cd,

                hvars_nulls=admsn_dt
                            dschrg_dt,

                lvars_nulls=srvc_bgnng_dt_line
                            srvc_endg_dt_line);

	%readclaims(LT,
				hvars=admsn_dt
                      dschrg_dt
                      srvc_bgnng_dt
				      srvc_endg_dt
					  bill_type_cd
					  %do i=1 %to 5;
						dgns_&i._cd
					  %end; ,

				lvars=rev_cd
				      ndc_cd,

                hvars_nulls=admsn_dt
                            dschrg_dt
                            srvc_bgnng_dt
                            srvc_endg_dt,

                lvars_nulls=srvc_bgnng_dt_line
                            srvc_endg_dt_line ); 

	%readclaims(OT,

				hvars=srvc_bgnng_dt
                      srvc_endg_dt
                      bill_type_cd
				      srvc_plc_cd
					  %do i=1 %to 2;
						dgns_&i._cd
					  %end; ,

				lvars=rev_cd
				      ndc_cd,

                hvars_nulls=srvc_plc_cd
				            bill_type_cd
                            srvc_bgnng_dt
                            srvc_endg_dt,

                lvars_nulls=srvc_bgnng_dt_line
                            srvc_endg_dt_line); 

	%readclaims(RX,
			    hvars=rx_fill_dt,

				lvars=ndc_cd suply_days_cnt,

                hvars_nulls=rx_fill_dt,

				lvars_nulls=ndc_cd
                            suply_days_cnt);


	** Now for IP, LT and OT, join to all diagnosis codes to the SUD diagnosis code table to
	   identify claims (header-level) with any SUD diagnosis code
	   (Note the diagnosis code identification is used in methods 1 and 2 only);

	%join_sud_dgns(IP, ndiag=12);
	%join_sud_dgns(LT, ndiag=5);
    %join_sud_dgns(OT, ndiag=2);


	** For IP and OT, must identify claims where ALL non-null procedure codes are lab/transport, to be dropped;

	%lab_transport(IP, nproc=6);
	%lab_transport(OT, nproc=1); 

%mend SUD_INITIAL;

