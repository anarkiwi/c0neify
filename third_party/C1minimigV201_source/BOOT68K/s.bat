@echo off
echo.
echo to assemble use the AS V 1.42 by Alfred Arnold 
echo http://john.ccac.rwth-aachen.de:8000/as/download.html
echo download aswcurr.zip and unzip it to c:\bin\as
echo.

if exist hostbootrom.hex if exist hostbootrom.bak del hostbootrom.bak
if exist hostbootrom.hex rename hostbootrom.hex hostbootrom.bak
c:\bin\as\asw -cpu 68000 hostboot.asm -L -olist hostboot.lst 
if exist hostboot.p c:\bin\as\p2bin hostboot.p hostboot.bin -r 0-$FFF
if exist hostboot.bin hexer hostboot.bin hostbootrom.hex
del hostboot.p
del hostboot.bin

if exist bootrom.hex if exist bootrom.bak del bootrom.bak
if exist bootrom.hex rename bootrom.hex bootrom.bak
c:\bin\as\asw -cpu 68000 boot.asm -L -olist boot.lst 
if exist boot.p c:\bin\as\p2bin boot.p boot.bin -r 0-$7FF
if exist boot.bin hexer boot.bin bootrom.hex
del boot.p
del boot.bin

