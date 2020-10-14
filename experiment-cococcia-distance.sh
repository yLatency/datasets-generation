#!/bin/bash

source /home/luca/envs/ylatency/bin/activate

JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
NUM_PATTERNS=2

mvn clean install
docker-compose -f docker-compose.dev.yml build

for j in 00 05 10 15 20
do
  DIR="/home/luca/ylatency/data_/cococcia_distance_${j}"
  mkdir $DIR

  docker-compose -f docker-compose.tracing.yml up -d
  sleep 1m
  bash ingest-pipeline.sh

  for i in $(seq 1 20)
  do
      docker-compose down
      docker-compose -f docker-compose.tracing.yml stop zipkin
      python generate_injections_distance.py "0.$j"
      cd config
      mvn clean package
      cd ..
      docker-compose -f docker-compose.dev.yml build config
      docker-compose up --scale web=3 --scale gateway=2  -d
      sleep 3m
      locust --host=http://localhost  --no-web -c 20 -r 1 --run-time 30s
      docker-compose -f docker-compose.tracing.yml up -d zipkin
      sleep 5s
      t1=$( date +%s )
      locust --host=http://localhost  --no-web -c 20 -r 1 --run-time 5m
      t2=$( date +%s )
      echo $NUM_PATTERNS';'$t1';'$t2  >> $DIR/experiments.csv
      mkdir $DIR'/info_'$t1'_'$t2
      cp config/src/main/resources/shared/* $DIR'/info_'$t1'_'$t2'/'
  done

  JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
  ES_SPARK="/home/luca/lib/elasticsearch-spark-20_2.11-7.6.0.jar"  \
  python `dirname $0`/create_dataset.py $DIR 'zipkin*' && \
   COMPOSE_HTTP_TIMEOUT=200 docker-compose -f docker-compose.tracing.yml -f docker-compose.yml down && \
   docker volume prune -f && docker image prune -f

done