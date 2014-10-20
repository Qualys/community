#!/bin/bash
NAME="DataCenter Linux"
./dlreports.pl -e PROD1 -n "$NAME"
TMP=`echo $NAME | sed 's/ /_/'`
NAME=$TMP
echo $NAME
./cr.pl -p $NAME"_Patch_Report.csv" -s $NAME"_Scorecard_Report.csv" -v $NAME"_Scan_Report.csv"
mailx -a $NAME"_combinedreport.xlsx" -s "$NAME" Daily Report" fred@abc.com"
