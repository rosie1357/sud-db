/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/
/*******************************************************************************/
/* Program: 00_5111_Driver.sas                                        
/* Date   : 12/2018                                                             
/* Author : Rosie Malsberger                                                   
/* Purpose: claims volume analysis
/*******************************************************************************/

%let libname = 5111_Claims_Volume;

%let briefnum = %substr(&libname.,1,4);
%let mprefix = M&briefnum._;

/**********************************
Run programs 
***********************************/

%include "&progpath./&libname./01_5111_Analysis.sas";
%include "&progpath./&libname./02_5111_Measures.sas";

proc sql;
	%tmsis_connect;
/**/
/*	%volume;*/
/**/
/*	%measures(ip, 0);*/
/*	%measures(lt, 11, suffix=_65);*/
/*	%measures(ot, 22);*/
/*	%measures(rx, 33);*/

	%measures_comb(ip lt ot rx, 0 11 22 33);

	%tmsis_disconnect;
quit;
