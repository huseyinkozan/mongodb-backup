FROM mongo:4.0

RUN apt-get update && apt-get -y install cron

ENV CRON_TIME="15 4 * * 6" \
  TZ=Europe/Istanbul \
  CRON_TZ=Europe/Istanbul

ADD run.sh /run.sh
CMD /run.sh
