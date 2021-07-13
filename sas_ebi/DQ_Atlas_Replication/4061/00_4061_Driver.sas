/************************************************************************************
* Copyright (C) Mathematica Policy Research, Inc. 
* This code cannot be copied, distributed or used without the express written 
* permission of Mathematica Policy Research, Inc. 
*************************************************************************************/

/*************************************************************************/
/*** organization : Mathematica Policy Research
/*** project      : 4061 MACBIS, Task 4 and 5
/*** program      : 000_IB_4061_Driver.sas
/*** author       : SVerghese
/*** purpose      : DRIVER for DQ Brief 4061
/*************************************************************************/

%let ibname   = 4061_Medicaid_Enrollment;

%let briefnum = %substr(&ibname.,1,4);
%let mprefix  = m&briefnum._;

/**********************************
Run programs 
***********************************/

title1 "IB &ibname.";
%include "&progpath./&ibname./01_&briefnum._Lookup_MDCD_CHIP_PI.sas";
%include "&progpath./&ibname./02_&briefnum._Measure.sas";

%macro run_brief;

proc sql;

%tmsis_connect;

%measure;

%tmsis_disconnect;
quit;

%mend;

%run_brief;
