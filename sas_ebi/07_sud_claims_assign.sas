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

	** For OT only, must assign to setting type based on specific claim values (all other file
	   types are one setting only). Join to crosswalk of setting type (procedure, bill type, POS, and rev);


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

		title2 "Join of OT SUD claims to Setting lookup table";

		%crosstab(OT_SUD_SETTING,PRCDR_HAS_SETTING SRVC_PLC_HAS_SETTING BILL_TYPE_HAS_SETTING REV_HAS_SETTING)
		%crosstab(OT_SUD_SETTING,SETTING_PRCDR)
		%crosstab(OT_SUD_SETTING,SETTING_SRVC_PLC)
		%crosstab(OT_SUD_SETTING,SETTING_BILL_TYPE)
		%crosstab(OT_SUD_SETTING,SETTING_REV);

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

		title2 "QC creation of SETTING for rolled-up claims - OT";

		%crosstab(OT_SUD_SETTING_ROLLUP,SETTING);

		%crosstab(OT_SUD_SETTING_ROLLUP,SETTING SETTING_PRCDR SETTING_SRVC_PLC SETTING_BILL_TYPE SETTING_REV rev_cd_any bill_type_cd_non_null,
                  outfile=sasout.OT_SETTING_CROSSTAB);

		** Now for all four file types, join line-level files to procedure code/NDC crosswalks to get service type.
	       Must also pull in MAT_TYPE and MAT_MED_CAT.
	       For all except OT, will assign Setting based on file type. For OT, will need to join on Settings calculated above
		   (after rolling up to header-level);

		%crosswalk_service_type(IP, 
                                nprocs=6, 
								setting=Inpatient,
                                dates=dschrg_dt srvc_endg_dt_line srvc_bgnng_dt_line)

		%crosswalk_service_type(LT,
		                        setting=Residential,
                                dates=srvc_endg_dt);

		%crosswalk_service_type(OT,
								nprocs=2,
                                dates=srvc_endg_dt srvc_bgnng_dt srvc_endg_dt_line);

		%crosswalk_service_type(RX,
								setting=Outpatient,
                                dates=rx_fill_dt);

		**** ADDITIONAL QC PULL PROCEDURE CODES FOR OT CLAIMS WITH:
				SETTING = COMMUNITY AND SERVICE TYPE = EMERGENCY SERVICES
				SETTING = OUTPATIENT AND SERVICE TYPE = INPATIENT CARE  **** ;

		execute (
			create temp table OT_SUD_ADDITIONAL_QC as
			select a.submtg_state_cd,
			       a.msis_ident_num,
			       a.OT_LINK_KEY,
				   a.SETTING,
				   a.srvc_plc_cd,
				   a.bill_type_cd,
				   b.prcdr_1_cd,
				   b.SERVICE_TYPE_PRCDR1,
				   b.rev_cd,
				   b.SERVICE_TYPE_REV,
				   b.ndc_cd,
				   b.SERVICE_TYPE_NDC

			from OT_SUD_SETTING_ROLLUP a
			     left join
				 OT_SUD_SRVC b

			on a.OT_LINK_KEY = b.OT_LINK_KEY

		) by tmsis_passthrough;

	   %crosstab(OT_SUD_ADDITIONAL_QC,prcdr_1_cd,
	              wherestmt=%nrstr(where SETTING='0. Community' and SERVICE_TYPE_PRCDR1='Emergency Services'),
                  outfile=community_emer_services);

	   %crosstab(OT_SUD_ADDITIONAL_QC,prcdr_1_cd,
	              wherestmt=%nrstr(where SETTING='4. Outpatient' and SERVICE_TYPE_PRCDR1='Inpatient Care'),
                  outfile=outpatient_inpat_services);

	   %crosstab(OT_SUD_ADDITIONAL_QC,rev_cd,
	              wherestmt=%nrstr(where SETTING='0. Community' and SERVICE_TYPE_REV='Emergency Services'),
                  outfile=community_emer_services_r);

	   %crosstab(OT_SUD_ADDITIONAL_QC,rev_cd,
	              wherestmt=%nrstr(where SETTING='4. Outpatient' and SERVICE_TYPE_REV='Inpatient Care'),
                  outfile=outpatient_inpat_services_r);

		** Join the rolled up table back to the above to pull all lines from claims marked as the above;

		execute (
			create temp table OT_SUD_ADDITIONAL_QC2 as
			select a.*,
			       b.srvc_dt,
			       b.TRT_SRVC_EMER_SRVCS,
				   b.TRT_SRVC_INPAT


			from OT_SUD_ADDITIONAL_QC a
			     inner join
				 OT_SUD_SRVC_ROLLUP b

			on a.OT_LINK_KEY = b.OT_LINK_KEY


		) by tmsis_passthrough;

		create table community_emer_services_samp as select * from connection to tmsis_passthrough
		(select * from OT_SUD_ADDITIONAL_QC2
		where SETTING='0. Community' and TRT_SRVC_EMER_SRVCS=1
		order by OT_LINK_KEY
		limit 100);

		create table outpatient_inpat_services_samp as select * from connection to tmsis_passthrough
		(select * from OT_SUD_ADDITIONAL_QC2
		where SETTING='4. Outpatient' and TRT_SRVC_INPAT=1
		order by OT_LINK_KEY
		limit 100);

		** Also get all community support procedure codes for claims with emergency services. Must join
		   header-level table to OT line-level file with community support procedure codes identified;

		execute (
			create temp table OT_SUD_ADDITIONAL_QC3 as
			select a.OT_LINK_KEY,
			       b.TRT_SRVC_EMER_SRVCS,
				   c.prcdr_1_cd,
				   c.SETTING_PRCDR


			from (select * from OT_SUD_SETTING_ROLLUP where SETTING='0. Community') a
			     left join
				 OT_SUD_SRVC_ROLLUP b

			     on a.OT_LINK_KEY = b.OT_LINK_KEY 

				 left join
				 OT_SUD_SETTING c

				 on a.OT_LINK_KEY = c.OT_LINK_KEY		     


		) by tmsis_passthrough;

	   %crosstab(OT_SUD_ADDITIONAL_QC3,prcdr_1_cd,
	              wherestmt=%nrstr(where TRT_SRVC_EMER_SRVCS=1 and SETTING_PRCDR='0. Community'),
                  outfile=comm_proc_codes_emer);


	   %crosstab(OT_SUD_ADDITIONAL_QC3,prcdr_1_cd,
	              wherestmt=%nrstr(where TRT_SRVC_EMER_SRVCS=0 and SETTING_PRCDR='0. Community'),
                  outfile=comm_proc_codes_notemer);


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

		title2 "Freqs and crosstabs of SETTING for rolled-up claims for all four file types";

		%crosstab(SUD_SERVICES,SETTING);
		%crosstab(SUD_SERVICES,FILE SETTING);

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
