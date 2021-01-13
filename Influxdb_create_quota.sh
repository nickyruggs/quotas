#!/bin/bash
#
#
#
#isilon IP address
#
isi_ip=10.231.153.162
#
# Influxdb IP
#
inf_ip=127.0.0.1
#
##### get the cluster name
#
name=$(curl -X GET "https://$isi_ip:8080/platform/5/cluster/identity" --insecure --basic --user pmon:emc | jq -r '.name' )
echo "Isilon cluster is called: $name"
#
curl -i -XPOST http://$inf_ip:8086/query --data-urlencode "q=DROP DATABASE quota_reports "
#
#  First create a databse to load the quota info into
#
curl -i -XPOST http://$inf_ip:8086/query --data-urlencode "q=CREATE DATABASE quota_reports --precision=ms"
#
#
#
curl -i -XPOST http://$inf_ip:8086/query?pretty=true --data-urlencode "q=SHOW DATABASES"

curl -X GET "https://$isi_ip:8080/platform/1/quota/reports?type=detail" --insecure --basic --user pmon:emc | jq -r '.reports[]  | {reportid: .id, time: .time, type: .type, gen: .generated} | select(.reportid and .time and .type and .gen) | .reportid as $id | .type as $typ | .gen as $gen|(.time )  | "report,cluster='$name',type=\($typ),origin=\($gen) rptid=\"\($id)\" \(.*1000000000)" ' > insert_report.ddl


curl -i -X POST "http://$inf_ip:8086/write?db=quota_reports" --data-binary @insert_report.ddl
#
# get all the quota reports of type detail
#
IDS=($(curl -X GET "https://$isi_ip:8080/platform/1/quota/reports?type=detail" --insecure --basic --user pmon:emc | jq -r ".reports[] | .id |@sh"))
#
#  get the times for each report
#
TIMES=($(curl -X GET "https://$isi_ip:8080/platform/1/quota/reports?type=detail" --insecure --basic --user pmon:emc | jq -r ".reports[] | .time |@sh"))
#
#   directory mask == ignore this directory
#
dir_mask="/ifs/nr-hdp.oriig"
#
# For each quota report retieved, create a quota record for each quota in the report and tie the time from the report to each quota.
#
counter=0
for id in "${IDS[@]}" 
  do
  echo "This is the $id report @ time ${TIMES[$counter]}"
  declare -i time=${TIMES[$counter]}*1000000000
  curl "https://$isi_ip:8080/platform/7/quota/quotas?$id" --insecure --basic --user pmon:emc | jq -r '.quotas[] | {quotaid: .id, path: .path, qtype: .type, persona: .persona.id, advise: .thresholds.advisory, hard: .thresholds.hard, soft: .thresholds.soft, applog: .usage.applogical, fslog: .usage.fslogical, phys: .usage.physical } | select (.quotaid and .qtype) | .quotaid as $quotaid | .qtype as $qtype | .path as $path|select ( .path != "'$dir_mask'" )  | .persona as $persona| .advise as $adv | .soft as $soft| .hard as  $hard |  .applog as $applog| .fslog as $fslog| .phys as $phys |"quota,cluster='$name',quotatype=\($qtype),path=\"\($path)\",persona=\"\($persona)\",advise=\($adv),soft=\($soft),hard=\($hard),applog=\($applog),fslog=\($fslog),phys=\($phys) quotaid=\"\($quotaid)\" '$time'"'  > insert_quota_detail_$time.ddl
  curl -i -X POST "http://$inf_ip:8086/write?db=quota_reports" --data-binary @insert_quota_detail_$time.ddl
  ((counter++))
done

