/*******************************************************************************/
/* Program: 99_sud_macro_lists.sas                                        
/* Date   : 01/2019                                                             
/* Author : Rosie Malsberger                                                   
/* Purpose: SUD macro lists - to be included in driver program
/*******************************************************************************/

** Macro variables with lists of codes/col names to be referenced in programs;

** Lists of all SUD category descriptions (as given in lookup tables) and
   corresponding indicators;

%let descriptions=alcohol caffeine cannabis hallucinogens inhalants opioid polysubstance sha stimulants tobacco other naltrexone;

%let indicators=ALCHL CFFNE CNNBS HLLCNGN INHLNTS OPIOIDS PLYSBSTNCE SHA STMLNTS TBCCO OTHER NLTRXNE;

* Macro lists of all eligibility codes grouped into six categories - note the sixth category is CHIP which
   we are not including as a group for analysis, but still need to count the # of months;

%let adultfam=%nrstr('01','02','03','04','09','27','32','33','34','35','36','56','70','71');

%let child=%nrstr('06','07','08','28','29','30','31','54','55');

%let pregnant=%nrstr('05','53');

%let aged=%nrstr('11','12','13','14','15','17','18','16','19','20','21','22','23','24','25','26','37','38','39',
                 '40','41','42','43','44','45','46','47','48','49','50','51','52','59','60','69');

%let expansion=%nrstr('72','73','74','75');

%let chip=%nrstr('61','62','63','64','65','66','67','68');

%let cats=adultfam child pregnant aged expansion chip;

%let disabled_yn=%nrstr('11','12','13','15','16','17','18','19','20','22','23','25','26','37','38','39','40','41',
                        '42','43','44','46','51','52','59','60');

%let disabled_y=%nrstr('21','24','45','47','48','49','50','69');

%let disabled_n=%nrstr('01','02','03','04','05','06','07','08','09','10','14','27','28','29','30','31','32','33','34','35','36',
                       '53','54','55','56','61','62','63','64','65','66','67','68','70','71','72','73','74','75');

** List of all revenue code values to identify inpatient psych (used for LT claim setting assignment);

%let inpat_psych_rev = %nrstr('0114','0124','0134','0144','0154','0204');

** Macro list of all Settings to loop over;

%let settings=Community Home Inpatient Outpatient Residential Unknown;

** Create macro list of all Service type descriptions (as given in lookup tables) and
   corresponding indicators;

%let service_types=
	Case Management #
	Community Support #
	Consultation #
	Counseling #
	Detoxification #
	Emergency Services #
	Inpatient Care #
	Intervention #
	MAT #
	Medication Management #
	Observation Care #
	Other #
	Partial Hospitalization #
	Peer Support #
	Physician Services #
	Rx #
	Screening/Assessment #
	Treatment Program;


%let service_inds=
	CASE_MGMT #
	COMM_SPRT #
	CNSLTN #
	CNSLING #
	DETOX #
	EMER_SRVCS #
	INPAT #
	INTRVN #
	MAT #
	MED_MGMT #
	OBS_CARE #
	OTHER #
	PART_HOSP #
	PEER_SPRT #
	PHYS_SRVCS #
	RX #
	SCN_ASSMT #
	TREAT ;

** List of MAT medication categories;

%let mat_meds=
	Acamprosate #
	Buprenorphine #
	Bupropion #
	Disulfiram #
	Methadone #
	Naltrexone #
	Nicotine #
	Other #
	Varenicline;


** Macro lists of specific service types we want to either count the number of unique claims or
   the number of unique days of service;

%let services_count_claims=
    CNSLING
	CNSLTN
	EMER_SRVCS
	PHYS_SRVCS
	SCN_ASSMT;

%let services_count_days=
	INPAT #
	MAT #
	OBS_CARE #
	PART_HOSP #
	TREAT;

%let services_count_days_types =
	Inpatient Care #
	MAT #
	Observation Care #
	Partial Hospitalization #
	Treatment Program;

** Macro lists of NDC codes to hard code days;

%let ndc30 = %nrstr('65757030001','12496010001','12496030001');
%let ndc77 = %nrstr('6936431436');
%let ndc180 = %nrstr('58284010014');

** Macro lists of procedure codes to hard code days;

%let proc30 = %nrstr('J2315','Q9991','Q9992','G2073');
%let proc180 = %nrstr('J0570','G0516','G0518','G2070');
