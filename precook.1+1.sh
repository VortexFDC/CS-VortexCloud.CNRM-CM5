#!/bin/bash

#############
#
# Crea grib files para periodos de 2 dias. Desde d1 a d2
#
#############

ens=r1i1p1

mdl=$1
s=$2
idate=$3

## TEMP
#idate=2005-12-22
#mdl=CNRM-CM5
#s=historical


if [ -z "$idate" ] || [ `echo $idate | awk -F- '{print NF}'` -ne 3 ];then echo 'Please specify start date in format YYYY-MM-DD';exit;fi

d1=$idate							# Inicio SHORT
d2=`date +%Y-%m-%d -d "$d1 2 day"`	# Final SHORT
dx=`date +%Y-%m-%d -d "$d1 -1 day"` # Inicio LONG
dy=`date +%Y-%m-%d -d "$d2 1 day"`	# Final LONG

dtx=`echo $d1.$d2 | sed 's/-//g'`
y1=`echo $dx | awk -F- '{print $1}'`
y2=`echo $dy | awk -F- '{print $1}'`
m1=`echo $dx | awk -F- '{print $2}' | sed 's/^0*//'`
m2=`echo $dy | awk -F- '{print $2}' | sed 's/^0*//'`

if [ $m1 -eq $m2 ];then 
	mx=`printf "%02d %02d" $m1 $(($m1+1))`
else
	mx=`printf "%02d %02d %02d" $m1 $(($m1+1)) $(($m1+2))`
fi

scratch=scratch.$mdl
storage=/home/martin/storage/models/$mdl

if [ -f $storage/out/wrfinput/$mdl.$s.$dtx.grb ];then echo 'Grib file '$mdl.$s.$dtx'.grb already exists';exit;fi

plev="100000,97500,95000,92500,90000,87500,85000,82500,80000,77500,75000,70000,65000,60000,55000,50000,45000,40000,35000,30000,25000,22500,20000,17500,15000,12500,10000,7000,5000,3000"
plev2="1000,975,950,925,900,875,850,825,800,775,750,700,650,600,550,500,450,400,350,300,250,225,200,175,150,125,100,70,50,30"

# Check if tslsi or ts
isfile=`ls $storage/files/ | grep tslsi_ | wc -l`
if [ $isfile -eq 0 ]; then
    tslsi=ts
else
    tslsi=tslsi
fi

#step=1  # crop
#step=2  # 3D: interpolate pressure levels
#step=3  # surface variables
#step=4  # land variables
#step=5  # land sea mask
#step=6  # nc to grib

for step in 1 2 3 4 5 6 ;do

if [ $step -eq 1 ] ; then
echo '## STEP 1 ##'

if [ -d $scratch ] ; then rm -r $scratch  ;  fi
mkdir -p $scratch
for i in crop zinter ready grb merge tab hlev;do mkdir -p $scratch/$i ; done

echo "crop period and interpolate ... " $d1 $d2

# input.sfc.grb
# huss psl ps tas uas vas tos ts/tslsi

for v in huss psl ps tas uas vas tos $tslsi ; do
f=`ls $storage/files/${v}_*_${mdl}_${s}_${ens}_$y1.nc`
freq=`echo $f | awk -F_ '{print $2}'`

if [ $(($y1+1)) -eq $y2 ] && [[ $freq != *"mon"* ]];then
	cdo -s cat $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y1.nc $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y2.nc $scratch/crop/$v.cat.nc
	f=$scratch/crop/$v.cat.nc
fi

echo 'select ... '$v $freq
if [ $v == tos ];then
    cdo -s -r griddes $scratch/crop/psl.nc > $scratch/tab/reg.grid
    cdo -s -r -remapdis,$scratch/tab/reg.grid -seldate,$d1,$d2  -inttime,$d1,00:00,6hour -seldate,$dx,$dy $f $scratch/crop/$v.nc
else
    if [[ $freq == *"6hr"* ]];then
        cdo -s -r  -seldate,$d1,$d2 $f $scratch/crop/$v.nc
    elif [[ $freq == *"mon"* ]];then
        for m in $mx; do
			if [ $m -gt 12 ];then
                f2=$storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$(($y1+1)).nc
                if [ ! -f $f2 ];then
                    cdo -s -r setday,1 -setyear,$(($y1+1)) -setmon,1 -settime,00:00 -selmon,12 $f $scratch/crop/$v.mon$m.nc
                else
                    m2=$(($m-12))
                    cdo -s -r setday,1 -settime,00:00 -selmon,$m2 $f2 $scratch/crop/$v.mon$m.nc
                fi
			else
	            cdo -s -r setday,1 -settime,00:00 -selmon,$m $f $scratch/crop/$v.mon$m.nc
			fi
        done
        rm -f $scratch/crop/$v.foo.nc
        cdo -s -r cat $scratch/crop/$v.mon*.nc $scratch/crop/$v.foo.nc
        cdo -s -r  -seldate,$d1,$d2 -inttime,$d1,00:00,6hour $scratch/crop/$v.foo.nc $scratch/crop/$v.nc
    else
        cdo -s -r  -seldate,$d1,$d2 -inttime,$d1,00:00,6hour -seldate,$dx,$dy $f $scratch/crop/$v.nc
    fi
fi
done

# input.3d.grb
# ta ta(day) ua ua(day) va va(day) hus zg

for v in ta ua va hus zg ; do
# Per les vars que poden tenir mes d'una freq
if [ $v == ta ] || [ $v == ua ] || [ $v == va ];then
    for freq in `ls $storage/files/${v}_*_${mdl}_${s}_${ens}_$y1.nc | awk -F_ '{print $2}'`; do
	    echo 'select ... '$v $freq
        f=$storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y1.nc
	
		if [ $(($y1+1)) -eq $y2 ] && [[ $freq != *"mon"* ]];then
			rm -f $scratch/crop/$v.cat.nc
		    cdo -s cat $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y1.nc $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y2.nc $scratch/crop/$v.cat.nc
		    f=$scratch/crop/$v.cat.nc
		fi

        if [[ $freq == *"6hrP"* ]];then
            cdo -s -r  -seldate,$d1,$d2 $f $scratch/crop/$v.nc
        elif [[ $freq == *"6hrL"* ]];then
            cdo -s -r  -invertlev -seldate,$d1,$d2 $f $scratch/crop/$v.nc
        elif [[ $freq == *"mon"* ]];then
            for m in $mx; do
   				if [ $m -gt 12 ];then
	                f2=$storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$(($y1+1)).nc
	                if [ ! -f $f2 ];then
	                    cdo -s -r setday,1 -setyear,$(($y1+1)) -setmon,1 -settime,00:00 -selmon,12 $f $scratch/crop/$v.mon$m.nc
	                else
						m2=$(($m-12))
		                cdo -s -r setday,1 -settime,00:00 -selmon,$m2 $f2 $scratch/crop/$v.mon$m.nc
					fi
				else
			        cdo -s -r setday,1 -settime,00:00 -selmon,$m $f $scratch/crop/$v.mon$m.nc
			    fi
			done
            rm -f $scratch/crop/$v.day.foo.nc
            cdo -s -r cat $scratch/crop/$v.mon*.nc $scratch/crop/$v.foo.nc
            cdo -s -r  -seldate,$d1,$d2 -inttime,$d1,00:00,6hour $scratch/crop/$v.foo.nc $scratch/crop/$v.day.nc
        else
            cdo -s -r  -seldate,$d1,$d2 -inttime,$d1,00:00,6hour -seldate,$dx,$dy $f $scratch/crop/$v.day.nc
        fi
    done
else
# Per la resta de vars
	f=`ls $storage/files/${v}_*_${mdl}_${s}_${ens}_$y1.nc`
	freq=`echo $f | awk -F_ '{print $2}'`
    echo 'select ... '$v $freq

	if [ $(($y1+1)) -eq $y2 ] && [[ $freq != *"mon"* ]];then
		    cdo -s cat $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y1.nc $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y2.nc $scratch/crop/$v.cat.nc
		    f=$scratch/crop/$v.cat.nc
	fi

    if [[ $freq == *"6hr"* ]];then
        cdo -s -r -seldate,$d1,$d2 $f $scratch/crop/$v.nc
    elif [[ $freq == *"mon"* ]];then
        for m in $mx; do
		    if [ $m -gt 12 ];then
                f2=$storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$(($y1+1)).nc
	            if [ ! -f $f2 ];then
					cdo -s -r setday,1 -setyear,$(($y1+1)) -setmon,1 -settime,00:00 -selmon,12 $f $scratch/crop/$v.mon$m.nc
        	    else
            	    m2=$(($m-12))
                	cdo -s -r setday,1 -settime,00:00 -selmon,$m2 $f2 $scratch/crop/$v.mon$m.nc
	            fi
		    else
		        cdo -s -r setday,1 -settime,00:00 -selmon,$m $f $scratch/crop/$v.mon$m.nc
			 fi
		done
		rm -f $scratch/crop/$v.foo.nc
        cdo -s -r cat $scratch/crop/$v.mon*.nc $scratch/crop/$v.foo.nc
        cdo -s -r  -seldate,$d1,$d2 -inttime,$d1,00:00,6hour $scratch/crop/$v.foo.nc $scratch/crop/$v.day.nc
    else
        cdo -s -r  -seldate,$d1,$d2  -inttime,$d1,00:00,6hour -seldate,$dx,$dy $f $scratch/crop/$v.day.nc
    fi
    if [ $v == hus ] || [ $v == zg ];then
        cp $scratch/crop/$v.day.nc  $scratch/zinter/$v.nc
    fi
fi
done

# input.soil.grb
# mrlsl tsl

for v in mrlsl tsl ; do
	f=`ls $storage/files/${v}_*_${mdl}_${s}_${ens}_$y1.nc`
	freq=`echo $f | awk -F_ '{print $2}'`
    echo 'select ... '$v $freq

	if [ $(($y1+1)) -eq $y2 ] && [[ $freq != *"mon"* ]];then
	    cdo -s cat $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y1.nc $storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$y2.nc $scratch/crop/$v.cat.nc
	    f=$scratch/crop/$v.cat.nc
	fi

    if [[ $freq == *"6hr"* ]];then
        cdo -s -r -interpolate,$scratch/crop/ua.nc -seldate,$d1,$d2 $f $scratch/crop/$v.nc
    elif [[ $freq == *"mon"* ]];then
        for m in $mx; do
    		if [ $m -gt 12 ];then
		        f2=$storage/files/${v}_${freq}_${mdl}_${s}_${ens}_$(($y1+1)).nc
				if [ ! -f $f2 ];then
					cdo -s -r setday,1 -setyear,$(($y1+1)) -setmon,1 -settime,00:00 -selmon,12 $f $scratch/crop/$v.mon$m.nc
				else
		        	m2=$(($m-12))
		        	cdo -s -r setday,1 -settime,00:00 -selmon,$m2 $f2 $scratch/crop/$v.mon$m.nc
				fi
		    else
		        cdo -s -r setday,1 -settime,00:00 -selmon,$m $f $scratch/crop/$v.mon$m.nc
		    fi
		done
        rm -f $scratch/crop/$v.foo.nc
        cdo -s -r cat $scratch/crop/$v.mon*.nc $scratch/crop/$v.foo.nc
        cdo -s -r  -interpolate,$scratch/crop/ua.nc -seldate,$d1,$d2 -inttime,$d1,00:00,6hour $scratch/crop/$v.foo.nc $scratch/crop/$v.nc
    else
        cdo -s -r  -interpolate,$scratch/crop/ua.nc -seldate,$d1,$d2  -inttime,$d1,00:00,6hour -seldate,$dx,$dy $f $scratch/crop/$v.nc
    fi
done

# rebuild 

for v in ta ua va ;do
f=$scratch/crop/$v.nc
g=$scratch/crop/$v.day.nc
for l in 100000 85000 70000 50000 25000 10000 5000 1000;do
echo "rebuild level ..." $l "for" $v
if [ $l -ge 70000 ] ; then r=85000 ;fi
if [ $l -eq 50000 ] ; then r=50000 ;fi
if [ $l -le 25000 ] ; then r=25000 ;fi
lx=$(echo $l | awk '{printf "%06.0f", $1}')
cdo -s -r -setlevel,$l -add -sub -sellevel,$l $g -sellevel,$r $g -sellevel,$r $f $scratch/zinter/$v.$lx.nc
done
cdo -s -r merge $scratch/zinter/$v.*.nc $scratch/zinter/$v.foo.nc
cdo -s -r setmissval,1.0000e+20 $scratch/zinter/$v.foo.nc $scratch/zinter/$v.nc
done

## IF HIBRID LEVELS ---
#echo "Transforming hybrid levels to pressure levels"
## get ps
#px=$(cdo -s -r outputf,"%6.0f",1 -timmax -fldmax -selvar,ps $scratch/crop/ua.nc )
## hybrid levels
#echo "vct = " > $scratch/foo.a
#echo "0.0" >> $scratch/foo.a
#cdo -s -r outputf,%10.3f,2 -mulc,$px -selname,a_bnds $scratch/crop/ua.nc | awk '{print $1}' | tac >> $scratch/foo.a
##ncks -v a_bnds $scratch/crop/va.nc | awk '($2=="x[0]"){print $3}' | awk -F= '($2!=""){print $2*'$px'}'
#echo "0.0" > $scratch/foo.b
#cdo -s -r outputf,%10.3f,2  -selname,b_bnds $scratch/crop/ua.nc | awk '{print $1}'  | tac >> $scratch/foo.b
#nl=$(cdo -s nlevel -selvar,ua $scratch/crop/ua.nc)
#echo "zaxistype = hybrid
#size      = $nl
#levels    = $(seq -s" " 1 $nl )
#vctsize   = $[nl*2 +2]" > $scratch/tab/zaxisinvert
#cat $scratch/foo.a |tr '\n' ' ' >>  $scratch/tab/zaxisinvert
#cat $scratch/foo.b |tr '\n' ' ' >>  $scratch/tab/zaxisinvert
#
#export EXTRAPOLATE=1
#for v in ua va ;do
#echo "rebuild levels for" $v
#cdo -s -r setzaxis,$scratch/tab/zaxisinvert -selvar,$v,ps $scratch/crop/$v.nc $scratch/hlev/$v.hyb.nc
#cdo -s -r ml2pl,$plev $scratch/hlev/$v.hyb.nc $scratch/hlev/$v.prs.nc
#cdo -s -r  $scratch/hlev/$v.prs.nc $scratch/zinter/$v.nc
#done
## END --

v=hus
cp $scratch/crop/$v.day.nc  $scratch/zinter/$v.nc
v=zg
cp $scratch/crop/$v.day.nc  $scratch/zinter/$v.nc

#rm -f $scratch/crop/*.mon*.nc $scratch/crop/*.foo.nc $scratch/zinter/*.foo.nc 

fi

#####################################

if [ $step -eq 2 ] ; then
echo '## STEP 2 ##'

## ta hus ua va zg
for v in ta hus ua va zg;do
echo "interpolating ... "  $v
cdo -s -r -sellevel,$plev -intlevel,$plev $scratch/zinter/$v.nc $scratch/ready/$v.nc
done

nl=$(cdo -s -r -nlevel -selvar,ta $scratch/ready/ta.nc)
echo "zaxistype = pressure
size      = $nl
name      = lev
longname  = pressure
units     = hPa
levels    = $(echo $plev2 | sed 's/,/ /g')
" > $scratch/tab/paxis

## ta hus ua va zg
for v in ta hus ua va zg;do
echo "nc to grib ... " $v
prm=$(grep -w $v param.tab | awk '{print $2}')
typ=$(grep -w $v param.tab | awk '{print $3}')
cdo -s -r -f grb -setzaxis,$scratch/tab/paxis -setltype,$typ -chparam,-1,$prm -selvar,$v $scratch/ready/$v.nc $scratch/grb/$v.grb
done


echo "merge ... 3D"
cdo -s -r -merge $scratch/grb/ta.grb $scratch/grb/hus.grb $scratch/grb/ua.grb $scratch/grb/va.grb $scratch/grb/zg.grb $scratch/merge/input.3d.grb

fi

#############################################

if [ $step -eq 3 ] ; then
echo '## STEP 3 ##'

echo "doing near surface ...."

## huss tas uas vas
for v in huss tas uas vas ;do
if [ "$v" == "huss" ] ; then h=2 ; fi
if [ "$v" == "tas" ] ; then h=2 ; fi
if [ "$v" == "uas" ] ; then h=10 ; fi
if [ "$v" == "vas" ] ; then h=10 ; fi
echo "... " $v
echo "zaxistype = height
    size      = 1
    levels    = $h" > $scratch/tab/zaxis2m

prm=$(grep -w $v param.tab | awk '{print $2}')
typ=$(grep -w $v param.tab | awk '{print $3}')
cdo -s -r -f grb -setzaxis,$scratch/tab/zaxis2m -setltype,$typ -chparam,-1,$prm -selname,$v $scratch/crop/$v.nc $scratch/grb/$v.grb
done

for v in psl ps ;do
echo "... " $v
prm=$(grep -w $v param.tab | awk '{print $2}')
typ=$(grep -w $v param.tab | awk '{print $3}')
cdo -s -r -f grb setltype,$typ -chparam,-1,$prm -selname,$v $scratch/crop/$v.nc $scratch/grb/$v.grb
done

echo "... tos"
cdo -s -r min $scratch/crop/$tslsi.nc $scratch/crop/tos.nc $scratch/crop/tsk.nc
cdo -s -r -f grb -setltype,1 -chparam,-1,11 $scratch/crop/tsk.nc $scratch/grb/tsk.grb

echo "merging near surface ..."
cdo -s -r merge $scratch/grb/tsk.grb $scratch/grb/huss.grb $scratch/grb/uas.grb $scratch/grb/vas.grb $scratch/grb/tas.grb $scratch/grb/psl.grb $scratch/grb/ps.grb $scratch/merge/input.sfc.grb

fi

#############################################

if [ $step -eq 4 ] ; then
echo '## STEP 4 ##'

echo "preparing soil temperature and moisture ..."

cdo -s -r -intlevel,0.05,0.25,1,2 $scratch/crop/mrlsl.nc $scratch/zinter/soilm.nc

for l in 1 2 3 4 ;do
if [ $l -eq 1 ] ; then a=0 ; b=5 ; c=0.05 ; fi
if [ $l -eq 2 ] ; then a=5 ; b=25 ; c=0.005 ; fi
if [ $l -eq 3 ] ; then a=25 ; b=100 ; c=0.0013 ; fi
if [ $l -eq 4 ] ; then a=100 ; b=200 ; c=0.001 ; fi
echo "zaxistype = depth_below_land
size      = 1
name      = depth
longname  = depth_below_land
units     = cm
lbounds    = $a
ubounds    = $b" > $scratch/tab/soilzaixis
cdo -s -r -f grb -setzaxis,$scratch/tab/soilzaixis -setltype,112 -chparam,-1,144 -mulc,$c -sellevidx,$l $scratch/zinter/soilm.nc  $scratch/grb/soilm.$l.grb
cdo -s -r -f grb -setzaxis,$scratch/tab/soilzaixis -setltype,112 -chparam,-1,11  -sellevidx,$l $scratch/crop/tsl.nc  $scratch/grb/soilt.$l.grb
done

echo "merging soil variables ..."
cdo -s -r merge $scratch/grb/soil*.*.grb $scratch/merge/input.soil.grb

fi

#############################################

if [ $step -eq 5 ] ; then
echo '## STEP 5 ##'

echo "preparing land-sea mask ..."
v=sftlf
f=$scratch/crop/tos.nc
prm=$(grep -w $v param.tab | awk '{print $2}')
typ=$(grep -w $v param.tab | awk '{print $3}')
cdo -s -r -eqc,0  -setmisstoc,0 $f $scratch/crop/lsmask.nc
cdo -s -r -f grb -setltype,$typ -chparam,-1,$prm $scratch/crop/lsmask.nc $scratch/merge/lsmask.grb

fi

#############################################

if [ $step -eq 6 ] ; then
echo '## STEP 6 ##'

echo "merge .... all"

# Shifttime when rcpXX
if [[ $s == *"rcp"* ]];then
    d0=`date +%Y-%m-%d -d "$d1 -100 year"`
else
    d0=$d1
fi

cdo -s -r merge $scratch/merge/*.grb $scratch/merge/all.grb
cdo1 -s settaxis,$d0,00:00,6hour $scratch/merge/all.grb $storage/out/wrfinput/$mdl.$s.$dtx.grb

echo "DONE ... $mdl.$s.$dtx.grb"

rm -r $scratch
fi

done


