/**********************************************************************************************/
/*Program: 07_sud_claims_assign
/*Author: Rosalie Malsberger, Mathematica Policy Research
/*Date: 01/2019
/*Purpose: Macro to read in tables with unique link_key values for SUD claims from prior
/*         program, join back to raw lines, and assign to setting/service types.
/*Mod: 
/*Notes: 
/**********************************************************************************************/
/**********************************************************************************************/
/* Copyright (C) Mathematica Policy Research, Inc.                                            */
/* This code cannot be copied, distributed or used without the express written permission     */
/* of Mathematica Policy Research, Inc.                                                       */ 
/**********************************************************************************************/

%macro sud_claims_assign;

	** For all file types, must join SUD link_keys back to raw lines to get needed cols.
       NOTE because we are now counting services, we will drop all denied lines;

	%pull_sud_claims(IP)
	%pull_sud_claims(LT)
	%pull_sud_claims(OT)
	%pull_sud_claims(RX);

	** For OT, must assign to setting type based on specific claim values. 
	   Join to crosswalk of setting type (procedure, bill type, POS, and rev);


		execute (
			create temp table OT_SUD_SETTING as
			select a.*,
			       case when bill_type_cd is not null
				        then 1 else 0
						end as bill_type_cd_non_null,

			       b.SETTING_TYPE as SETTING_PRCDR,
				   c.SETTING_TYPE as SETTING_SRVC_PLC,
				   d.SETTING_TYPE as SETTING_BILL_TYPE,
				   e.SETTING_TYPE as SETTING_REV,

				   case when SETTING_PRCDR is not null
				        then 1 else 0
						end as PRCDR_HAS_SETTING,

					case when SETTING_SRVC_PLC is not null
				        then 1 else 0
						end as SRVC_PLC_HAS_SETTING,

					case when SETTING_BILL_TYPE is not null
				        then 1 else 0
						end as BILL_TYPE_HAS_SETTING,

					case when SETTING_REV is not null
				        then 1 else 0
						end as REV_HAS_SETTING


			from OT_SUD_FULL a

			     left join
				 (select * from codes_setting where TYPE='PRCDR') b
				 on a.prcdr_1_cd = b.CODE

				 left join
				 (select * from codes_setting where TYPE='SRVC_PLC') c
				 on a.srvc_plc_cd = c.CODE

				 left join
				 (select * from codes_setting where TYPE='BILL_TYPE') d
				 on a.bill_type_cd_lkup = d.CODE

				 left join
				 (select * from codes_setting where TYPE='REV') e
				 on a.rev_cd = e.CODE

		) by tmsis_passthrough;


		** Roll up to header-level and use rules to assign setting based on the four mapped values.
		   Also get date values to use in program 09 (when must pull claims with Setting = Inpatient and
		   look to services 30 days after discharge/ending date);

		execute (
			create temp table OT_SUD_SETTING_ROLLUP as
			select *,

				   /* Assign when claim has TOB setting and not POS setting (Community will follow the same rules as non-Community except for Outpatient) */

			       case when (SETTING_BILL_TYPE is not null and SETTING_SRVC_PLC is null and SETTING_PRCDR is null) or 
				             (SETTING_BILL_TYPE is not null and SETTING_BILL_TYPE != '4. Outpatient' and SETTING_SRVC_PLC is null and SETTING_PRCDR = '0. Community')

                              then SETTING_BILL_TYPE

						when SETTING_BILL_TYPE = '4. Outpatient' and SETTING_SRVC_PLC is null and SETTING_PRCDR = '0. Community'
                             then '0. Community'

					/* Assign when claim has POS setting and COMPLETELY MISSING TOB (again Community follows same rules except for Outpatient) */

						when (SETTING_SRVC_PLC is not null and bill_type_cd_non_null = 0 and SETTING_PRCDR is null) or 
				             (SETTING_SRVC_PLC is not null and SETTING_SRVC_PLC != '4. Outpatient' and bill_type_cd_non_null = 0 and SETTING_PRCDR = '0. Community')

                              then SETTING_SRVC_PLC

						when SETTING_SRVC_PLC = '4. Outpatient' and bill_type_cd_non_null = 0 and SETTING_PRCDR = '0. Community'
                             then '0. Community'

					/* Assign when claim has BOTH POS and TOB setting - must look to REV_CD. If has rev code, use TOB. If no rev code, use POS.
					   For community setting, only use the POS/TOB value if not Outpatient (otherwise Community) */

						when (SETTING_BILL_TYPE is not null and SETTING_SRVC_PLC is not null and rev_cd_any=1 and SETTING_PRCDR is null) or
                             (SETTING_BILL_TYPE is not null and SETTING_BILL_TYPE != '4. Outpatient' and SETTING_SRVC_PLC is not null and rev_cd_any=1
                              and SETTING_PRCDR = '0. Community') 

						     then SETTING_BILL_TYPE

						when SETTING_BILL_TYPE = '4. Outpatient' and SETTING_SRVC_PLC is not null and rev_cd_any=1 and SETTING_PRCDR = '0. Community'
							 then '0. Community'

						when (SETTING_BILL_TYPE is not null and SETTING_SRVC_PLC is not null and rev_cd_any=0 and SETTING_PRCDR is null) or
						     (SETTING_BILL_TYPE is not null and SETTING_SRVC_PLC is not null and SETTING_SRVC_PLC != '4. Outpatient' and rev_cd_any=0
                              and SETTING_PRCDR = '0. Community')
						     
						     then SETTING_SRVC_PLC

						when SETTING_BILL_TYPE is not null and SETTING_SRVC_PLC = '4. Outpatient' and rev_cd_any=0 and SETTING_PRCDR = '0. Community'
						     then '0. Community'

					/* Assign when neither POS or TOB map to a setting, OR POS maps with a non-null value of TOB that does not map, and rev code maps,
				       use the setting from rev code (max value of setting). For community, as usual use value unless = Outpatient, and then set as Community */

						when (SETTING_BILL_TYPE is null and SETTING_SRVC_PLC is null and SETTING_REV is not null and SETTING_PRCDR is null) or
						     (SETTING_SRVC_PLC is not null and bill_type_cd_non_null = 1 and SETTING_REV is not null and SETTING_PRCDR is null) or

							 (SETTING_BILL_TYPE is null and SETTING_SRVC_PLC is null and SETTING_REV is not null and SETTING_REV != '4. Outpatient'
                                   and SETTING_PRCDR = '0. Community') or
						     (SETTING_SRVC_PLC is not null and bill_type_cd_non_null = 1 and SETTING_REV is not null and SETTING_REV != '4. Outpatient' 
                                   and SETTING_PRCDR = '0. Community')

						then SETTING_REV

						when (SETTING_BILL_TYPE is null and SETTING_SRVC_PLC is null and SETTING_REV = '4. Outpatient'
                                   and SETTING_PRCDR = '0. Community') or

						     (SETTING_SRVC_PLC is not null and bill_type_cd_non_null = 1 and SETTING_REV = '4. Outpatient' 
                                   and SETTING_PRCDR = '0. Community')

						then '0. Community'

					/* Assign when POS does map and both TOB and REV are non-null but neither map */

						when SETTING_SRVC_PLC is not null and SETTING_BILL_TYPE is null and bill_type_cd_non_null = 1 and SETTING_REV is null 
                             and rev_cd_any=1

						then '5. Unknown'

					/* Assign when POS does map and TOB is non-null but does not map, and REV is null - use POS setting, except for Community, where
					   set to Community if POS = Outpatient */

						when (SETTING_SRVC_PLC is not null and bill_type_cd_non_null = 1 and rev_cd_any=0 and SETTING_PRCDR is null) or
						     (SETTING_SRVC_PLC is not null and SETTING_SRVC_PLC != '4. Outpatient' and bill_type_cd_non_null = 1 and rev_cd_any=0 
                                 and SETTING_PRCDR = '0. Community')

						 then SETTING_SRVC_PLC

						 when (SETTING_SRVC_PLC is not null and SETTING_SRVC_PLC = '4. Outpatient' and bill_type_cd_non_null = 1 and rev_cd_any=0 
                                 and SETTING_PRCDR = '0. Community')

						 then '0. Community'
						     

					/* OTHERWISE if NONE map, set to Unknown */

						when SETTING_BILL_TYPE is null and SETTING_SRVC_PLC is null and SETTING_REV is null

						then '5. Unknown'

					/* Ensure we have no values of UNASSIGNED */

						else '6. UNASSIGNED'

						end as SETTING

			from

				(select submtg_state_cd,
				       msis_ident_num,
					   ot_link_key,
					   srvc_plc_cd,
					   bill_type_cd,
					   bill_type_cd_non_null,
					   srvc_bgnng_dt,
					   srvc_endg_dt,
					   min(srvc_bgnng_dt_line) as srvc_bgnng_dt_line_min,
					   max(srvc_bgnng_dt_line) as srvc_bgnng_dt_line_max,
					   max(srvc_endg_dt_line) as srvc_endg_dt_line_max,
					   max(SETTING_BILL_TYPE) as SETTING_BILL_TYPE,
					   max(SETTING_SRVC_PLC) as SETTING_SRVC_PLC,
					   max(SETTING_PRCDR) as SETTING_PRCDR,
					   max(SETTING_REV) as SETTING_REV,
					   case when max(rev_cd) is not null then 1 else 0 end as rev_cd_any

				from OT_SUD_SETTING
				group by submtg_state_cd,
				         msis_ident_num,
					     ot_link_key,
						 srvc_plc_cd,
						 bill_type_cd,
                         bill_type_cd_non_null,
						 srvc_bgnng_dt,
                         srvc_endg_dt)

		) by tmsis_passthrough;

		** Now for all four file types, join line-level files to procedure code/NDC crosswalks to get service type.
	       Must also pull in MAT_TYPE and MAT_MED_CAT.
	       For IP and RX, will assign Setting based on file type. 
		   For OT, will need to join on Settings calculated above (after rolling up to header-level).
		   For LT, identify lines with a rev_cd that matches the list of inpatient psych rev codes, then assign
		    the entire claim to Inpatient if ANY line has a matching rev code, otherwise Residential;

		%crosswalk_service_type(IP, 
                                nprocs=6, 
								setting=Inpatient,
                                dates=dschrg_dt srvc_endg_dt_line srvc_bgnng_dt_line)

		%crosswalk_service_type(LT,
                                dates=srvc_endg_dt);

		%crosswalk_service_type(OT,
								nprocs=2,
                                dates=srvc_endg_dt srvc_bgnng_dt srvc_endg_dt_line);

		%crosswalk_service_type(RX,
								setting=Outpatient,
                                dates=rx_fill_dt);

		** Now stack all four files together;

		execute (
			create temp table SUD_SERVICES as

			(select *, 'IP' as FILE from IP_SUD_SRVC_ROLLUP)

			union all
			(select *, 'LT' as FILE from LT_SUD_SRVC_ROLLUP)

			union all
			(select *, 'OT' as FILE from OT_SUD_SRVC_ROLLUP2)

			union all
			(select *, 'RX' as FILE from RX_SUD_SRVC_ROLLUP)


		) by tmsis_passthrough;

		title "Crosstab of assigned setting for all file types";

		%crosstab(SUD_SERVICES, FILE SETTING)

		** For the C tables, must roll up to the bene-level to get counts of benes with each service and setting.
		   First in inner query, create indicator for each setting type to then take max of;

		execute (
			create temp table SUD_BENE_SETTING_SRVC0 as

			select submtg_state_cd,
			       msis_ident_num
			       %do t=1 %to %sysfunc(countw(&service_inds.,'#'));
						%let ind=%scan(&service_inds.,&t.,'#');
					    ,max(TRT_SRVC_&ind.) as TRT_SRVC_&ind.
					%end;
					%do s=1 %to %sysfunc(countw(&settings.));
					   	%let setting=%scan(&settings.,&s.);
						,max(&setting._ind) as &setting._ind
					%end;
					%do m=1 %to %sysfunc(countw(&mat_meds.,'#'));
			   	  		%let med=%scan(&mat_meds.,&m.,'#');
						,max(MAT_&med.) as MAT_&med.
					%end;


			from (
				select *
					   %do s=1 %to %sysfunc(countw(&settings.));
					   	  %let setting=%scan(&settings.,&s.);
						  ,case when SETTING=%nrbquote('&setting.')
						        then 1 else 0
								end as &setting._ind
						%end;

				from SUD_SERVICES )
			group by submtg_state_cd,
			         msis_ident_num

		) by tmsis_passthrough;

		** Must finally join to population_sud to get OPIOIDS indicator;

		execute (
			create temp table SUD_BENE_SETTING_SRVC as
			select a.*,
			       b.SUD_OPIOIDS

			from SUD_BENE_SETTING_SRVC0 a
			     inner join
				 population_sud b

			on a.submtg_state_cd = b.submtg_state_cd and
			   a.msis_ident_num = b.msis_ident_num


		) by tmsis_passthrough;

		%macro counts(suffix=);

			create table sasout.state_sud_set_srvc&suffix. as select * from connection to tmsis_passthrough
			(select submtg_state_cd,
			        count(*) as nbenes
					%do s=1 %to %sysfunc(countw(&settings.));
					   	  %let setting=%scan(&settings.,&s.);
						  ,sum(&setting._ind) as &setting.
					%end;
					%do t=1 %to %sysfunc(countw(&service_inds.,'#'));
						%let ind=%scan(&service_inds.,&t.,'#');
						,sum(TRT_SRVC_&ind.) as TRT_SRVC_&ind.
					%end;
					%do m=1 %to %sysfunc(countw(&mat_meds.,'#'));
			   	  		%let med=%scan(&mat_meds.,&m.,'#');
						,sum(MAT_&med.) as MAT_&med.
					%end;

			from SUD_BENE_SETTING_SRVC
			%if &suffix. ne  %then %do;
				where SUD_OPIOIDS=1
			%end;
			group by submtg_state_cd );

			create table sasout.national_sud_set_srvc&suffix. as select * from connection to tmsis_passthrough
			(select count(*) as nbenes
					%do s=1 %to %sysfunc(countw(&settings.));
					   	  %let setting=%scan(&settings.,&s.);
						  ,sum(&setting._ind) as &setting.
					%end;
					%do t=1 %to %sysfunc(countw(&service_inds.,'#'));
						%let ind=%scan(&service_inds.,&t.,'#');
						,sum(TRT_SRVC_&ind.) as TRT_SRVC_&ind.
					%end;
					%do m=1 %to %sysfunc(countw(&mat_meds.,'#'));
			   	  		%let med=%scan(&mat_meds.,&m.,'#');
						,sum(MAT_&med.) as MAT_&med.
					%end;


			from SUD_BENE_SETTING_SRVC
            %if &suffix. ne  %then %do;
				where SUD_OPIOIDS=1
			%end;);

		%mend counts;

		%counts;
		%counts(suffix=_OP);


%mend sud_claims_assign;
