/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/
/*******************************************************************************/
/* Program: 00_5131_Driver.sas                                        
/* Date   : 12/2018                                                             
/* Author : Preeti Gill                                                 
/* Purpose: Missing Diagnosis Codes
/*******************************************************************************/

%let ibname = 5131_Missing_and_Invalid_Dx;

%let briefnum = %substr(&ibname.,1,4);
%let mprefix  = M&briefnum._;

%let clm_type_keep = %str('1', 'A', '3', 'C');
%let clm_type_ffs    = '1', 'A';
%let clm_type_mco    = '3', 'C';

*===================================================================================;
* Run programs;
*===================================================================================;
/*run all macros for data processing*/
%include "&progpath./&ibname./01_5131_Analysis.sas";
%include "&progpath./&ibname./02_5131_Measure.sas";

/*Run the driver program which incorporates the above macros*/
%macro run_brief();
	proc sql;
	%tmsis_connect;

		*-----------------------------------------------------------------------------------;
		* Extract claims and claim lines                        ;
		*-----------------------------------------------------------------------------------;
	    %extract_claims(type = lt);
		%extract_claims(type = ip);
		%extract_claims(type = ot);

		*-----------------------------------------------------------------------------------;
		* Generate all measures               											    ;
		*-----------------------------------------------------------------------------------;
		%measure(type = ip, startnum=1);
		%measure(type = lt, startnum=8);
		%ot_measure(startnum=15);
		%measures_comb;

	%tmsis_disconnect;
quit;
%mend;
%run_brief();
