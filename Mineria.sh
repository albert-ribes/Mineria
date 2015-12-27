#!/bin/bash
Date=`date +%Y%m%d%H%M%S`
BackupPath="/media/sf_Mineria"

VerifyIncomingParams(){
	if [ "$1" == "" ]
	then
		echo "ERROR: You must use $0 project_name"
		exit 1
	else
		project="$1"
		if [ ! -d $project ]
		then
			mkdir $project
		fi
		return=`mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME=\"$project\""|grep $project|wc -l`
		if [ "$return" == "0" ]
		then
			echo ERROR: Unable to find $project database to operate with. Generate it? \[y/n\]
			read answer
			if [ "$answer" == "y" ]
			then
				cat <<EOF > $project/mysql.db
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";
CREATE DATABASE IF NOT EXISTS DummyName DEFAULT CHARACTER SET latin1 COLLATE latin1_spanish_ci;
USE DummyName;
CREATE TABLE GoogleInfo (
IdUnic int(11) NOT NULL,
  GoogleKey tinytext COLLATE latin1_spanish_ci NOT NULL
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=latin1 COLLATE=latin1_spanish_ci;
CREATE TABLE Positions (
IdUnic int(11) NOT NULL,
  GoogleKeyIdUnic int(11) NOT NULL,
  Location point NOT NULL
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=latin1 COLLATE=latin1_spanish_ci;
ALTER TABLE GoogleInfo
 ADD PRIMARY KEY (IdUnic), ADD KEY GoogleKey (IdUnic,GoogleKey(25));
ALTER TABLE Positions
 ADD PRIMARY KEY (IdUnic), ADD SPATIAL KEY Location (Location), ADD KEY GoogleKeyIdUnic (GoogleKeyIdUnic,IdUnic);
ALTER TABLE GoogleInfo
MODIFY IdUnic int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=1;
ALTER TABLE Positions
MODIFY IdUnic int(11) NOT NULL AUTO_INCREMENT,AUTO_INCREMENT=1;
EOF
				sed "s/DummyName/$project/" < $project/mysql.db > $project/mysql.db2
				rm -f $project/mysql.db
				mysql < $project/mysql.db2
				if [ "$?" -eq "0" ]
				then
					rm -f $project/mysql.db2
					InteractiveMenu
				else
					rm -f $project/mysql.db2
					echo ERROR: Unable to create $project database. Sorry.
				fi
			fi
			exit 1
		else
			InteractiveMenu
		fi
	fi

}

InteractiveMenu(){
	while true
	do
	clear
	echo "----------------------------------------------"
	echo " * * * * * * * Main Menu * * * * * * * * * * "
	echo "----------------------------------------------"
	echo "[1]Download kmz searching by word in googlemaps"
	echo "[z]Download kmz & kml searching by word in google"
	echo "	[1a]Delete downloads with 0 coords"
	echo "	[1b]Get the list of allready searched words"
	echo "	[1c]Redownload all searched words"
	echo "[2]Generate MySql insert code"
	echo "	[2a]Get some statistics about it"
	echo "[3]Insert MySql generated codes"
	echo "	[3a]Verify and move downloaded and inserted data to data-done"
	echo "	[3b]Verify data-done folders are clean"
	echo "	[3c]Verify data-done folders contain valid info"
	echo "	[3d]Remove from database GoogleKeys with mysql.code in dir"
	echo "[a]Make MySql Backup"
	echo "[b]Make data's filesystem backup"
	echo "[0]Exit"
	printf "Enter your menu choice:"
	read yourch
	case $yourch in
		1)
			DownloadByWordGoogleMaps
			;;
		z)
			DownloadByWordGoogle
			;;
			1a)
				Delete0CoordsDirs
				;;
			1b)
				ListSearchedWords
				;;
			1c)
				RedownloadSearchedWords
				;;
		2)
			MySqlGenerate
			;;
			2a)
				MySqlGenerateStats
				;;
		3)
			MySqlInsert
			;;
			3a)
				VerifyMysqlInsertDown
				;;
			3b)
				DataDoneFolderVerify
				;;
			3c)
				DataDoneInfoVerify
				;;
			3d)
				MysqlPurgeIfMysqlCode
				;;
		a)
			MySqlBackup
			;;
		b)
			DataFileSystemBackup
			;;
		0)
			exit 0
		;;
		*)
			echo "Opps!!! Please select choice 1,1a,1b,...,2,2a,...3,... or 0"
			echo "Press a key. . ." `pwd`
			read -n 1
			;;
	esac
	done
}

DownloadByWordGoogleMaps(){
	clear
	#User must provide a search word
	if [ "$1" == "" ]
	then
		echo "Enter your search word:"
		echo "[or full path to a file with words]"
		read search_word
		if [ -f "$search_word" ]
		then
			for word in `cat $search_word`
			do
				DownloadByWordGoogleMaps $word
			done
		else
			DownloadByWordGoogleMaps $search_word
		fi
	else
		search_word="$1"
		if [ ! -d $project/data ]
		then
			mkdir -p $project/data
		fi
		cd $project/data
		#Just download all the results.
		echo Downloading all maps list with the key search \"$search_word\" ...
		curl --connect-timeout 5 --max-time 20 -s -# -L -A "Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3" -o zz_page.html "https://maps.google.com/gallery/search?hl=ca&q=$search_word"
		#Verify we downloaded somethig
		if [ ! -f zz_page.html ]
		then
			echo ERROR: Unable to download all maps list.|tee -a ../DownloadByWordGoogleMaps.log
		fi
		#From the all maps list, get the urls for the different galleryes
		cat zz_page.html|tr "<" "\n"|grep 'href="/gallery/details'|cut -f4 -d"\""|sed 's/\&amp\;/\&/gI'|sed 's/\/gallery/https\:\/\/maps.google.com\/gallery/gI'>zz_urls.list
		urls_count=`cat zz_urls.list|wc -l`
		#For each url we are going to download the kmz file
		names_count_temp=0
		for line in `cat zz_urls.list`
		do
			unicid=`echo $line|cut -f5 -d"/"|cut -f2 -d"="|cut -f1 -d"&"`
			names_count_temp=`echo $[$names_count_temp+1]`
			if [[ -d $unicid || -d ../data-done/$unicid ]]
			then
				echo \[$names_count_temp\/$urls_count] $unicid allready downloaded
			else
				mkdir $unicid
				cd $unicid
				touch $search_word.search
				echo \[$names_count_temp\/$urls_count] Downloading $unicid gallery ...
				curl --connect-timeout 5 --max-time 20 -s -# -L -A "Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3" -o down.kmz "https://www.google.com/maps/d/kml?mid=$unicid"
				if [ ! -f down.kmz ]
				then
					echo \[$names_count_temp\/$urls_count] ERROR: $unicid gallery didnt downloaded fine, deleting it. Retry later.|tee -a ../../DownloadByWordGoogleMaps.log
					rm -f *.search
					cd ..
					rmdir $unicid
				else
					cd ..
				fi
			fi
		done
		find -maxdepth 1 -type f -name 'zz_*' -exec rm -f {} \;
		cd ../..
	fi
}

DownloadByWordGoogle(){
	clear
	#User must provide a search word
	if [ "$1" == "" ]
	then
		echo "Enter your search word:"
		echo "[or full path to a file with words]"
		read search_word
		if [ -f "$search_word" ]
		then
			for word in `cat $search_word`
			do
				DownloadByWordGoogle $word
			done
		else
			DownloadByWordGoogle $search_word
		fi
	else
		search_word="$1"
		if [ ! -d $project/data ]
		then
			mkdir -p $project/data
		fi
		cd $project/data
		#Just download all the results.
		results=1
		start=0
		while [ "$results" -ne "0" ]
		do
			echo Downloading kmz page for search \"$search_word\" start = $start ...
			echo "https://www.google.es/search?q=$search_word+filetype:kmz#q=urbex+filetype:kmz&start=$start"
			curl --connect-timeout 5 --max-time 20 -s -# -L -A "Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3" -o zz_page.html "https://www.google.es/search?q=$search_word+filetype:kmz&start=$start"
			#Verify we downloaded somethig
			if [ ! -f zz_page.html ]
			then
				echo ERROR: Unable to download kmz main page|tee -a ../DownloadByWordGoogle.log
				result=0
			else
				#get the urls for the different kmz
				cat zz_page.html|tr " " "\n"|grep 'href="/url?q='|grep -v 'webcache.googleusercontent.com/search'|cut -f3 -d"="|sed "s/\&amp\;sa//">DownloadByWordGoogle.list
				urls_count=`cat DownloadByWordGoogle.list|wc -l`
				#For each url we are going to download the kmz file
				names_count_temp=0
				for line in `cat DownloadByWordGoogle.list`
				do
					unicid=`echo $line|md5sum|cut -f1 -d" "`
					names_count_temp=`echo $[$names_count_temp+1]`
					if [[ -d $unicid || -d ../data-done/$unicid ]]
					then
						echo \[$names_count_temp\/$urls_count] $unicid allready downloaded
					else
						mkdir $unicid
						cd $unicid
						echo DownloadByWordGoogle $start > $search_word.search
						echo \[$names_count_temp\/$urls_count] Downloading $unicid gallery ...
						curl --connect-timeout 5 --max-time 20 -s -# -L -A "Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3" -o down.kmz $line
						if [ ! -f down.kmz ]
						then
							echo \[$names_count_temp\/$urls_count] ERROR: $unicid gallery didnt downloaded fine, deleting it|tee -a ../../DownloadByWordGoogle.log
							rm -f *.search
							cd ..
							rmdir $unicid
						else
							cd ..
						fi
					fi
				done
				rm -f DownloadByWordGoogle.list
				if [ "$urls_count" -ne "10" ]
				then
					echo ERROR: google search for $search_word dint return 10.
					results=0
				fi		
			fi
			start=$(($start+10))
		done
		cd ../..
	fi
}

Delete0CoordsDirs(){
	clear
	cd $project/data
	#For each GoogleKey (folder) have a look and delete if 0 coords found
	ls -la|grep ^d|tr -s " "|cut -f9 -d" "|grep [a-z]>zz_unicid.list
	names_count=`wc -l zz_unicid.list|cut -f1 -d" "`
	folders_count_temp=0
	for GoogleKey in `cat zz_unicid.list`
	do
		folders_count_temp=`echo $[$folders_count_temp+1]`
		deleteme=0
		if [ -d $GoogleKey ]
		then
			cd $GoogleKey
			if [ ! -f down.kmz ]
			then
				echo \[$folders_count_temp\/$names_count] No down.kmz file in $GoogleKey, deleting it|tee -a ../../Delete0CoordsDirs.log
				deleteme=1
			else
				#Getting coords from doc.kml and storing in zz_coords.list
				exec 2<&-
				zcat down.kmz|grep '<coordinates>'|cut -f2 -d">"|cut -f1 -d"<"|tr " " "\n">zz_coords.list 2>/dev/null
				coords_num=`cat zz_coords.list|wc -l`
				if [ "$coords_num" -eq "0" ]
				then
					echo \[$folders_count_temp\/$names_count] 0 coords found in $GoogleKey, deleting it|tee -a ../../Delete0CoordsDirs.log
					deleteme=1
				else
					echo \[$folders_count_temp\/$names_count] OK $GoogleKey
				fi
				#rm -f zz_coords.list
				if [ -d images ]
				then
					rm -rf images
				fi
			fi
			cd ..
			if [ "$deleteme" -eq "1" ]
			then
				echo DELETE $GoogleKey
				rm -rf $GoogleKey
				deleteme=0
			fi
		else
			echo $GoogleKey dissapeared \[$folders_count_temp\/$names_count]
		fi
	done
	cd ../..
}

ListSearchedWords(){
	clear
	cd $project/data
	find -name *.search|cut -f3 -d"/"|sort|uniq|cut -f1 -d"." > ../zz_ListSearchedWords.log
	if [ -d ../data-done ]
	then
		cd ../data-done
		find -name *.search|cut -f3 -d"/"|sort|uniq|cut -f1 -d"." >> ../zz_ListSearchedWords.log
		cd ..
	fi
	cat zz_ListSearchedWords.log|sort|uniq>ListSearchedWords.log
	rm -f zz_ListSearchedWords.log
	more ListSearchedWords.log
	echo "Press a key. . ."
	read
	cd ..
}

RedownloadSearchedWords(){
	clear
	cd $project/data
	find -name *.search|cut -f3 -d"/"|sort|uniq|cut -f1 -d"." > ../zz_ListSearchedWords.log
	if [ -d ../data-done ]
	then
		cd ../data-done
		find -name *.search|cut -f3 -d"/"|sort|uniq|cut -f1 -d"." >> ../zz_ListSearchedWords.log
		cd ..
	fi
	cat zz_ListSearchedWords.log|sort|uniq>ListSearchedWords.log
	rm -f zz_ListSearchedWords.log
	cd ..
	for word in `cat $project/ListSearchedWords.log`
	do
		DownloadByWordGoogleMaps $word
	done
}

MySqlGenerate(){
	clear
	cd $project/data
	#For each GoogleKey (folder) have a look and generate if necessary the mysql code.
	ls -la|grep ^d|tr -s " "|cut -f9 -d" "|grep [a-z]>zz_unicid.list
	names_count=`wc -l zz_unicid.list|cut -f1 -d" "`
	folders_count_temp=0
	for GoogleKey in `cat zz_unicid.list`
	do
		folders_count_temp=`echo $[$folders_count_temp+1]`
		if [ -d $GoogleKey ]
		then
			cd $GoogleKey
			if [[ -f mysql.code || -f mysql.inserted.gz ]]
			then
				echo $GoogleKey allready has its mysql code \[$folders_count_temp\/$names_count]
			else
				if [ ! -f down.kmz ]
				then
					echo \[$folders_count_temp\/$names_count] ERROR: $GoogleKey Unable to find down.kmz file in directory|tee -a ../../MySqlGenerate.log
				else
					#Getting coords from doc.kml and storing in zz_coords.list
					exec 2<&-
					zcat down.kmz|grep '<coordinates>'|cut -f2 -d">"|cut -f1 -d"<"|tr " " "\n">zz_coords.list
					coords_num=`cat zz_coords.list|wc -l`
					if [ "$coords_num" -ne "0" ]
					then
						echo \[$folders_count_temp\/$names_count] Generating $GoogleKey mysql code with $coords_num inserts
						echo INSERT INTO GoogleInfo \(IdUnic, GoogleKey\) VALUES \(NULL, \"$GoogleKey\"\)\; > mysql.code
						echo INSERT INTO Positions \(GoogleKeyIdUnic,Location\) VALUES >> mysql.code
						coord_count=0;
						for coord in `cat zz_coords.list` 
						do
							echo \(\(SELECT IdUnic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"\), GeomFromText\(\'POINT\(`echo $coord|cut -f1 -d","` `echo $coord|cut -f2 -d","`\)\'\)\), >> mysql.code
							printf .
							coord_count=`echo $[$coord_count+1]`
							if [ $coord_count -eq "1000" ]
							then
								echo \(0, GeomFromText\(\'POINT\(0 0\)\'\)\)\; >> mysql.code
								echo INSERT INTO Positions \(GoogleKeyIdUnic,Location\) VALUES >> mysql.code
								coord_count=0;
							fi
						done
						printf "\n"
						echo \(0, GeomFromText\(\'POINT\(0 0\)\'\)\)\; >> mysql.code
					else
						echo ERROR: $GoogleKey 0 coords found in directory|tee -a ../../MySqlGenerate.log
					fi
					rm -f zz_coords.list
					if [ -d images ]
					then
						rm -rf images
					fi
				fi
			fi
			cd ..
		else
			echo $GoogleKey dissapeared \[$folders_count_temp\/$names_count]
		fi
	done
	rm zz_unicid.list
	cd ../..
}

MySqlGenerateStats(){
	clear
	cd $project
	secs=`date +%s`
	total=`ls -la data/|wc -l`
	done=`find data/ -name mysql.code|wc -l`
	echo $secs $total $done >> MySqlGenerateStats.stats
	counter=2
	while [ "$counter" -ne "0" ]
	do
		if [ "$counter" == "1" ]
		then
			line=`tail -1 MySqlGenerateStats.stats`
			secs_end=`echo $line|cut -f1 -d" "`
			total_end=`echo $line|cut -f2 -d" "`
			done_end=`echo $line|cut -f3 -d" "`
			secs=`echo $[$secs_end-$secs_begin]`
			done=`echo $[$done_end-$done_begin]`
			total=`echo $[$total_end-$done_end]`
			ETA=`echo $[$total/$done*secs]`
			if [ "$secs" -ge 60 ]
			then
				mins=`echo "scale=0;$secs/60"|bc`
				secs=`echo "scale=0;$secs-$mins*60"|bc`
				if [ "$mins" -ge 60 ]
				then
					hours=`echo "scale=0;$mins/60"|bc`
					mins=`echo "scale=0;$mins-$hours*60"|bc`
					if [ "$hours" -ge 24 ]
					then
						days=`echo "scale=0;$hours/24"|bc`
						hours=`echo "scale=0;$hours-$days*24"|bc`
					else
						days="0"
					fi
				else
					hours="0"
					days="0"
				fi
			else
				mins="0"
				hours="0"
				days="0"
			fi
			echo $done done in $days days, $hours hours, $mins mins, $secs seconds, $total remaining.
			secs=$ETA
			if [ "$secs" -ge 60 ]
			then
				mins=`echo "scale=0;$secs/60"|bc`
				secs=`echo "scale=0;$secs-$mins*60"|bc`
				if [ "$mins" -ge 60 ]
				then
					hours=`echo "scale=0;$mins/60"|bc`
					mins=`echo "scale=0;$mins-$hours*60"|bc`
					if [ "$hours" -ge 24 ]
					then
						days=`echo "scale=0;$hours/24"|bc`
						hours=`echo "scale=0;$hours-$days*24"|bc`
					else
						days="0"
					fi
				else
					hours="0"
					days="0"
				fi
			else
				mins="0"
				hours="0"
				days="0"
			fi
			echo ETA: $days days, $hours hours, $mins mins, $secs seconds
			counter=0
		fi
		if [ "$counter" == "2" ]
		then
			line=`head -1 MySqlGenerateStats.stats`
			secs_begin=`echo $line|cut -f1 -d" "`
			total_begin=`echo $line|cut -f2 -d" "`
			done_begin=`echo $line|cut -f3 -d" "`
			counter=1
		fi
	done
	read 
	cd ..
}

MySqlInsert(){
	clear
	cd $project/data
	mysql_count_temp=0
	mysql_count=`find -maxdepth 2 -type f -name 'mysql.code'|wc -l`
	for file in `find -maxdepth 2 -type f -name 'mysql.code'`
	do
		mysql_count_temp=`echo $[$mysql_count_temp+1]`
		GoogleKey=`echo $file|cut -f2 -d"/"`
		return=`mysql -h 127.0.0.1 -u root -e "SELECT idunic FROM GoogleInfo WHERE GoogleKey = \"$GoogleKey\"" $project|head -4|tail -1|tr -s " "|cut -f2 -d" "`
		if [ "$return" != "" ]
		then
			echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey is allready in the database|tee -a ../MySqlInsert.log
		else
			echo \[$mysql_count_temp/$mysql_count\] Inserting $GoogleKey ...
			mysql -h 127.0.0.1 -u root $project < $file
			if [ "$?" -eq "0" ]
			then
				mv $file $GoogleKey/mysql.inserted
				gzip $GoogleKey/mysql.inserted
			else
				echo ERROR: $GoogleKey Something went wrong with this insert|tee -a ../MySqlInsert.log
			fi
		fi
	done
	cd ../..
}

VerifyMysqlInsertDown(){
	clear
	cd $project/data
	if [ ! -d ../data-done ]
	then
		mkdir ../data-done
	fi
	mysql_count_temp=0
	mysql_count=`find -maxdepth 2 -type f -name 'mysql.inserted.gz'|wc -l`
	for file in `find -maxdepth 2 -type f -name 'mysql.inserted.gz'`
	do
		mysql_count_temp=`echo $[$mysql_count_temp+1]`
		GoogleKey=`echo $file|cut -f2 -d"/"`
		printf .
		value1=`mysql -h 127.0.0.1 -u root -e "SELECT COUNT(*) FROM Positions WHERE GoogleKeyIdUnic=(SELECT idunic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\")" $project|head -4|tail -1|tr -s " "|cut -f2 -d" "`
		if [ "$value1" != "" ]
		then
			printf .
			value2=`zcat $GoogleKey/mysql.inserted.gz|grep "POINT"|grep -v 'POINT(0 0)'|wc -l`
			if [ $value1 -ne $value2 ]
			then
				echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey, has $value1 in database and $value2 in mysql.inserted.gz|tee -a ../VerifyMysqlInsertDown.log
			else
				printf .
				exec 2<&-
				value3=`zcat $GoogleKey/down.kmz|grep '<coordinates>'|cut -f2 -d">"|cut -f1 -d"<"|tr " " "\n"|wc -l`
				if [ $value2 -ne $value3 ]
				then
					echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey, has $value1 and $value2 in mysql.inserted.gz, different from $value3 in down.kmz.|tee -a ../VerifyMysqlInsertDown.log
				else
					mv $GoogleKey ../data-done/.
					echo \[$mysql_count_temp/$mysql_count\] OK $GoogleKey $value1 $value2 $value3
				fi
			fi
		else
			echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey is not even in the database.|tee -a ../VerifyMysqlInsertDown.log
		fi
	done
	cd ../..
}

DataDoneFolderVerify(){
	cd $project/data-done
	ls -la|grep ^d|tr -s " "|cut -f9 -d" "|grep [a-z]>zz_unicid.list
	names_count=`wc -l zz_unicid.list|cut -f1 -d" "`
	folders_count_temp=0
	for GoogleKey in `cat zz_unicid.list`
	do
		folders_count_temp=`echo $[$folders_count_temp+1]`
		extrafiles=`ls $GoogleKey|grep -v down.kmz|grep -v mysql.inserted.gz|grep -v .search|wc -l`
		if [ "$extrafiles" -eq "0" ]
		then
			echo \[$folders_count_temp\/$names_count] OK $GoogleKey
		else
			echo \[$folders_count_temp\/$names_count] ERROR: $GoogleKey has $extrafiles extra files|tee -a ../DataDoneFolderVerify.log
		fi
	done
	rm -f zz_unicid.list
	cd ../..
}

DataDoneInfoVerify(){
	#It verifyes that all the GoogleKey that have its mysql.inserted.gz file (and are supposed to be loaded in the database)
	#have the same number of registryes in the database than in the mysql.innserted file
	#After that also verifyes that down.kmz is also with the same values.
	cd $project/data-done
	mysql_count_temp=0
	mysql_count=`find . -name mysql.inserted.gz|wc -l`
	for file in `find . -name mysql.inserted.gz`
	do
		mysql_count_temp=`echo $[$mysql_count_temp+1]`
		GoogleKey=`echo $file|cut -f2 -d"/"`
		value1=`mysql -e "SELECT COUNT(*) FROM Positions WHERE GoogleKeyIdUnic=(SELECT idunic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\")" $project|grep [0-9]`
		if [ "$value1" != "" ]
		then
			value2=`zcat $GoogleKey/mysql.inserted.gz|grep "POINT"|grep -v 'POINT(0 0)'|wc -l`
			if [ $value1 -ne $value2 ]
			then
				echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey, has $value1 in database and $value2 in mysql.inserted.gz|tee -a ../DataDoneInfoVerify.log
			else
				exec 2<&-
				value3=`zcat $GoogleKey/down.kmz|grep '<coordinates>'|cut -f2 -d">"|cut -f1 -d"<"|tr " " "\n"|wc -l`
				if [ $value2 -ne $value3 ]
				then
						echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey, has $value1 and $value2 in mysql.inserted.gz, different from $value3 in down.kmz|tee -a ../DataDoneInfoVerify.log
				else
						echo \[$mysql_count_temp/$mysql_count\] OK $GoogleKey $value1 $value2 $value3
				fi
			fi
		else
			echo \[$mysql_count_temp/$mysql_count\] ERROR: $GoogleKey is not even in the database|tee -a ../DataDoneInfoVerify.log
		fi
	done
	cd ../..
}

MysqlPurgeIfMysqlCode(){
clear
	cd $project/data
	mysql_count_temp=0
	mysql_count=`find -maxdepth 2 -type f -name 'mysql.code'|wc -l`
	for file in `find -maxdepth 2 -type f -name 'mysql.code'`
	do
		mysql_count_temp=`echo $[$mysql_count_temp+1]`
		GoogleKey=`echo $file|cut -f2 -d"/"`
		return=`mysql -e "SELECT idunic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"" $project|grep [0-9]`
		if [ "$return" != "" ]
		then
			value1=0
			echo \#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#
			echo mysql -e "SELECT IdUnic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"" $project
			echo `mysql -e "SELECT IdUnic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"" $project|grep [0-9]`
			for IdUnic in `mysql -e "SELECT IdUnic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"" $project|grep [0-9]`
			do
				echo mysql -e "SELECT COUNT(*) FROM Positions WHERE GoogleKeyIdUnic=\"$IdUnic\"" $project
				value1=$(($value1+`mysql -e "SELECT COUNT(*) FROM Positions WHERE GoogleKeyIdUnic=\"$IdUnic\"" $project|grep [0-9]`))
			done
			exec 2<&-
			value2=`zcat $GoogleKey/down.kmz|grep '<coordinates>'|cut -f2 -d">"|cut -f1 -d"<"|tr " " "\n"|wc -l`
			echo $value1 in mysql and $value2 in down.mkz. Delete in database? \[y/n\]
			read return
			if [ "$return" == "y" ]
			then
				DeleteMysqlGoogleKey $GoogleKey
			fi
		fi
	done
}

DeleteMysqlGoogleKey(){
	GoogleKey=$1
	echo \ \ \ \ \ Generating delete code for $GoogleKey ...
	if [ -f zz_purge.sql ]
	then
		rm -f zz_purge.sql
	fi
	for IdUnic in `mysql -e "SELECT IdUnic FROM GoogleInfo WHERE GoogleKey=\"$GoogleKey\"" $project|grep [0-9]`
	do
		echo DELETE FROM Positions WHERE GoogleKeyIdUnic=$IdUnic\;>>zz_purge.sql
		echo DELETE FROM GoogleInfo WHERE IdUnic=$IdUnic\;>>zz_purge.sql
	done
	mysql $project<zz_purge.sql
	rm -f zz_purge.sql
}

MySqlBackup(){
	mysqldump $project|bzip2>$BackupPath/$project/backups/Mysql-`date +%Y_%m_%d`.sql.bz2
	read
}

DataFileSystemBackup(){
	cd $project
	tar cvfj $BackupPath/$project/backups/Data-`date +%Y_%m_%d`.tar.bz2 *
	cd ..
}

VerifyIncomingParams $1