mkdir /tmp/parasite-release
cd /tmp/parasite-release

# Dump all the databases into the tmp space
echo "Dumping and loading databases"
databaselist=$($PARASITE_STAGING_MYSQL -e 'SHOW DATABASES LIKE "%_core%_'${ENSEMBL_VERSION}'_%"')
databases=( `echo ${databaselist}` ensembl_compara_parasite_${PARASITE_VERSION}_${ENSEMBL_VERSION} ensembl_ontology_${ENSEMBL_VERSION} ensembl_website_${ENSEMBL_VERSION} ensemblgenomes_info_${EG_VERSION} ensemblgenomes_stable_ids_${PARASITE_VERSION}_${ENSEMBL_VERSION} )
for DB in "${databases[@]}"
do
  echo $DB
  $PARASITE_STAGING_MYSQL mysqldump $DB > $DB.sql
  mysql-ps-rel-ensrw -e "CREATE DATABASE $DB"
  mysql-ps-rel-ensrw $DB < $DB.sql
  mysql-ps-rel-ensrw mysqlcheck -o $DB
  mysql-ps-rest-rel-ensrw -e "CREATE DATABASE $DB"
  mysql-ps-rest-rel-ensrw $DB < $DB.sql
  mysql-ps-rest-rel-ensrw mysqlcheck -o $DB
  mysql-ps-intrel-ensrw -e "CREATE DATABASE $DB"
  mysql-ps-intrel-ensrw $DB < $DB.sql
  mysql-ps-intrel-ensrw mysqlcheck -o $DB
done

# Compress the archive then push to the EBI Archive Freezer
echo "Creating release archive for the EBI Freezer"
tar -zcvf release-${PARASITE_VERSION}.tar.gz *.sql
rm *.sql
ear-put release-${PARASITE_VERSION}.tar.gz
